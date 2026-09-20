---
description: Deterministic, Burst-compatible pseudo-random number generation using Unity.Mathematics.Random across singletons, per-entity components, and multithreaded jobs in Unity Entities 1.4+ and Unity 6.5+.
generated:
  at: 2026-09-07T12:35:00Z
  by: curator/antigravity
sources:
  - id: unity-mathematics-random
    resource: https://docs.unity3d.com/Packages/com.unity.mathematics@1.3/api/Unity.Mathematics.Random.html
    title: Unity Mathematics - Random Struct API
  - id: unity-entities-prefab-instantiation
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/ecs-workflow-example-prefab-instantiation.html
    title: Unity Entities 1.4 - Prefab Instantiation & Random Spawner Example
status: stable
tags:
  - dots
  - ecs
  - mathematics
  - random
  - burst
  - performance
title: Working with Random in ECS
type: Architecture Guide
---
# Working with Random in ECS

In DOTS, random number generation differs fundamentally from classic GameObjects. Traditional `UnityEngine.Random` is a managed static class that cannot be called from Burst-compiled code or worker threads. Instead, ECS relies on `Unity.Mathematics.Random`, an unmanaged value-type `struct` designed for high-performance, deterministic execution.[^unity-mathematics-random]

> [!NOTE]
> **Unity 6.5+ Native Availability**: In Unity Editor 6.5 and later, `Unity.Mathematics` is integrated natively into the core engine and is immediately available via `using Unity.Mathematics;` without requiring a separate package entry in `manifest.json`.

---

## 1. Core Differences: `UnityEngine.Random` vs `Unity.Mathematics.Random`

| Feature | `UnityEngine.Random` (OOP) | `Unity.Mathematics.Random` (DOTS) |
| :--- | :--- | :--- |
| **Type Kind** | Static class | Unmanaged value-type `struct` |
| **Burst Compatibility** | ❌ No (managed runtime) | ✅ Full Burst compilation |
| **Thread Safety** | ❌ Main thread only | ✅ Thread-safe when isolated per entity, job, or worker |
| **Determinism** | Difficult to synchronize | Guaranteed when seeded identically |
| **Initialization** | Implicit global state | Explicit non-zero seed required (`new Random(seed)`) |

---

## 2. Common Random Value Methods

All sampling methods mutate the internal pseudo-random state of the `Random` struct:

```csharp
Unity.Mathematics.Random random = new Unity.Mathematics.Random(1234u);

// Floating point numbers
float f01 = random.NextFloat();                // [0.0f, 1.0f)
float fRange = random.NextFloat(5.0f, 10.0f);  // [min, max)

// Integers
int iRange = random.NextInt(1, 101);           // [min, max)

// Booleans
bool coinFlip = random.NextBool();

// Vectors & Quaternions
float3 pos = random.NextFloat3(-10f, 10f);     // Uniform 3D bounding box
float3 dir = random.NextFloat3Direction();     // Normalized unit direction on sphere
quaternion rot = random.NextQuaternionRotation(); // Random 3D rotation
```

> [!IMPORTANT]
> **Non-Zero Seed Precondition**: The constructor `new Random(uint seed)` requires a non-zero positive integer. Passing `0` results in invalid generator state. Use `math.max(1u, seed)` to protect against zero-seed inputs.

---

## 3. Idiomatic ECS Patterns

### Pattern A: Global Singleton (Centralized Spawners & Configs)
Store a single random generator on a singleton entity for single-threaded systems or serial spawners:[^unity-entities-prefab-instantiation]

```csharp
using Unity.Entities;
using Unity.Mathematics;
using Unity.Burst;

// 1. Component definition
public struct GlobalRandom : IComponentData
{
    public Unity.Mathematics.Random Value;
}

// 2. System access
[BurstCompile]
public partial struct SpawnerSystem : ISystem
{
    [BurstCompile]
    public void OnCreate(ref SystemState state)
    {
        state.RequireForUpdate<GlobalRandom>();
    }

    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        // Mutate singleton random state via RefRW
        ref var random = ref SystemAPI.GetSingletonRW<GlobalRandom>().ValueRW.Value;

        float3 spawnOffset = random.NextFloat3Direction() * random.NextFloat(2f, 5f);
        // Process spawning logic...
    }
}
```

### Pattern B: Per-Entity Random Component (Independent Entity Jitter)
When each entity requires an independent random sequence (e.g., erratic NPC movement, randomized attack cooldowns):

```csharp
using Unity.Entities;
using Unity.Mathematics;

public struct EntityRandom : IComponentData
{
    public Unity.Mathematics.Random Value;
}
```

Baking the entity seed:
```csharp
public class EntityRandomAuthoring : MonoBehaviour
{
    public uint Seed = 1;

    class Baker : Baker<EntityRandomAuthoring>
    {
        public override void Bake(EntityRandomAuthoring authoring)
        {
            var entity = GetEntity(TransformUsageFlags.Dynamic);
            AddComponent(entity, new EntityRandom
            {
                Value = new Unity.Mathematics.Random(math.max(1u, authoring.Seed))
            });
        }
    }
}
```

### Pattern C: Stateless Stack-Local Derivation in Parallel Jobs
In multithreaded jobs (`IJobEntity` or `IJobParallelFor`), worker threads cannot share a single `Random` instance. If entities do not have an `EntityRandom` component, derive a deterministic seed on the stack inside `Execute`:

```csharp
using Unity.Entities;
using Unity.Transforms;
using Unity.Mathematics;
using Unity.Burst;

[BurstCompile]
public partial struct JitterParallelJob : IJobEntity
{
    public uint GlobalSeed;
    public float DeltaTime;

    // Derive a unique seed per entity index and tick
    public void Execute(Entity entity, ref LocalTransform transform)
    {
        // Distinct non-zero seed per entity using hash multiplier
        uint uniqueSeed = (uint)(entity.Index + 1) * 0x9E3779B9u + GlobalSeed;
        var localRandom = new Unity.Mathematics.Random(math.max(1u, uniqueSeed));

        // Apply jitter
        transform.Position += localRandom.NextFloat3Direction() * (localRandom.NextFloat(0.5f, 1.5f) * DeltaTime);
    }
}
```

---

## 4. Best Practices & Guidelines

* **Burst-First Math**:
  * *Prefer*: `Unity.Mathematics.Random` in all systems and jobs.
  * *Avoid*: `UnityEngine.Random` inside ECS code (triggers Burst compilation failures).
* **Seeding Safety**:
  * *Prefer*: Seeding with non-zero values (`math.max(1u, seed)`).
  * *Prefer*: Using `(uint)System.DateTime.Now.Ticks` or a hardware seed at startup if non-deterministic behavior is desired.
* **Parallel Concurrency**:
  * *Prefer*: Giving each entity an `EntityRandom` component or constructing a stack-local `Random` instance per entity in parallel jobs.
  * *Avoid*: Passing a single `Random` struct by reference across multiple worker threads (causes concurrent race conditions and non-deterministic results).

---

## 5. Cross-References

- Unmanaged Components: [DOTS Component Declarations](ecs-components.md)
- Singletons: [Singleton Components](singletons.md)
- Parallel Jobs: [Jobs & Native Collections](jobs-native-collections.md)
- Entity Spawning: [Entity Spawning & Prefabs](entity-spawning.md)

[^unity-mathematics-random]: Unity Mathematics - Random Struct API
[^unity-entities-prefab-instantiation]: Unity Entities 1.4 - Prefab Instantiation & Random Spawner Example
