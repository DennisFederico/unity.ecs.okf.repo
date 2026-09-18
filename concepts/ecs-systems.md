---
description: Architectural rules, lifecycle callbacks (OnCreate, OnUpdate, OnDestroy), scheduling, update ordering, and Burst compilation for unmanaged ISystem structs in Unity Entities 1.4+.
generated:
  at: 2026-09-07T10:45:00Z
  by: curator/antigravity
sources:
  - id: unity-entities-isystem
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/systems-isystem.html
    title: Unity Entities 1.4 - ISystem Overview
  - id: unity-entities-system-update-order
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/systems-update-order.html
    title: Unity Entities 1.4 - System Update Order
status: stable
tags:
  - dots
  - ecs
  - systems
  - isystem
  - burst
  - performance
title: High-Performance Systems with ISystem
type: Architecture Guide
---
# High-Performance Systems with ISystem

In Unity Entities 1.4+, execution logic belongs in unmanaged systems implementing `ISystem`. Because `ISystem` is a `struct`, the entire system lifecycle can be natively compiled by the Burst compiler, eliminating garbage collection and maximizing CPU execution speed.[^unity-entities-isystem]

---

## 1. Canonical Structural Template

Systems must be declared as `public partial struct` so that Roslyn source generators can generate `SystemAPI` backing lookups:

```csharp
using Unity.Entities;
using Unity.Transforms;
using Unity.Mathematics;
using Unity.Burst;

[BurstCompile]
public partial struct MovementSystem : ISystem
{
    [BurstCompile]
    public void OnCreate(ref SystemState state)
    {
        // Guard: only update when at least one entity possesses MovementSpeed
        state.RequireForUpdate<MovementSpeed>();
    }

    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        float dt = SystemAPI.Time.DeltaTime;

        // Linear chunk iteration across matching entities
        foreach (var (transform, speed) in 
            SystemAPI.Query<RefRW<LocalTransform>, RefRO<MovementSpeed>>())
        {
            transform.ValueRW.Position += new float3(0, 0, speed.ValueRO.Value * dt);
        }
    }

    [BurstCompile]
    public void OnDestroy(ref SystemState state)
    {
        // Clean up unmanaged allocations created specifically by this system
    }
}
```

---

## 2. Controlling System Execution (`RequireForUpdate`)

In Entities 1.4+, systems update every frame by default. Use `RequireForUpdate` inside `OnCreate` to prevent empty system updates and eliminate redundant CPU overhead:

```csharp
[BurstCompile]
public void OnCreate(ref SystemState state)
{
    // 1. Require a component to exist in the World before running
    state.RequireForUpdate<GameActiveTag>();

    // 2. Require a configuration singleton before updating
    state.RequireForUpdate<GameConfig>();

    // 3. Require a custom EntityQuery to have matching chunks
    EntityQuery query = SystemAPI.QueryBuilder().WithAll<PlayerTag, Health>().Build();
    state.RequireForUpdate(query);
}
```

> [!TIP]
> Always call `state.RequireForUpdate<T>()` for singletons in systems that run during asynchronous scene loading. This guarantees the system never executes before the singleton entity has been instantiated.

---

## 3. System Groups & Execution Order

Systems execute deterministically within a hierarchical pipeline of **System Groups**.[^unity-entities-system-update-order] Use attributes to specify the parent group and execution order:

```csharp
// Runs during the simulation phase (default if omitted)
[UpdateInGroup(typeof(SimulationSystemGroup))]
// Runs after MovementSystem has completed its update
[UpdateAfter(typeof(MovementSystem))]
// Runs before physics resolution
[UpdateBefore(typeof(DamageSystem))]
[BurstCompile]
public partial struct CombatResolutionSystem : ISystem
{
    [BurstCompile]
    public void OnUpdate(ref SystemState state) { /* ... */ }
}
```

### Standard System Groups:
* `InitializationSystemGroup`: Pre-frame preparation, input gathering, and command buffer playback.
* `SimulationSystemGroup`: Core gameplay logic, physics, and state updates (default).
* `PresentationSystemGroup`: Rendering preparation, animations, and transform-to-graphics synchronization.

---

## 4. Scheduling Parallel Worker Threads (`IJobEntity`)

When workload processing benefits from multithreaded worker jobs, schedule an `IJobEntity` and chain the system's `state.Dependency` handle:

```csharp
[BurstCompile]
public partial struct MovementJobSystem : ISystem
{
    [BurstCompile]
    public void OnCreate(ref SystemState state)
    {
        state.RequireForUpdate<MovementSpeed>();
    }

    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        var job = new MoveParallelJob
        {
            DeltaTime = SystemAPI.Time.DeltaTime
        };

        // Chain dependencies to prevent race conditions across parallel systems
        state.Dependency = job.ScheduleParallel(state.Dependency);
    }
}

[BurstCompile]
public partial struct MoveParallelJob : IJobEntity
{
    public float DeltaTime;

    void Execute(ref LocalTransform transform, in MovementSpeed speed)
    {
        transform.Position += new float3(0, 0, speed.Value * DeltaTime);
    }
}
```

---

## 5. Architectural Rule: `ISystem` vs `SystemBase`

| Architecture | Paradigm | Best Suited For | Burst Compilation |
| :--- | :--- | :--- | :--- |
| **`ISystem`** | Unmanaged `struct` | Gameplay logic, math, physics, combat, queries, jobs. | ✅ Fully Supported |
| **`SystemBase`** | Managed `class` | Interfacing with Unity GameObjects, UI Toolkit, Audio sources, external C# events. | ❌ No (Runs on Mono/.NET heap) |

* **Best Practice Guideline**:
  * *Prefer*: `ISystem` as the default for all gameplay systems.
  * *Avoid*: Using `SystemBase` for simulation loops. Isolate `SystemBase` exclusively to boundary systems that bridge Entities with managed GameObjects.

---

## 6. Cross-References

- Foundational Architecture: [ECS Fundamentals vs OOP](ecs-fundamentals.md)
- Query Building: [Entity Queries & Filtering](entity-queries.md)
- Parallel Jobs: [Jobs & Native Collections](jobs-native-collections.md)
- Structural Commands: [Entity Command Buffers](ecb-structural.md)
- Managed Bridging: [Hybrid ECS & Managed Bridges](hybrid-ecs.md)

[^unity-entities-isystem]: Unity Entities 1.4 - ISystem Overview
[^unity-entities-system-update-order]: Unity Entities 1.4 - System Update Order
