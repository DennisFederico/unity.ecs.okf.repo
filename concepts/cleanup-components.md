---
description: Managing entity destruction lifecycles and external resource disposal using ICleanupComponentData and UnityObjectRef in Unity Entities 1.4+.
generated:
  at: 2026-09-07T09:05:00Z
  by: curator/antigravity
sources:
  - id: unity-entities-cleanup-concept
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/components-cleanup.html
    title: Unity Entities 1.4 - Cleanup Components
  - id: unity-entities-cleanup-create
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/components-cleanup-create.html
    title: Unity Entities 1.4 - Define a Cleanup Component
status: stable
tags:
  - dots
  - ecs
  - components
  - cleanup
  - lifecycle
  - memory
title: Cleanup Components
type: Architecture Guide
---
# Cleanup Components

Cleanup components allow an entity to intercept `DestroyEntity` calls so that cleanup logic—such as recycling pooled objects, releasing native memory, or destroying linked GameObjects—can run before the entity ID is recycled.[^unity-entities-cleanup-concept]

---

## 1. How Cleanup Components Work

When `EntityManager.DestroyEntity` (or `ecb.DestroyEntity`) is called on an entity possessing a cleanup component:
1. Unity **does not** destroy the entity immediately.
2. Unity removes all **non-cleanup** components from the entity (e.g., `LocalTransform`, tags, velocities).
3. The entity ID remains alive in memory, retaining only its cleanup components.
4. Once your cleanup system finishes its work and removes the final cleanup component, Unity permanently deallocates the entity.

---

## 2. Defining Cleanup Components

Implement `ICleanupComponentData` on an unmanaged struct. If the cleanup component needs to reference a managed asset or GameObject instance, wrap it in `UnityObjectRef<T>`:[^unity-entities-cleanup-create]

```csharp
using Unity.Entities;
using UnityEngine;

// Primary gameplay tag
public struct MonsterTag : IComponentData { }

// Unmanaged cleanup component holding an asset reference
public struct MonsterCleanup : ICleanupComponentData
{
    public UnityObjectRef<GameObject> SpawnedVfxInstance;
    public int AudioEmitterId;
}
```

> [!IMPORTANT]
> **Runtime-Only Precondition**: Cleanup components (`ICleanupComponentData`, `ICleanupBufferElementData`, `ICleanupSharedComponentData`) **cannot be baked**. They are ignored during subscene baking and are not cloned during `EntityManager.Instantiate`. You must attach cleanup components at runtime (e.g., during spawning).

---

## 3. The 3-Step Lifecycle Workflow

### Step 1: Attach Cleanup Component at Runtime
When spawning or initializing the entity, add both the primary gameplay components and the cleanup component:

```csharp
using Unity.Entities;
using Unity.Transforms;

public partial struct MonsterSpawnSystem : ISystem
{
    public void OnUpdate(ref SystemState state)
    {
        var ecb = SystemAPI.GetSingleton<BeginSimulationEntityCommandBufferSystem.Singleton>()
                           .CreateCommandBuffer(state.WorldUnmanaged);

        // When spawning a new monster entity:
        Entity monster = ecb.CreateEntity();
        ecb.AddComponent<MonsterTag>(monster);
        ecb.AddComponent(monster, LocalTransform.FromPosition(0, 0, 0));

        // Attach cleanup component at runtime
        ecb.AddComponent(monster, new MonsterCleanup
        {
            SpawnedVfxInstance = default,
            AudioEmitterId = 42
        });
    }
}
```

### Step 2: Trigger Destruction Normally
Game systems destroy entities without needing to check for cleanup components:

```csharp
// Destruction strips LocalTransform and MonsterTag, leaving MonsterCleanup attached
ecb.DestroyEntity(monsterEntity);
```

### Step 3: Implement the Disposal System
Query for entities that retain `MonsterCleanup` but have lost their primary component (for spatial entities, check `.WithNone<LocalTransform>()`):

```csharp
using Unity.Entities;
using Unity.Transforms;
using Unity.Burst;

[BurstCompile]
public partial struct MonsterCleanupSystem : ISystem
{
    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        var ecb = SystemAPI.GetSingleton<EndSimulationEntityCommandBufferSystem.Singleton>()
                           .CreateCommandBuffer(state.WorldUnmanaged);

        // Entities with MonsterCleanup that lost LocalTransform were destroyed
        foreach (var (cleanup, entity) in 
            SystemAPI.Query<RefRO<MonsterCleanup>>()
                     .WithNone<LocalTransform>()
                     .WithEntityAccess())
        {
            // 1. Perform disposal or release operations
            int emitterId = cleanup.ValueRO.AudioEmitterId;
            // (Dispose audio handles, return instances to pool, etc.)

            // 2. Remove the cleanup component to allow full entity destruction
            ecb.RemoveComponent<MonsterCleanup>(entity);
        }
    }
}
```

---

## 4. Best Practices & Guidelines

* **Runtime Initialization**:
  * *Prefer*: Attaching cleanup components in spawn or initialization systems via `ecb.AddComponent<T>()` or `state.EntityManager.AddComponentData<T>()`.
  * *Avoid*: Adding cleanup components inside a `Baker<T>` (the baking pipeline ignores cleanup interfaces).
* **Destruction Detection**:
  * *Prefer*: Checking `.WithNone<LocalTransform>()` for spatial entities, as `DestroyEntity` automatically strips transforms alongside gameplay components.
  * *Prefer*: Checking `.WithNone<PrimaryTag>()` for non-spatial entities (e.g., `.WithNone<MonsterTag>()`).
* **Final Removal**:
  * Always ensure the cleanup system removes the cleanup component via `ecb.RemoveComponent<T>(entity)`. If the cleanup component is never removed, the entity will remain as a permanent memory leak.

---

## 5. Cross-References

- Component Taxonomy: [DOTS Component Declarations](ecs-components.md)
- Structural Commands: [Entity Command Buffers](ecb-structural.md)
- Entity Spawning: [Entity Spawning & Prefabs](entity-spawning.md)
- High-Performance Systems: [High-Performance Systems with ISystem](ecs-systems.md)

[^unity-entities-cleanup-concept]: Unity Entities 1.4 - Cleanup Components
[^unity-entities-cleanup-create]: Unity Entities 1.4 - Define a Cleanup Component
