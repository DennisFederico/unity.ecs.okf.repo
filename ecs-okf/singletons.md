---
description: Defining, initializing, baking, and querying single-instance ECS components and buffers using SystemAPI in Unity Entities 1.4+.
generated:
  at: 2026-09-07T07:30:00Z
  by: curator/antigravity
sources:
  - id: unity-entities-systemapi
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/systems-systemapi.html
    title: Unity Entities 1.4 - SystemAPI
  - id: unity-entities-concepts-components
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/concepts-components.html
    title: Unity Entities 1.4 - Components Concept
status: stable
tags:
  - dots
  - ecs
  - singletons
  - systemapi
  - csharp
title: Singleton Components
type: Architecture Guide
---
# Singleton Components

A singleton is a standard component type that has exactly one instance in the ECS World. Singletons are idiomatic for global gameplay state, configuration parameters, timing data, and global event buffers.[^unity-entities-concepts-components]

---

## 1. Defining Singleton Data

Singletons are defined as standard unmanaged `IComponentData` structs. Follow memory alignment best practices (sort fields ascending by type size):

```csharp
using Unity.Entities;

public struct GameConfig : IComponentData
{
    public bool EnableHardcoreMode;  // 1 byte  (Offset 0)
    public int MaxEnemyCount;        // 4 bytes (Offset 4)
    public float SpawnInterval;      // 4 bytes (Offset 8)
    public double MatchStartTime;    // 8 bytes (Offset 16)
}

public struct MatchState : IComponentData
{
    public int CurrentWave;
    public float WaveTimeRemaining;
}
```

---

## 2. Initializing Singletons

### Approach A: Authoring & Baking (Recommended for Config)
Attach an authoring MonoBehaviour to a GameObject in a SubScene. Use `TransformUsageFlags.None` so that no transform components (`LocalTransform`) are generated for purely non-spatial data:

```csharp
using Unity.Entities;
using UnityEngine;

public class GameConfigAuthoring : MonoBehaviour
{
    public bool EnableHardcoreMode;
    public int MaxEnemyCount = 100;
    public float SpawnInterval = 2.5f;

    class Baker : Baker<GameConfigAuthoring>
    {
        public override void Bake(GameConfigAuthoring authoring)
        {
            // TransformUsageFlags.None avoids allocating unused spatial transforms
            var entity = GetEntity(TransformUsageFlags.None);
            AddComponent(entity, new GameConfig
            {
                EnableHardcoreMode = authoring.EnableHardcoreMode,
                MaxEnemyCount = authoring.MaxEnemyCount,
                SpawnInterval = authoring.SpawnInterval,
                MatchStartTime = 0.0
            });
        }
    }
}
```

### Approach B: Runtime Initialization (`OnCreate`)
For one-time runtime bootstrap systems, create the singleton entity during initialization, then disable the system to prevent unnecessary `OnUpdate` execution:

```csharp
using Unity.Entities;

public partial struct MatchBootstrapSystem : ISystem
{
    public void OnCreate(ref SystemState state)
    {
        var entity = state.EntityManager.CreateEntity();
        state.EntityManager.AddComponentData(entity, new MatchState
        {
            CurrentWave = 1,
            WaveTimeRemaining = 60.0f
        });

        // Disable system after initialization to avoid running OnUpdate every frame
        state.Enabled = false;
    }
}
```

---

## 3. Querying & Modifying Singletons (`SystemAPI`)

Access singletons directly in systems using source-generated `SystemAPI` methods:[^unity-entities-systemapi]

```csharp
using Unity.Entities;
using Unity.Burst;

[BurstCompile]
public partial struct MatchDirectorSystem : ISystem
{
    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        // 1. Safe existence check (essential when singletons stream in via SubScenes)
        if (!SystemAPI.TryGetSingleton<GameConfig>(out var config))
        {
            return;
        }

        // 2. Read-Only access (direct struct copy)
        int maxEnemies = config.MaxEnemyCount;

        // 3. Read-Write access (via RefRW)
        if (SystemAPI.TryGetSingletonRW<MatchState>(out var matchState))
        {
            matchState.ValueRW.WaveTimeRemaining -= SystemAPI.Time.DeltaTime;
        }

        // 4. Retrieve the Entity ID of a singleton
        Entity configEntity = SystemAPI.GetSingletonEntity<GameConfig>();
    }
}
```

---

## 4. Dynamic Buffer Singletons

To maintain global dynamic arrays (such as global event queues or damage events), use singleton dynamic buffers:

```csharp
using Unity.Entities;

[InternalBufferCapacity(16)]
public struct GlobalEventMessage : IBufferElementData
{
    public int EventType;
    public float Timestamp;
}
```

Accessing in systems:
```csharp
// Read/Write access to the global buffer
DynamicBuffer<GlobalEventMessage> events = SystemAPI.GetSingletonBuffer<GlobalEventMessage>();
events.Add(new GlobalEventMessage { EventType = 1, Timestamp = (float)SystemAPI.Time.ElapsedTime });
```

---

## 5. Best Practices & Guidelines

* **Authoring Spatial Cost**:
  * *Prefer*: `GetEntity(TransformUsageFlags.None)` in Bakers for configuration singletons.
  * *Avoid*: `TransformUsageFlags.Dynamic` or `Renderable` on singleton config entities (wastes 16KB chunk capacity on unnecessary `LocalTransform` / `LocalToWorld` data).
* **Asynchronous SubScene Safety**:
  * *Prefer*: `SystemAPI.TryGetSingleton<T>(out var value)` or `SystemAPI.HasSingleton<T>()` in systems that run while SubScenes may still be loading.
  * *Avoid*: Unconditional `SystemAPI.GetSingleton<T>()` during loading phases (throws an `InvalidOperationException` if 0 entities match).
* **Cardinality Guarantee**:
  * Ensure exactly **one** entity possesses the singleton component type in the active World. If multiple entities have `T`, `SystemAPI.GetSingleton<T>()` throws an exception.
* **Bootstrap System Lifecycle**:
  * *Prefer*: Setting `state.Enabled = false;` in `OnCreate` for bootstrap systems that exist only to populate initial singletons.

---

## 6. Cross-References

- Component Declarations & Packing: [DOTS Component Declarations](ecs-components.md)
- Systems Lifecycle: [High-Performance Systems with ISystem](ecs-systems.md)
- Subscene Baking: [Baking & Authoring](baking.md)

[^unity-entities-concepts-components]: Unity Entities 1.4 - Components Concept
[^unity-entities-systemapi]: Unity Entities 1.4 - SystemAPI
