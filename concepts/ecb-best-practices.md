---
description: Parallel recording with EntityCommandBuffer.ParallelWriter, deterministic playback with sort keys, deferred entity references, and system-managed vs manual ECB lifecycles in Unity Entities 1.4+.
generated:
  at: 2026-09-07T14:57:00Z
  by: curator/antigravity
sources:
  - id: unity-entities-ecb
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/systems-entity-command-buffers.html
    title: Unity Entities 1.4 - Entity Command Buffers
  - id: unity-entities-ecb-jobs
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/systems-entity-command-buffers-jobs.html
    title: Unity Entities 1.4 - Entity Command Buffers in Jobs
  - id: unity-entities-ecb-determinism
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/systems-entity-command-buffers-determinism.html
    title: Unity Entities 1.4 - Deterministic Playback and Sort Keys
status: stable
tags:
  - dots
  - ecs
  - ecb
  - parallel-writer
  - determinism
  - sort-key
  - lifecycle
title: EntityCommandBuffer Best Practices & Parallel Writing
type: Architecture Guide
---
# EntityCommandBuffer Best Practices & Parallel Writing

In Unity Entities, recording structural changes across worker threads requires thread-safe command collection, deterministic playback sequencing, and correct lifecycle management. An improper ECB implementation can cause data races, non-deterministic gameplay bugs, or fatal runtime exceptions.[^unity-entities-ecb]

---

## 1. Thread-Safe Parallel Recording (`ParallelWriter`)

Standard `EntityCommandBuffer` instances are single-threaded and cannot be accessed directly from worker threads.[^unity-entities-ecb-jobs] When scheduling parallel jobs (`IJobEntity` or `IJobChunk`), convert the command buffer to an `EntityCommandBuffer.ParallelWriter` via `.AsParallelWriter()`:

```csharp
using Unity.Entities;
using Unity.Transforms;
using Unity.Burst;

[BurstCompile]
[UpdateInGroup(typeof(SimulationSystemGroup))]
public partial struct ProjectileDespawnSystem : ISystem
{
    [BurstCompile]
    public void OnCreate(ref SystemState state)
    {
        state.RequireForUpdate<Lifetime>();
    }

    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        // 1. Retrieve the system-managed ECB singleton
        var ecbSingleton = SystemAPI.GetSingleton<EndSimulationEntityCommandBufferSystem.Singleton>();
        EntityCommandBuffer ecb = ecbSingleton.CreateCommandBuffer(state.WorldUnmanaged);

        // 2. Schedule parallel job passing the ParallelWriter
        var job = new DespawnExpiredJob
        {
            DeltaTime = SystemAPI.Time.DeltaTime,
            ECB = ecb.AsParallelWriter()
        };

        state.Dependency = job.ScheduleParallel(state.Dependency);
    }
}

[BurstCompile]
public partial struct DespawnExpiredJob : IJobEntity
{
    public float DeltaTime;
    public EntityCommandBuffer.ParallelWriter ECB;

    // [ChunkIndexInQuery] provides the sortKey for deterministic playback
    void Execute([ChunkIndexInQuery] int sortKey, Entity entity, ref Lifetime lifetime)
    {
        lifetime.Value -= DeltaTime;

        if (lifetime.Value <= 0f)
        {
            // Record command into the parallel writer with the sortKey
            ECB.DestroyEntity(sortKey, entity);
        }
    }
}
```

---

## 2. Deterministic Playback & Sort Keys

Because worker threads process chunks concurrently and complete in arbitrary order based on CPU scheduling, recorded commands arrive non-sequentially across thread buffers.[^unity-entities-ecb-determinism]

To guarantee identical, deterministic execution across runs, the ECB system merges all worker recordings and sorts them by their `sortKey` integer before playback:

```
Worker Thread 1 (Chunk 3): [Cmd: Destroy E10 (sortKey: 3)]
Worker Thread 2 (Chunk 0): [Cmd: Spawn E1   (sortKey: 0)] ──► [ECB Sorter] ──► [Ordered Playback]
Worker Thread 3 (Chunk 1): [Cmd: Destroy E4  (sortKey: 1)]                      1. sortKey 0
                                                                                2. sortKey 1
                                                                                3. sortKey 3
```

### Choosing the Correct Sort Key

| Parameter Attribute | Scope | Overhead | Best Suited For |
| :--- | :--- | :--- | :--- |
| **`[ChunkIndexInQuery]`** | Per-chunk integer | Minimal / Zero | General destruction, spawning, and component tagging where ordering between entities in the same chunk does not matter. |
| **`[EntityIndexInQuery]`** | Global query entity index | Low (tracking cost) | Scenarios where strict, entity-by-entity deterministic ordering is required even within the same chunk. |

> [!IMPORTANT]
> **Never Pass Hardcoded Zero**: Passing a constant integer (such as `0`) as the `sortKey` across parallel threads collapses deterministic ordering. The ECB system cannot resolve which thread recorded first, resulting in non-deterministic command playback order between frames.

---

## 3. Deferred Entity References & Command Chaining

When creating or instantiating entities through an ECB, the actual entity does not exist yet. The ECB returns a temporary **deferred entity placeholder** (represented internally with a negative index):

```csharp
[BurstCompile]
public partial struct SpawnWaveJob : IJobEntity
{
    public EntityCommandBuffer.ParallelWriter ECB;

    void Execute([ChunkIndexInQuery] int sortKey, in SpawnerConfig spawner)
    {
        // 1. Returns a deferred entity placeholder
        Entity newEntity = ECB.Instantiate(sortKey, spawner.Prefab);

        // 2. Safely chain subsequent commands referencing the placeholder
        ECB.SetComponent(sortKey, newEntity, new LocalTransform
        {
            Position = spawner.SpawnPosition,
            Scale = 1f
        });

        ECB.AddComponent(sortKey, newEntity, new ActiveTag());
    }
}
```

### Deferred Entity Rules:
* **Chaining Allowed**: You can pass the placeholder `Entity` into subsequent ECB calls (`AddComponent`, `SetComponent`, `SetBuffer`, `DestroyEntity`) in the *same* command buffer. During playback, the ECB resolves the placeholder to the real entity ID and updates all command targets automatically.
* **No Immediate Reads**: You **cannot** query, inspect, or read component data from a placeholder `Entity` inside the job or system. Attempting to call `SystemAPI.GetComponent<T>(newEntity)` or `EntityManager.GetComponentData<T>(newEntity)` throws an exception because the entity has not yet been instantiated in the World.

---

## 4. System-Managed vs Manual ECB Lifecycle

Understanding who owns the lifecycle of an `EntityCommandBuffer` is critical to avoiding crashes and native memory leaks:

| Feature | System-Managed ECB | Manual Custom ECB |
| :--- | :--- | :--- |
| **Creation** | `SystemAPI.GetSingleton<T.Singleton>().CreateCommandBuffer(...)` | `new EntityCommandBuffer(Allocator.TempJob)` |
| **Playback** | Automated at group boundary | Explicit: `ecb.Playback(EntityManager)` on Main Thread |
| **Disposal** | Automated by the managing system | Explicit: `ecb.Dispose()` or `ecb.Dispose(JobHandle)` |
| **Primary Use Case** | All gameplay, simulation, and parallel systems | Custom test harnesses, editor tools, or isolated manual playback |

### Critical Lifecycle Constraints:
1. **Never Playback System-Managed ECBs**: Calling `ecb.Playback()` on a system-managed buffer triggers an `InvalidOperationException` when the owning system runs its automated playback pass.
2. **Never Dispose System-Managed ECBs**: The owning `EntityCommandBufferSystem` is responsible for freeing the buffer memory. Manual disposal causes double-free exceptions.
3. **Always Dispose Manual ECBs**: Custom ECBs allocated with `Allocator.TempJob` or `Allocator.Persistent` will leak unmanaged memory if `ecb.Dispose()` is omitted.

---

## 5. Best Practices & Guidelines

* **Parallel Recording**:
  * *Prefer*: Calling `.AsParallelWriter()` when passing an ECB into parallel jobs.
  * *Prefer*: Using `[ChunkIndexInQuery] int sortKey` in `IJobEntity` as the default sort key for parallel recording.
  * *Prefer*: Using `[EntityIndexInQuery] int sortKey` when intra-chunk entity ordering must be strictly preserved.
* **Deferred Entity Chaining**:
  * *Prefer*: Passing placeholder entities directly to subsequent `.AddComponent()` or `.SetComponent()` calls within the same ECB.
  * *Avoid*: Attempting to read components from or query a placeholder entity before the command buffer plays back.
* **Lifecycle Discipline**:
  * *Prefer*: System-managed command buffers (`BeginSimulation...` / `EndSimulation...`) for all runtime systems.
  * *Avoid*: Passing a constant integer (e.g., `0`) to `ParallelWriter` methods across concurrent threads.
  * *Avoid*: Calling `.Playback()` or `.Dispose()` on system-managed ECBs.
  * *Avoid*: Forgetting to call `.Dispose()` on manually instantiated `new EntityCommandBuffer(...)` instances.

---

## 6. Cross-References

- Sync Points & Foundations: [Entity Command Buffers & Sync Points](ecb-structural.md)
- Systems Architecture: [High-Performance Systems with ISystem](ecs-systems.md)
- Parallel Jobs: [Jobs & Native Collections](jobs-native-collections.md)
- Batch Instantiation: [Entity Spawning & Prefabs](entity-spawning.md)

[^unity-entities-ecb]: Unity Entities 1.4 - Entity Command Buffers
[^unity-entities-ecb-jobs]: Unity Entities 1.4 - Entity Command Buffers in Jobs
[^unity-entities-ecb-determinism]: Unity Entities 1.4 - Deterministic Playback and Sort Keys
