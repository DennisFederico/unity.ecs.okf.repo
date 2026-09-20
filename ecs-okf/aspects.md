---
description: Idiomatic patterns for accessing multi-component entities directly via SystemAPI.Query and IJobEntity without obsolete IAspect structs in Unity Entities 1.4+.
generated:
  at: 2026-09-07T10:38:00Z
  by: curator/antigravity
sources:
  - id: unity-entities-aspects-api
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/api/Unity.Entities.IAspect.html
    title: Unity Entities 1.4 - IAspect Interface (Obsolete)
  - id: unity-entities-whats-new-14
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/whats-new.html
    title: Unity Entities 1.4 - What's New & Deprecated APIs
status: stable
tags:
  - dots
  - ecs
  - components
  - queries
  - deprecation
  - migration
title: Querying Component Combinations (Aspects Migration)
type: Architecture Guide
---
# Querying Component Combinations (Aspects Migration)

In Unity Entities 1.4+, the `IAspect` interface is deprecated and obsolete.[^unity-entities-aspects-api] Modern DOTS code accesses component combinations directly through `SystemAPI.Query` tuples and `IJobEntity` parameters.

Direct component queries eliminate wrapper complexity, simplify safety checks, and allow the Burst compiler to vectorize loops without intermediate aspect code.[^unity-entities-whats-new-14]

---

## 1. Modern Idiom: Direct `SystemAPI.Query` Tuples

Instead of defining an aspect struct, decompose component dependencies directly into a `SystemAPI.Query` tuple:

```csharp
using Unity.Entities;
using Unity.Transforms;
using Unity.Mathematics;
using Unity.Burst;

public struct MovementSpeed : IComponentData
{
    public float Value;
}

public struct Health : IComponentData
{
    public float Current;
    public float Max;
}

[BurstCompile]
public partial struct CharacterMovementSystem : ISystem
{
    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        float dt = SystemAPI.Time.DeltaTime;

        // Query components directly using RefRW and RefRO tuples
        foreach (var (transform, speed, health) in 
            SystemAPI.Query<RefRW<LocalTransform>, RefRO<MovementSpeed>, RefRW<Health>>())
        {
            // Update position
            transform.ValueRW.Position += new float3(0, 0, speed.ValueRO.Value * dt);

            // Access companion component state
            if (health.ValueRO.Current < health.ValueRO.Max * 0.5f)
            {
                health.ValueRW.Current += 5.0f * dt;
            }
        }
    }
}
```

---

## 2. Multithreaded Idiom: Direct `IJobEntity` Parameters

For parallel processing, declare each component as an explicit parameter in the job's `Execute` signature:

```csharp
using Unity.Entities;
using Unity.Transforms;
using Unity.Mathematics;
using Unity.Burst;

[BurstCompile]
public partial struct CharacterMoveJob : IJobEntity
{
    public float DeltaTime;

    // Parameters define read/write access:
    // 'ref' = read-write, 'in' = read-only
    public void Execute(ref LocalTransform transform, in MovementSpeed speed, ref Health health)
    {
        transform.Position += new float3(0, 0, speed.Value * DeltaTime);

        if (health.Current < health.Max * 0.5f)
        {
            health.Current += 5.0f * DeltaTime;
        }
    }
}
```

---

## 3. Best Practices & Guidelines

* **Direct Component Queries**:
  * *Prefer*: Direct `SystemAPI.Query<RefRW<T1>, RefRO<T2>>` iteration for main-thread linear execution.
  * *Prefer*: `IJobEntity` with `ref` and `in` parameters for multithreaded scheduling.
  * *Avoid*: Declaring new structs that implement `IAspect` (flagged with compiler obsolescence warnings).
* **Burst Optimization**:
  * Direct component parameters give the Burst compiler direct pointer access to contiguous chunk arrays, maximizing SIMD vectorization.

---

## 4. Cross-References

- Component Taxonomy: [DOTS Component Declarations](ecs-components.md)
- Systems Architecture: [High-Performance Systems with ISystem](ecs-systems.md)
- Query Architecture: [Entity Queries & Filtering](entity-queries.md)
- Multithreaded Scheduling: [Jobs & Native Collections](jobs-native-collections.md)

[^unity-entities-aspects-api]: Unity Entities 1.4 - IAspect Interface (Obsolete)
[^unity-entities-whats-new-14]: Unity Entities 1.4 - What's New & Deprecated APIs
