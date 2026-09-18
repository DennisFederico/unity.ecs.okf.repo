---
description: Patterns for bridging pure unmanaged DOTS/ECS with managed GameObjects, Particle Systems, Audio, and UI using SystemBase, UnityObjectRef, and cleanup lifecycles in Unity Entities 1.4+.
generated:
  at: 2026-09-07T19:25:00Z
  by: curator/antigravity
sources:
  - id: unity-entities-systembase
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/systems-systembase.html
    title: Unity Entities 1.4 - SystemBase
  - id: unity-entities-hybrid-components
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/hybrid-components.html
    title: Unity Entities 1.4 - Companion GameObjects
  - id: unity-entities-cleanup-components
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/components-cleanup.html
    title: Unity Entities 1.4 - Cleanup Components
status: stable
tags:
  - dots
  - ecs
  - hybrid
  - systembase
  - gameobjects
  - unityobjectref
  - companion
title: Hybrid ECS & Companion GameObjects
type: Architecture Guide
---
# Hybrid ECS & Companion GameObjects

While core gameplay simulation in DOTS belongs in unmanaged, Burst-compiled `ISystem` structs, production games frequently require integration with engine features that remain fundamentally managed (such as AudioSources, Shuriken Particle Systems, VFX Graph, NavMeshAgents, and third-party SDKs). The **Hybrid ECS** paradigm provides structured patterns to bridge unmanaged Entities with managed GameObjects without sacrificing simulation performance.[^unity-entities-hybrid-components]

---

## 1. Dual Bridging Paradigms

| Paradigm | Master / Authority | Companion / Listener | Primary Use Case |
| :--- | :--- | :--- | :--- |
| **Entities-First** (Companion Pattern) | Unmanaged Entity (owns transform, health, physics) | Managed `GameObject` (follows entity transform) | Audio triggers, visual particle systems, NavMesh companions, complex ragdolls. |
| **GameObject-First** (Bridge Pattern) | Managed `MonoBehaviour` (owns UI, canvas, input) | Unmanaged Entity (receives data updates) | UI Toolkit screens, UGUI HUDs, dialogue trees, game settings menus. |

---

## 2. Unmanaged Managed References (`UnityObjectRef<T>`)

To allow an unmanaged `IComponentData` or `ICleanupComponentData` struct to hold a reference to a managed `UnityEngine.Object` (such as a `GameObject`, `AudioClip`, or `Transform`), Unity provides the `UnityObjectRef<T>` struct:

```csharp
using Unity.Entities;
using UnityEngine;

// 1. Unmanaged component holding a managed GameObject reference
public struct CompanionLink : IComponentData
{
    public UnityObjectRef<GameObject> Target;
}

// 2. Cleanup component to manage the companion's lifecycle
public struct CompanionCleanup : ICleanupComponentData
{
    public UnityObjectRef<GameObject> Instance;
}
```

### Conversion & Casting Rules:
`UnityObjectRef<T>` relies strictly on C# cast operators. It does **not** contain factory methods:
* **Managed to ECS (Implicit Cast)**:
  ```csharp
  // Implicitly converts GameObject to UnityObjectRef<GameObject>
  companionLink.Target = myGameObject;
  ```
* **ECS to Managed (Explicit Cast)**:
  ```csharp
  // Explicitly cast back to access managed methods and properties
  GameObject go = (GameObject)companionLink.Target;
  go.transform.position = worldPosition;
  ```

> [!WARNING]
> Do not attempt to invoke non-existent methods like `.FromObject()` or `UnityObjectRef.Instantiate()`. Always use implicit assignment to store, and explicit casting to retrieve.

---

## 3. The `SystemBase` Managed Bridge

While `ISystem` is an unmanaged `struct` compiled by Burst, `SystemBase` is a managed `class` that runs on the Mono/.NET runtime.[^unity-entities-systembase] It can allocate managed memory, call Unity engine APIs, and invoke C# delegates.

### Key Rules for `SystemBase`:
1. **Fully Qualify UnityEngine.Object Methods**: Because `SystemBase` does not inherit from `UnityEngine.Object`, static helper methods like `Instantiate` or `Destroy` must be explicitly qualified (e.g., `UnityEngine.Object.Instantiate(...)`, `UnityEngine.Object.Destroy(...)`).
2. **Accessing Unmanaged World for ECBs**: When obtaining an `EntityCommandBuffer` inside `SystemBase`, use `World.Unmanaged` (do not look for `state.WorldUnmanaged`, which only exists in `ISystem`).

---

## 4. Companion Transform Synchronization Pattern

Below is the canonical `SystemBase` implementation for instantiating companion GameObjects and synchronizing their transforms with ECS simulation entities:

```csharp
using Unity.Entities;
using Unity.Transforms;
using UnityEngine;

[UpdateInGroup(typeof(PresentationSystemGroup))]
public partial class CompanionSyncSystem : SystemBase
{
    protected override void OnUpdate()
    {
        var ecbSingleton = SystemAPI.GetSingleton<BeginPresentationEntityCommandBufferSystem.Singleton>();
        var ecb = ecbSingleton.CreateCommandBuffer(World.Unmanaged);

        // 1. Initialization pass: instantiate companion GameObjects
        foreach (var (link, entity) in 
            SystemAPI.Query<RefRO<CompanionLink>>()
                     .WithNone<CompanionCleanup>()
                     .WithEntityAccess())
        {
            // Explicitly cast to GameObject and instantiate
            GameObject prefab = (GameObject)link.ValueRO.Target;
            GameObject instance = UnityEngine.Object.Instantiate(prefab);

            // Attach cleanup component with the live instance reference
            ecb.AddComponent(entity, new CompanionCleanup
            {
                Instance = instance
            });
        }

        // 2. Sync pass: update GameObject transforms to match ECS LocalToWorld
        foreach (var (transform, cleanup) in 
            SystemAPI.Query<RefRO<LocalToWorld>, RefRO<CompanionCleanup>>())
        {
            GameObject instance = (GameObject)cleanup.ValueRO.Instance;
            if (instance != null)
            {
                instance.transform.SetPositionAndRotation(
                    transform.ValueRO.Position, 
                    transform.ValueRO.Rotation
                );
            }
        }
    }
}
```

---

## 5. Deterministic Lifecycle Cleanup

When an entity is destroyed via `ecb.DestroyEntity(entity)`, the entity is not immediately deallocated if it holds an `ICleanupComponentData`.[^unity-entities-cleanup-components] This allows a cleanup system to intercept the deletion and clean up the companion `GameObject`:

```csharp
[UpdateInGroup(typeof(PresentationSystemGroup))]
[UpdateAfter(typeof(CompanionSyncSystem))]
public partial class CompanionCleanupSystem : SystemBase
{
    protected override void OnUpdate()
    {
        var ecbSingleton = SystemAPI.GetSingleton<BeginPresentationEntityCommandBufferSystem.Singleton>();
        var ecb = ecbSingleton.CreateCommandBuffer(World.Unmanaged);

        // Entities that lost CompanionLink but still possess CompanionCleanup are destroyed
        foreach (var (cleanup, entity) in 
            SystemAPI.Query<RefRO<CompanionCleanup>>()
                     .WithNone<CompanionLink>()
                     .WithEntityAccess())
        {
            GameObject instance = (GameObject)cleanup.ValueRO.Instance;
            if (instance != null)
            {
                UnityEngine.Object.Destroy(instance);
            }

            // Remove cleanup component to finalize entity deallocation
            ecb.RemoveComponent<CompanionCleanup>(entity);
        }
    }
}
```

---

## 6. GameObject-First Access (`DefaultGameObjectInjectionWorld`)

When standard `MonoBehaviour` scripts (such as UI buttons, HUD controllers, or settings menus) need to read from or dispatch commands to the ECS world:

```csharp
using UnityEngine;
using Unity.Entities;

public class PlayerHealthUI : MonoBehaviour
{
    void Update()
    {
        World world = World.DefaultGameObjectInjectionWorld;
        if (world == null || !world.IsCreated) return;

        var entityManager = world.EntityManager;

        // 1. Complete pending worker jobs before accessing unmanaged data
        entityManager.CompleteAllTrackedJobs();

        // 2. Query singleton player health safely
        EntityQuery query = entityManager.CreateEntityQuery(typeof(PlayerTag), typeof(Health));
        if (query.HasSingleton<Health>())
        {
            Health health = query.GetSingleton<Health>();
            // Update UI sliders or text labels
        }
    }
}
```

---

## 7. Best Practices & Guidelines

* **System Selection**:
  * *Prefer*: `ISystem` for pure simulation, math, movement, and physics.
  * *Prefer*: `SystemBase` strictly for companion synchronizations, audio triggering, and UI bridging.
* **Type Conversion**:
  * *Prefer*: Implicit casting to store `UnityEngine.Object` in `UnityObjectRef<T>`.
  * *Prefer*: Explicit casting `(T)unityObjectRef` when accessing members on managed instances.
* **Lifecycle Management**:
  * *Prefer*: `ICleanupComponentData` to destroy companion GameObjects when their parent entity is deleted.
* **Job Safety in MonoBehaviours**:
  * *Prefer*: Calling `world.EntityManager.CompleteAllTrackedJobs()` before reading or writing ECS data from `MonoBehaviour` updates.
* **Common Pitfalls**:
  * *Avoid*: Calling factory methods on `UnityObjectRef<T>` (they do not exist).
  * *Avoid*: Calling unqualified `Instantiate()` inside `SystemBase` (must prefix with `UnityEngine.Object.`).
  * *Avoid*: Storing managed object references directly in standard `IComponentData` without `UnityObjectRef<T>` (breaks unmanaged memory layouts).

---

## 8. Cross-References

- Unmanaged Components: [DOTS Component Declarations](ecs-components.md)
- Cleanup Lifecycle: [Cleanup Components](cleanup-components.md)
- Systems Architecture: [High-Performance Systems with ISystem](ecs-systems.md)
- Scene Setup: [DOTS/ECS Scene Architecture & Subscenes](ecs-scene-architecture.md)
- UI Performance: [UI Toolkit & DOTS Integration](unity-ui-performance.md)

[^unity-entities-systembase]: Unity Entities 1.4 - SystemBase
[^unity-entities-hybrid-components]: Unity Entities 1.4 - Companion GameObjects
[^unity-entities-cleanup-components]: Unity Entities 1.4 - Cleanup Components
