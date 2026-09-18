---
description: Managing structural changes, understanding synchronization points (sync points), and delegating mutations to Entity Command Buffers (ECBs) in Unity Entities 1.4+.
generated:
  at: 2026-09-07T14:35:00Z
  by: curator/antigravity
sources:
  - id: unity-entities-structural-changes
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/concepts-structural-changes.html
    title: Unity Entities 1.4 - Structural Changes
  - id: unity-entities-sync-points
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/performance-sync-points.html
    title: Unity Entities 1.4 - Sync Points
  - id: unity-entities-ecb
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/systems-entity-command-buffers.html
    title: Unity Entities 1.4 - Entity Command Buffers
status: stable
tags:
  - dots
  - ecs
  - ecb
  - structural-changes
  - sync-points
  - performance
title: Entity Command Buffers & Sync Points
type: Architecture Guide
---
# Entity Command Buffers & Sync Points

In Unity Entities, performance relies on storing unmanaged component data in contiguous 16KB memory chunks grouped by Archetype. When an operation changes an entity's archetype or memory footprint, it executes a **Structural Change**. Understanding the performance implications of structural changes and delegating them to **Entity Command Buffers (ECBs)** is vital for maintaining high frame rates and multi-core CPU utilization.[^unity-entities-structural-changes]

---

## 1. What is a Structural Change?

A structural change occurs whenever an operation alters the archetype of an entity or invalidates existing chunk layout memory:

* **Entity Creation & Destruction**: `EntityManager.CreateEntity`, `EntityManager.DestroyEntity`, `EntityManager.Instantiate`.
* **Component Mutation**: `EntityManager.AddComponent`, `EntityManager.RemoveComponent`.
* **Shared Component Modification**: Changing a shared component value via `EntityManager.SetSharedComponentData`.

### Memory Impact:
When an entity's archetype changes:
1. The entity and all its remaining component data must be moved from its current chunk to a chunk matching the new archetype.
2. If no chunk with available capacity exists for the new archetype, a new 16KB chunk is allocated.
3. Existing pointers, direct component references, and cached chunk arrays are invalidated.

---

## 2. Synchronization Points (Sync Points)

Because structural changes reorder chunk memory and invalidate component pointers, they **cannot** happen while worker thread jobs or queries are actively reading or writing component data.[^unity-entities-sync-points]

A **Sync Point** (synchronization barrier) is a point in frame execution where the main thread halts execution and waits for **all currently running jobs to complete** before proceeding:

```
Frame Timeline (Without ECB - Multiple Hard Sync Points):
Worker Threads: [Job A Running] ───► STALL (Wait for Sync Point) ───► [Job B Running]
Main Thread:    [System Logic] ────► [Structural Change] ───────────► [System Logic]
                                          ▲
                                          └── Hard Sync Point (CPU Bubbles & Idle Threads)
```

### Why Sync Points Degrade Performance:
* **CPU Pipeline Stalls**: The main thread sits idle waiting for background worker threads to finish executing their chunk batches.
* **Worker Thread Starvation**: Worker threads finish their scheduled chunks and remain idle with no work available until the structural mutation finishes.
* **Multithreading Collapse**: Triggering multiple sync points across a single frame serializes execution, defeating the benefits of the Unity Job System.

### Hidden Sync Points:
Sync points are not limited to explicit `EntityManager.AddComponent` calls:
* **Immediate Array Extractions**: Calling `EntityQuery.ToEntityArray(Allocator.Temp)` or `EntityQuery.ToComponentDataArray<T>()` forces a sync point if scheduled jobs have pending write dependencies on those components.
* **Direct EntityManager Access**: Accessing `EntityManager` component lookups while jobs holding write access are scheduled.

---

## 3. Delegating to Entity Command Buffers (ECBs)

To eliminate mid-frame sync points, structural changes must be deferred using an **Entity Command Buffer (ECB)**.[^unity-entities-ecb]

Instead of mutating chunks immediately, the system records commands into an unmanaged memory buffer. These commands are executed as a single batched playback at a predetermined point in the frame pipeline (managed by dedicated `EntityCommandBufferSystem` passes):

```
Frame Timeline (With System-Managed ECB - Zero Mid-Frame Sync Points):
Worker Threads: [Job A Running] ────────────────────────────────────► [Job B Running]
Main Thread:    [System Logic: Record ECB] ─────────────────────────► [System Logic]
                                                                            │
                                                     [Group Boundary: Single ECB Playback]
```

### SystemAPI Idiomatic Pattern (`ISystem`)
In Unity Entities 1.4+, retrieve the ECB singleton from the appropriate system group:

```csharp
using Unity.Entities;
using Unity.Transforms;
using Unity.Burst;

[BurstCompile]
[UpdateInGroup(typeof(SimulationSystemGroup))]
public partial struct EnemySpawnerSystem : ISystem
{
    [BurstCompile]
    public void OnCreate(ref SystemState state)
    {
        state.RequireForUpdate<SpawnerConfig>();
    }

    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        // 1. Retrieve the command buffer singleton for BeginSimulation
        var ecbSingleton = SystemAPI.GetSingleton<BeginSimulationEntityCommandBufferSystem.Singleton>();
        
        // 2. Create the command buffer bound to the current unmanaged world
        EntityCommandBuffer ecb = ecbSingleton.CreateCommandBuffer(state.WorldUnmanaged);

        // 3. Record commands during iteration without triggering a sync point
        foreach (var (spawner, transform) in 
            SystemAPI.Query<RefRW<SpawnerConfig>, RefRO<LocalTransform>>())
        {
            spawner.ValueRW.Cooldown -= SystemAPI.Time.DeltaTime;
            if (spawner.ValueRO.Cooldown <= 0f)
            {
                spawner.ValueRW.Cooldown = spawner.ValueRO.Interval;

                // Deferred instantiation and component initialization
                Entity spawnedEntity = ecb.Instantiate(spawner.ValueRO.Prefab);
                ecb.SetComponent(spawnedEntity, LocalTransform.FromPosition(transform.ValueRO.Position));
                ecb.AddComponent(spawnedEntity, new ActiveTag());
            }
        }

        // Automatic: Do NOT call ecb.Playback() or ecb.Dispose()!
    }
}
```

---

## 4. Built-in ECB Systems & Playback Phasing

Unity provides built-in `EntityCommandBufferSystem` instances stationed at the boundaries of standard System Groups. Choosing the correct ECB system ensures data consistency across dependent systems:

| System Group Phase | Built-in ECB System Singleton | Optimal Use Cases |
| :--- | :--- | :--- |
| **Initialization** | `BeginInitializationEntityCommandBufferSystem` | World bootstrap, pre-simulation setup, input prep. |
| | `EndInitializationEntityCommandBufferSystem` | Finalizing initialization state before simulation begins. |
| **Fixed Simulation** | `BeginFixedStepSimulationEntityCommandBufferSystem` | Physics and fixed-timestep entity spawning. |
| | `EndFixedStepSimulationEntityCommandBufferSystem` | Post-physics cleanup and state synchronization. |
| **Simulation** | `BeginSimulationEntityCommandBufferSystem` | Spawning gameplay entities, projectiles, and initial states needed by simulation systems. |
| | `EndSimulationEntityCommandBufferSystem` | Destroying dead entities, removing tags, and deferred state transitions after simulation completes. |
| **Presentation** | `BeginPresentationEntityCommandBufferSystem` | Visual companion updates, audio trigger entities, transform sync. |

> [!NOTE]
> There is **no** `EndPresentationEntityCommandBufferSystem`. Commands needed after presentation should be scheduled into `BeginInitializationEntityCommandBufferSystem` for the subsequent frame.

---

## 5. Architectural Strategies to Minimize Structural Changes

Even when batched via ECBs, structural changes incur chunk movement overhead during playback. High-performance architectures minimize structural changes through alternative patterns:

### 1. Prefer `IEnableableComponent` over Tag Adding/Removing
Adding or removing a tag component forces an archetype transition. Implementing `IEnableableComponent` allows toggling component presence via a chunk bitmask:
* **Archetype Change**: ❌ No (Entity stays in the same chunk).
* **Structural Change**: ❌ No.
* **Sync Point**: ❌ No.

### 2. Use Dynamic Buffers for Dynamic Lists
Rather than adding multiple child or relation components dynamically at runtime, declare a `DynamicBuffer<T>` with an appropriate `[InternalBufferCapacity]`. Modifying elements within a buffer avoids archetype mutation.

### 3. Batch Chunk Operations
When structural changes are unavoidable (e.g., destroying all entities of a type during level unload), execute them across entire queries using `EntityManager.DestroyEntity(EntityQuery query)` rather than individual entity iterations.

---

## 6. Best Practices & Guidelines

* **ECB Selection**:
  * *Prefer*: Using `BeginSimulationEntityCommandBufferSystem` for entity spawning so newly created entities are available to all subsequent simulation systems in the current frame.
  * *Prefer*: Using `EndSimulationEntityCommandBufferSystem` for entity destruction so queries in earlier simulation systems are not disrupted mid-frame.
* **Lifecycle Automation**:
  * *Prefer*: Relying on the built-in ECB systems to manage playback and disposal.
  * *Avoid*: Calling `ecb.Playback()` or `ecb.Dispose()` on command buffers obtained from an `EntityCommandBufferSystem.Singleton` (triggers runtime playback exceptions).
* **Sync Point Elimination**:
  * *Prefer*: `IEnableableComponent` toggling (`EnabledRefRW<T>`) for frequent state transitions.
  * *Avoid*: Calling `EntityManager.CreateEntity`, `AddComponent`, or `DestroyEntity` in per-frame update loops.
  * *Avoid*: Calling `EntityQuery.ToEntityArray()` in per-frame update loops when `SystemAPI.Query` can be iterated directly.

---

## 7. Cross-References

- Memory & Chunks: [ECS Fundamentals vs OOP](ecs-fundamentals.md)
- Component Declarations: [DOTS Component Declarations](ecs-components.md)
- Zero-Cost Toggling: [Enableable Components](enableable-components.md)
- System Lifecycles: [High-Performance Systems with ISystem](ecs-systems.md)
- Parallel Recording & Sort Keys: [EntityCommandBuffer Best Practices](ecb-best-practices.md)
- Batch Instantiation: [Entity Spawning & Prefabs](entity-spawning.md)

[^unity-entities-structural-changes]: Unity Entities 1.4 - Structural Changes
[^unity-entities-sync-points]: Unity Entities 1.4 - Sync Points
[^unity-entities-ecb]: Unity Entities 1.4 - Entity Command Buffers
