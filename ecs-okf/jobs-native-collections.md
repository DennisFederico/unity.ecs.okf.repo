---
description: Multithreaded execution using IJobEntity and IJobParallelFor, NativeContainer lifecycles, and thread-safe parallel writers in Unity Entities 1.4+.
generated:
  at: 2026-09-07T12:25:00Z
  by: curator/antigravity
sources:
  - id: unity-entities-ijobentity
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/systems-ijobentity.html
    title: Unity Entities 1.4 - IJobEntity
  - id: unity-collections-allocators
    resource: https://docs.unity3d.com/Packages/com.unity.collections@2.4/manual/allocator-overview.html
    title: Unity Collections 2.4 - Allocator Overview
status: stable
tags:
  - dots
  - ecs
  - jobs
  - native-collections
  - burst
  - performance
title: Jobs & Native Collections
type: Architecture Guide
---
# Jobs & Native Collections

Unmanaged DOTS execution achieves multithreaded scaling by pairing the C# Job System with **NativeContainers** (`NativeArray`, `NativeList`, `NativeParallelHashMap`, `NativeParallelMultiHashMap`, `NativeQueue`). Native collections bypass garbage collection and provide contiguous memory for Burst vectorization.[^unity-collections-allocators]

---

## 1. Native Allocator Lifecycles

Every native container must be initialized with an explicit memory allocator:

| Allocator | Lifespan | Usage Rule | Disposal Pattern |
| :--- | :--- | :--- | :--- |
| **`Allocator.Temp`** | 1 frame (stack-like) | Rapid local calculation inside a single method. Do not pass to scheduled jobs. | Disposed automatically or manually before method exit. |
| **`Allocator.TempJob`** | Job duration (≤4 frames) | Passing intermediate buffers between systems and scheduled jobs. | Must be explicitly disposed, ideally via `collection.Dispose(JobHandle)`. |
| **`Allocator.Persistent`** | Indefinite (heap) | Long-lived collections stored as fields on `ISystem` structs. | Must be manually allocated in `OnCreate` and disposed in `OnDestroy`. |

---

## 2. Parallel Hash Map Job with ParallelWriter

When worker threads insert data concurrently into a shared collection, use `ParallelWriter` to guarantee lock-free, thread-safe writes:

```csharp
using Unity.Jobs;
using Unity.Collections;
using Unity.Burst;
using Unity.Mathematics;

[BurstCompile]
public struct SpatialPartitionJob : IJobParallelFor
{
    [ReadOnly] public NativeArray<float3> Positions;
    public float CellSize;

    // ParallelWriter allows concurrent, race-free insertions across threads
    public NativeParallelMultiHashMap<int, int>.ParallelWriter SpatialMap;

    public void Execute(int index)
    {
        float3 pos = Positions[index];
        int cellHash = GetCellHash(pos, CellSize);
        SpatialMap.Add(cellHash, index);
    }

    private static int GetCellHash(float3 pos, float cellSize)
    {
        int3 cell = (int3)math.floor(pos / cellSize);
        return cell.x * 73856093 ^ cell.y * 19349663 ^ cell.z * 83492791;
    }
}
```

---

## 3. System Lifecycle & Deferred Disposal

Manage long-lived containers in `OnCreate`/`OnDestroy` and schedule jobs with chained dependency handles:[^unity-entities-ijobentity]

```csharp
using Unity.Entities;
using Unity.Transforms;
using Unity.Collections;
using Unity.Burst;
using Unity.Mathematics;

[BurstCompile]
public partial struct SpatialHashSystem : ISystem
{
    private NativeParallelMultiHashMap<int, int> _spatialMap;

    [BurstCompile]
    public void OnCreate(ref SystemState state)
    {
        // Persistent allocation for multi-frame reuse
        _spatialMap = new NativeParallelMultiHashMap<int, int>(10000, Allocator.Persistent);
        state.RequireForUpdate<LocalTransform>();
    }

    [BurstCompile]
    public void OnDestroy(ref SystemState state)
    {
        // Always dispose persistent collections to prevent memory leaks
        if (_spatialMap.IsCreated)
        {
            _spatialMap.Dispose();
        }
    }

    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        EntityQuery query = SystemAPI.QueryBuilder().WithAll<LocalTransform>().Build();
        int count = query.CalculateEntityCount();

        if (_spatialMap.Capacity < count)
        {
            _spatialMap.Capacity = count * 2;
        }
        _spatialMap.Clear();

        // TempJob allocations for job execution
        NativeArray<float3> positions = new NativeArray<float3>(count, Allocator.TempJob);
        NativeArray<LocalTransform> transforms = query.ToComponentDataArray<LocalTransform>(Allocator.TempJob);

        for (int i = 0; i < count; i++)
        {
            positions[i] = transforms[i].Position;
        }

        var job = new SpatialPartitionJob
        {
            Positions = positions,
            CellSize = 5.0f,
            SpatialMap = _spatialMap.AsParallelWriter()
        };

        // 1. Schedule job and chain dependency handle
        state.Dependency = job.Schedule(count, 64, state.Dependency);

        // 2. Defer disposal until worker threads finish without blocking the main thread
        positions.Dispose(state.Dependency);
        transforms.Dispose(state.Dependency);
    }
}
```

---

## 4. Best Practices & Guidelines

* **Concurrency Safety**:
  * *Prefer*: `[ReadOnly]` on all container fields where worker threads only read data, enabling maximum parallel concurrency.
  * *Prefer*: Calling `.AsParallelWriter()` when writing into `NativeParallelHashMap`, `NativeParallelMultiHashMap`, or `NativeQueue` inside parallel jobs.
* **Leak Prevention & Deferred Disposal**:
  * *Prefer*: Passing `state.Dependency` into `collection.Dispose(state.Dependency)` for `TempJob` collections to free memory asynchronously once the job completes.
  * *Avoid*: Storing persistent heap allocations on temporary structs without pairing them with a `.Dispose()` call in `OnDestroy`.
* **Minimizing Reallocations**:
  * *Prefer*: Reusing persistent collections across frames by clearing them (`_collection.Clear()`) instead of allocating new containers each update.

---

## 5. Cross-References

- System Architecture: [High-Performance Systems with ISystem](ecs-systems.md)
- Query Building: [Entity Queries & Filtering](entity-queries.md)
- Dynamic Arrays: [Dynamic Buffers](dynamic-buffers.md)
- Structural Commands: [Entity Command Buffers](ecb-structural.md)

[^unity-entities-ijobentity]: Unity Entities 1.4 - IJobEntity
[^unity-collections-allocators]: Unity Collections 2.4 - Allocator Overview
