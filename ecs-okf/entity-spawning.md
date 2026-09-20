---
description: High-performance entity spawning via baked prefabs, batch instantiation with NativeArray, code-defined EntityArchetypes, and query filtering in Unity Entities 1.4+.
generated:
  at: 2026-09-07T15:00:00Z
  by: curator/antigravity
sources:
  - id: unity-entities-prefab-instantiation
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/ecs-workflow-example-prefab-instantiation.html
    title: Unity Entities 1.4 - Prefab Instantiation Workflow
  - id: unity-entities-create
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/entities-create.html
    title: Unity Entities 1.4 - Creating Entities
  - id: unity-entities-baking-prefabs
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/baking-prefabs.html
    title: Unity Entities 1.4 - Baking Prefabs
status: stable
tags:
  - dots
  - ecs
  - spawning
  - prefabs
  - instantiate
  - batching
  - structural-changes
title: Entity Spawning & Prefabs
type: Architecture Guide
---
# Entity Spawning & Prefabs

In Unity Entities, creating entities dynamically at runtime requires careful archetype management. Because an entity's archetype defines the 16KB memory chunk where its data resides, adding components one by one after creation forces repeated archetype migrations and memory copies. High-performance spawning relies on instantiating pre-baked **Entity Prefabs** or pre-defined **EntityArchetypes** in a single allocation.[^unity-entities-prefab-instantiation]

---

## 1. The Archetype Allocation Principle

| Approach | Chunk Migrations | Sync / Realloc Cost | Best For |
| :--- | :--- | :--- | :--- |
| **Prefab Instantiation** | **1 Allocation** (Direct to final chunk) | Zero mid-frame sync (via ECB) | Visual entities, authoring-defined gameplay objects, enemies, projectiles. |
| **EntityArchetype Creation** | **1 Allocation** (Direct to final chunk) | Zero mid-frame sync (via ECB) | Pure data entities, event signals, procedural grid cells with no GameObject source. |
| **Iterative AddComponent** | **N Allocations** (Hops chunks for every component) | Severe fragmentation & memory churn | Anti-pattern; avoid in all runtime systems. |

---

## 2. Canonical Prefab Spawner Workflow

To spawn authoring-defined entities at runtime:
1. Author the target entity as a standard Unity GameObject Prefab with all necessary Baker components.
2. Author a Spawner GameObject that holds a serialized `GameObject` reference to that prefab.
3. In the Spawner's Baker, convert the GameObject reference to an `Entity` using `GetEntity(authoring.Prefab, TransformUsageFlags)`.
4. In an unmanaged `ISystem`, instantiate the baked prefab through an `EntityCommandBuffer`.[^unity-entities-baking-prefabs]

### Step 1: Spawner Authoring & Baker
```csharp
using UnityEngine;
using Unity.Entities;

public class AsteroidSpawnerAuthoring : MonoBehaviour
{
    public GameObject AsteroidPrefab;
    public float SpawnInterval = 1.5f;

    class Baker : Baker<AsteroidSpawnerAuthoring>
    {
        public override void Bake(AsteroidSpawnerAuthoring authoring)
        {
            // TransformUsageFlags.None if the spawner entity does not need spatial transforms
            var entity = GetEntity(TransformUsageFlags.None);

            AddComponent(entity, new AsteroidSpawnerConfig
            {
                // Dynamic flag allows the spawned instances to translate/rotate
                Prefab = GetEntity(authoring.AsteroidPrefab, TransformUsageFlags.Dynamic),
                SpawnInterval = authoring.SpawnInterval,
                Cooldown = 0f
            });
        }
    }
}

public struct AsteroidSpawnerConfig : IComponentData
{
    public Entity Prefab;
    public float SpawnInterval;
    public float Cooldown;
}
```

### Step 2: System Instantiation via ECB
```csharp
using Unity.Entities;
using Unity.Transforms;
using Unity.Mathematics;
using Unity.Burst;

[BurstCompile]
[UpdateInGroup(typeof(SimulationSystemGroup))]
public partial struct AsteroidSpawnerSystem : ISystem
{
    [BurstCompile]
    public void OnCreate(ref SystemState state)
    {
        state.RequireForUpdate<AsteroidSpawnerConfig>();
    }

    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        var ecbSingleton = SystemAPI.GetSingleton<BeginSimulationEntityCommandBufferSystem.Singleton>();
        var ecb = ecbSingleton.CreateCommandBuffer(state.WorldUnmanaged);
        float dt = SystemAPI.Time.DeltaTime;

        foreach (var spawner in SystemAPI.Query<RefRW<AsteroidSpawnerConfig>>())
        {
            spawner.ValueRW.Cooldown -= dt;
            if (spawner.ValueRO.Cooldown <= 0f)
            {
                spawner.ValueRW.Cooldown = spawner.ValueRO.SpawnInterval;

                // 1. Instant allocation into the exact prefab chunk archetype
                Entity spawned = ecb.Instantiate(spawner.ValueRO.Prefab);

                // 2. Configure per-instance state
                ecb.SetComponent(spawned, LocalTransform.FromPosition(new float3(0f, 5f, 0f)));
            }
        }
    }
}
```

---

## 3. High-Density Batch Spawning (`NativeArray<Entity>`)

When instantiating large volumes of entities simultaneously (e.g., bullet swarms, particle emitters, procedural swarms), instantiating entity-by-entity introduces loop call overhead. Use the batch instantiation overload of `EntityManager` or `EntityCommandBuffer`:[^unity-entities-create]

```csharp
[BurstCompile]
public void SpawnWave(ref SystemState state, Entity prefab, int spawnCount)
{
    var ecbSingleton = SystemAPI.GetSingleton<BeginSimulationEntityCommandBufferSystem.Singleton>();
    var ecb = ecbSingleton.CreateCommandBuffer(state.WorldUnmanaged);

    // Allocate temporary container for deferred placeholders
    var spawnedEntities = new NativeArray<Entity>(spawnCount, Allocator.Temp);

    // Batch instantiate all entities in one call
    ecb.Instantiate(prefab, spawnedEntities);

    // Initialize individual transforms
    for (int i = 0; i < spawnCount; i++)
    {
        float3 position = new float3(i * 2f, 0f, 0f);
        ecb.SetComponent(spawnedEntities[i], LocalTransform.FromPosition(position));
    }

    spawnedEntities.Dispose();
}
```

---

## 4. Code-Defined Spawning with `EntityArchetype`

For runtime entities that do not require visual GameObject authoring (e.g., event records, audio request tokens, pure math particles), define an `EntityArchetype` in `OnCreate`:

```csharp
[BurstCompile]
public partial struct SignalEmitterSystem : ISystem
{
    private EntityArchetype _signalArchetype;

    [BurstCompile]
    public void OnCreate(ref SystemState state)
    {
        // Cache the archetype once during system initialization
        _signalArchetype = state.EntityManager.CreateArchetype(
            ComponentType.ReadOnly<SignalTag>(),
            ComponentType.ReadWrite<SignalData>()
        );
    }

    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        var ecbSingleton = SystemAPI.GetSingleton<EndSimulationEntityCommandBufferSystem.Singleton>();
        var ecb = ecbSingleton.CreateCommandBuffer(state.WorldUnmanaged);

        // Creates an entity pre-configured with SignalTag and SignalData in one step
        Entity signal = ecb.CreateEntity(_signalArchetype);
        ecb.SetComponent(signal, new SignalData { EventId = 42 });
    }
}
```

---

## 5. The `Prefab` Tag & Query Filtering

During the baking process, any GameObject converted as an entity prefab automatically receives an unmanaged `Prefab` tag component:

* **Implicit Exclusion**: All standard queries (`SystemAPI.Query`, `SystemAPI.QueryBuilder()`, and `IJobEntity`) automatically exclude entities possessing the `Prefab` component. Simulation and movement systems will never inadvertently update or move prefab source definitions.
* **Explicit Querying**: To deliberately query prefab definitions (such as an inventory catalog system discovering available baked templates), pass `EntityQueryOptions.IncludePrefab`:

```csharp
EntityQuery prefabQuery = SystemAPI.QueryBuilder()
    .WithAll<WeaponConfig>()
    .WithOptions(EntityQueryOptions.IncludePrefab)
    .Build();
```

---

## 6. Best Practices & Guidelines

* **Instantiation Source**:
  * *Prefer*: Pre-baked entity prefabs for any entity with authoring components or visual representations.
  * *Prefer*: `EntityArchetype` created once during `OnCreate` for procedural or data-only entities.
* **Batch Operations**:
  * *Prefer*: `ecb.Instantiate(prefab, nativeArray)` when spawning multiple entities at once.
* **Transform Usage Flags**:
  * *Prefer*: `TransformUsageFlags.Dynamic` for prefabs that translate, rotate, or scale at runtime.
  * *Prefer*: `TransformUsageFlags.Renderable` for static environment prefabs.
  * *Prefer*: `TransformUsageFlags.None` for spawner managers and headless data singletons.
* **Query Safety**:
  * *Prefer*: Relying on default query filtering which automatically ignores `Prefab` entities.
  * *Avoid*: Creating empty entities and adding multiple components sequentially in per-frame loops (causes N chunk migrations per entity).
  * *Avoid*: Manually attaching the `Prefab` tag component unless authoring custom baking systems.

---

## 7. Cross-References

- Memory Architecture: [ECS Fundamentals vs OOP](ecs-fundamentals.md)
- Command Buffers: [Entity Command Buffers & Sync Points](ecb-structural.md)
- Parallel Recording: [EntityCommandBuffer Best Practices](ecb-best-practices.md)
- Authoring & Baking: [Authoring & Baking](baking.md)
- Deterministic Seeding: [Working with Random in ECS](random-in-ecs.md)

[^unity-entities-prefab-instantiation]: Unity Entities 1.4 - Prefab Instantiation Workflow
[^unity-entities-create]: Unity Entities 1.4 - Creating Entities
[^unity-entities-baking-prefabs]: Unity Entities 1.4 - Baking Prefabs
