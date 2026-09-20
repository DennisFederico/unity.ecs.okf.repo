---
description: Converting GameObject authoring scenes and prefabs into optimized unmanaged ECS entities using Baker<T>, TransformUsageFlags, and dependency tracking in Unity Entities 1.4+.
generated:
  at: 2026-09-07T17:35:00Z
  by: curator/antigravity
sources:
  - id: unity-entities-baking-overview
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/baking-overview.html
    title: Unity Entities 1.4 - Baking Overview
  - id: unity-entities-transform-usage-flags
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/conversion-transform-usage-flags.html
    title: Unity Entities 1.4 - Transform Usage Flags
  - id: unity-entities-bakers
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/baking-bakers.html
    title: Unity Entities 1.4 - Bakers
status: stable
tags:
  - dots
  - ecs
  - baking
  - bakers
  - authoring
  - transform-usage-flags
  - conversion
title: Authoring & Baking
type: Architecture Guide
---
# Authoring & Baking

In Unity Entities, world building and entity configuration happen inside the Unity Editor using standard GameObjects and `MonoBehaviour` authoring scripts in Subscenes. The **Baking** pipeline converts these authoring hierarchies into pure, unmanaged ECS entities and components at edit-time and build-time. Baking executes inside an isolated, headless "Baking World" and is strictly deterministic and incremental.[^unity-entities-baking-overview]

---

## 1. Architectural File Separation

To maintain clean boundaries between managed Unity authoring and Burst-compiled unmanaged runtime systems, follow strict file separation:

```
Assets/Scripts/
├── Authoring/                      <-- Managed assembly (UnityEngine dependent)
│   ├── CharacterAuthoring.cs       <-- MonoBehaviour & nested Baker<T>
│   └── SpawnerAuthoring.cs
└── Runtime/                        <-- Unmanaged DOTS assembly (Burst-compatible)
    ├── Components/
    │   ├── CharacterData.cs        <-- Pure unmanaged IComponentData structs
    │   └── SpawnerConfig.cs
    └── Systems/
        └── CharacterMovementSystem.cs
```

> [!IMPORTANT]
> **Component Isolation**: Always declare `IComponentData` structs in dedicated, pure C# files. Placing `IComponentData` structs in the same file as `MonoBehaviour` authoring classes can cause compilation assembly circularities and hinder Burst optimization.

---

## 2. `TransformUsageFlags` Optimization Matrix

When converting a GameObject to an entity via `GetEntity()` or `CreateAdditionalEntity()`, you must specify a `TransformUsageFlags` enum.[^unity-entities-transform-usage-flags] This flag dictates which transform components (`LocalTransform`, `LocalToWorld`) are added to the entity's chunk layout:

| Flag | Components Added | Memory Overhead | Best Suited For |
| :--- | :--- | :--- | :--- |
| **`TransformUsageFlags.None`** | *None* | 0 bytes | Pure data singletons, spawners, event records, gameplay managers, tags. |
| **`TransformUsageFlags.Dynamic`** | `LocalTransform`, `LocalToWorld` | ~112 bytes | Entities that translate, rotate, or scale at runtime (characters, bullets, moving props). |
| **`TransformUsageFlags.Renderable`** | `LocalToWorld` | ~64 bytes | Static environment geometry and visual props that do not move independently. |
| **`TransformUsageFlags.WorldSpace`** | `LocalTransform`, `LocalToWorld` | ~112 bytes | Entities that discard parent hierarchy and require absolute world coordinates. |
| **`TransformUsageFlags.ManualOverride`**| Custom transform setup | Variable | Advanced custom spatial indexing or third-party physics integration. |

> [!TIP]
> Always specify `TransformUsageFlags.None` for spawner entities and singletons. Adding unused `LocalTransform` components wastes chunk capacity and forces unnecessary transform hierarchy passes.

---

## 3. Canonical Baker Implementation

A Baker class inherits from `Baker<TAuthoring>` where `TAuthoring` is the target `MonoBehaviour`:[^unity-entities-bakers]

```csharp
using UnityEngine;
using Unity.Entities;

// 1. Authoring MonoBehaviour: serialized for the Inspector
public class EnemyAuthoring : MonoBehaviour
{
    public float MovementSpeed = 4.5f;
    public float MaxHealth = 100f;
    public GameObject ProjectilePrefab;

    // 2. Nested Baker translates managed fields to unmanaged ECS components
    class Baker : Baker<EnemyAuthoring>
    {
        public override void Bake(EnemyAuthoring authoring)
        {
            // Primary entity representing this GameObject
            Entity entity = GetEntity(TransformUsageFlags.Dynamic);

            // Add value components
            AddComponent(entity, new MovementSpeed { Value = authoring.MovementSpeed });
            AddComponent(entity, new Health
            {
                Current = authoring.MaxHealth,
                Max = authoring.MaxHealth
            });

            // Add tag component
            AddComponent(entity, new EnemyTag());

            // Convert and assign prefab reference
            if (authoring.ProjectilePrefab != null)
            {
                AddComponent(entity, new ProjectileLauncher
                {
                    Prefab = GetEntity(authoring.ProjectilePrefab, TransformUsageFlags.Dynamic)
                });
            }
        }
    }
}
```

---

## 4. Multi-Entity Bakers & Dynamic Buffers

A single Baker can construct multiple entities and populate dynamic buffer arrays during the conversion pass:

```csharp
using UnityEngine;
using Unity.Entities;

public class CompoundSpawnerAuthoring : MonoBehaviour
{
    public GameObject[] SpawnablePrefabs;
    public float Interval = 2.0f;

    class Baker : Baker<CompoundSpawnerAuthoring>
    {
        public override void Bake(CompoundSpawnerAuthoring authoring)
        {
            // Primary spawner entity (no transforms needed)
            Entity spawnerEntity = GetEntity(TransformUsageFlags.None);

            AddComponent(spawnerEntity, new SpawnerConfig
            {
                Interval = authoring.Interval,
                Cooldown = 0f
            });

            // Populate an ECS DynamicBuffer array during baking
            DynamicBuffer<SpawnPrefabElement> buffer = AddBuffer<SpawnPrefabElement>(spawnerEntity);
            foreach (var prefab in authoring.SpawnablePrefabs)
            {
                if (prefab != null)
                {
                    buffer.Add(new SpawnPrefabElement
                    {
                        Prefab = GetEntity(prefab, TransformUsageFlags.Dynamic)
                    });
                }
            }

            // Create an auxiliary companion sub-entity
            Entity auxiliaryEntity = CreateAdditionalEntity(TransformUsageFlags.None);
            AddComponent(auxiliaryEntity, new AuxiliaryTag());
        }
    }
}
```

---

## 5. Incremental Baking & Dependency Tracking

Unity's baking pipeline is **incremental**: it only re-bakes GameObjects whose authoring data has changed.

1. **Automatic Tracking**: The Baker automatically registers dependencies on any serialized field or component accessed on `authoring`.
2. **Explicit Asset Dependencies**: If a Baker reads external assets (such as a `ScriptableObject`, sprite atlas, or external asset array), you must explicitly register the dependency using `DependsOn()`:

```csharp
class Baker : Baker<ConfigAuthoring>
{
    public override void Bake(ConfigAuthoring authoring)
    {
        // Track external ScriptableObject asset
        DependsOn(authoring.GameSettingsAsset);

        var entity = GetEntity(TransformUsageFlags.None);
        AddComponent(entity, new RuntimeConfig
        {
            DifficultyMultiplier = authoring.GameSettingsAsset.Multiplier
        });
    }
}
```

---

## 6. Managed Asset References (`UnityObjectRef<T>`)

When an entity requires a runtime reference to an unmanaged-incompatible Unity asset (e.g., `GameObject`, `AudioClip`, `Material` companion):

```csharp
// Unmanaged component holding managed reference
public struct CompanionAudioRef : IComponentData
{
    public UnityObjectRef<AudioClip> Clip;
}
```

### Assignment Rule:
In the Baker, assign the managed object directly using **implicit conversion**:

```csharp
class Baker : Baker<AudioAuthoring>
{
    public override void Bake(AudioAuthoring authoring)
    {
        var entity = GetEntity(TransformUsageFlags.None);

        AddComponent(entity, new CompanionAudioRef
        {
            // Implicit conversion from AudioClip to UnityObjectRef<AudioClip>
            Clip = authoring.HitSoundEffect
        });
    }
}
```

> [!WARNING]
> Do not attempt to invoke non-existent factory methods such as `.FromObject()`. `UnityObjectRef<T>` handles reference encapsulation exclusively through implicit operator casting.

---

## 7. Best Practices & Guidelines

* **Transform Flag Selection**:
  * *Prefer*: `TransformUsageFlags.None` for headless data singletons, spawners, and tag-only entities.
  * *Prefer*: `TransformUsageFlags.Renderable` for static environment geometry.
  * *Prefer*: `TransformUsageFlags.Dynamic` strictly for entities that move or scale at runtime.
* **Architecture & Layout**:
  * *Prefer*: Declaring `IComponentData` structs in dedicated runtime scripts separate from `MonoBehaviour` authoring classes.
  * *Prefer*: `CreateAdditionalEntity(TransformUsageFlags)` when a single authoring GameObject represents compound entities.
* **Dependency Hygiene**:
  * *Prefer*: Calling `DependsOn()` whenever reading external `ScriptableObject` assets or asset arrays to guarantee proper cache invalidation.
* **Safety Rules**:
  * *Avoid*: Defaulting to `TransformUsageFlags.Dynamic` on static objects (wastes memory and CPU hierarchy cycles).
  * *Avoid*: Calling factory methods on `UnityObjectRef<T>` (use implicit conversion).

---

## 8. Cross-References

- ECS Architecture: [ECS Fundamentals vs OOP](ecs-fundamentals.md)
- Component Declarations: [DOTS Component Declarations](ecs-components.md)
- Singletons: [Singleton Components](singletons.md)
- Dynamic Buffers: [Dynamic Buffers](dynamic-buffers.md)
- Entity Spawning: [Entity Spawning & Prefabs](entity-spawning.md)
- Subscenes & Architecture: [DOTS/ECS Scene Architecture & Subscenes](ecs-scene-architecture.md)
- Agentic Assembly: [Agentic DOTS/ECS Scene Assembly](agentic-scene-assembly.md)

[^unity-entities-baking-overview]: Unity Entities 1.4 - Baking Overview
[^unity-entities-transform-usage-flags]: Unity Entities 1.4 - Transform Usage Flags
[^unity-entities-bakers]: Unity Entities 1.4 - Bakers
