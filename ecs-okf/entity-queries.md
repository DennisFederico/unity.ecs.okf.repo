---
description: Creating, caching, and filtering entity subsets using SystemAPI.Query and EntityQueryBuilder in Unity Entities 1.4+.
generated:
  at: 2026-09-07T12:15:00Z
  by: curator/antigravity
sources:
  - id: unity-entities-systemapi-query
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/systems-systemapi-query.html
    title: Unity Entities 1.4 - SystemAPI.Query
  - id: unity-entities-query-builder
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/api/Unity.Entities.EntityQueryBuilder.html
    title: Unity Entities 1.4 - EntityQueryBuilder
status: stable
tags:
  - dots
  - ecs
  - queries
  - entityquery
  - systemapi
  - filtering
title: Entity Queries & Filtering
type: Architecture Guide
---
# Entity Queries & Filtering

Entity queries select and filter chunks in the ECS World based on required, optional, or excluded components. Unity Entities 1.4+ provides two primary querying mechanisms:[^unity-entities-systemapi-query]
1. **`SystemAPI.Query`**: An inline, source-generated loop construct for per-entity processing.
2. **`EntityQuery`**: A cached query object built in `OnCreate` for batch array extraction, entity counting, and system update preconditions.

---

## 1. Inline Queries (`SystemAPI.Query`)

Use `SystemAPI.Query` directly inside `ISystem.OnUpdate` for clean, Burst-vectorized iteration:

```csharp
using Unity.Entities;
using Unity.Transforms;
using Unity.Burst;

[BurstCompile]
public partial struct EnemyDamageSystem : ISystem
{
    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        // 1. RefRW for write access, RefRO for read access
        // 2. WithEntityAccess() appends the Entity handle to the end of the tuple
        // 3. Filter tags without reading data payload
        foreach (var (health, transform, entity) in 
            SystemAPI.Query<RefRW<Health>, RefRO<LocalTransform>>()
                     .WithAll<EnemyTag>()
                     .WithNone<DeadTag>()
                     .WithEntityAccess())
        {
            health.ValueRW.Current -= 10f * SystemAPI.Time.DeltaTime;
        }
    }
}
```

### Filtering Options:
* `.WithAll<T1, T2>()`: Matches entities that possess components not included in the main tuple (ideal for zero-size tags).
* `.WithNone<T1, T2>()`: Excludes entities possessing any of the specified component types.
* `.WithAny<T1, T2>()`: Matches entities possessing at least one of the specified types.
* `.WithEntityAccess()`: Appends the `Entity` ID as the final parameter of the loop tuple.

---

## 2. Explicit Cached Queries (`EntityQueryBuilder`)

When a system needs to compute entity counts, extract data into native arrays, or configure `state.RequireForUpdate(query)`, construct and cache an `EntityQuery` in `OnCreate`:[^unity-entities-query-builder]

```csharp
using Unity.Entities;
using Unity.Collections;
using Unity.Burst;

[BurstCompile]
public partial struct RadarSystem : ISystem
{
    private EntityQuery _targetQuery;

    [BurstCompile]
    public void OnCreate(ref SystemState state)
    {
        // Construct and cache query once during initialization
        _targetQuery = SystemAPI.QueryBuilder()
                                .WithAll<EnemyTag, LocalTransform>()
                                .WithNone<StealthedTag>()
                                .Build();

        // Ensure system only updates if at least one target matches
        state.RequireForUpdate(_targetQuery);
    }

    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        // 1. Efficient entity count calculation
        int targetCount = _targetQuery.CalculateEntityCount();

        // 2. Extract matching entities into a temporary native array
        NativeArray<Entity> targets = _targetQuery.ToEntityArray(Allocator.Temp);

        // 3. Extract component data arrays directly
        NativeArray<LocalTransform> transforms = _targetQuery.ToComponentDataArray<LocalTransform>(Allocator.Temp);
    }
}
```

---

## 3. Best Practices & Guidelines

* **Inline Query Placement**:
  * *Prefer*: Writing `SystemAPI.Query<...>()` directly inside the `foreach` statement.
  * *Avoid*: Assigning `SystemAPI.Query` to an intermediate local variable before the loop (Roslyn source generators require direct inline placement and will throw compilation errors).
* **Filter Redundancy**:
  * *Prefer*: Using `.WithAll<T>()` exclusively for filtering tags or components that do **not** appear in the `Query<...>` tuple.
  * *Avoid*: Adding `.WithAll<T>()` for components already declared in `Query<RefRO<T>, ...>` (types in the query tuple are automatically required; redundant calls consume parameter slots).
* **Caching EntityQuery**:
  * *Prefer*: Caching `EntityQuery` instances in `OnCreate` via `SystemAPI.QueryBuilder()`.
  * *Avoid*: Rebuilding an `EntityQuery` every frame inside `OnUpdate` (creates unnecessary runtime allocation and overhead).
* **Memory Lifecycle for Arrays**:
  * *Prefer*: Using `Allocator.Temp` for native arrays extracted via `_query.ToEntityArray()` that are used and discarded within the same frame.

---

## 4. Cross-References

- System Lifecycle: [High-Performance Systems with ISystem](ecs-systems.md)
- Component Taxonomy: [DOTS Component Declarations](ecs-components.md)
- Multithreaded Jobs: [Jobs & Native Collections](jobs-native-collections.md)

[^unity-entities-systemapi-query]: Unity Entities 1.4 - SystemAPI.Query
[^unity-entities-query-builder]: Unity Entities 1.4 - EntityQueryBuilder
