---
description: Architectural division between Main Scenes and Subscenes, runtime scene streaming with SceneSystem, hierarchy baking, and scene sections in Unity Entities 1.4+.
generated:
  at: 2026-09-07T19:15:00Z
  by: curator/antigravity
sources:
  - id: unity-entities-subscenes
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/scenes-subscenes.html
    title: Unity Entities 1.4 - Subscenes
  - id: unity-entities-load-scene
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/load-scene.html
    title: Unity Entities 1.4 - Loading Scenes
  - id: unity-entities-workflow-intro
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/ecs-workflow-intro.html
    title: Unity Entities 1.4 - ECS Workflow Introduction
status: stable
tags:
  - dots
  - ecs
  - subscene
  - scene-system
  - streaming
  - baking
  - scene-architecture
title: DOTS/ECS Scene Architecture & Subscenes
type: Architecture Guide
---
# DOTS/ECS Scene Architecture & Subscenes

In Unity Entities, scenes are partitioned into managed root scenes and unmanaged **Subscenes**. Authoring GameObjects and their associated `Baker<T>` classes will **not** be baked into unmanaged entities unless they reside inside a Subscene. Understanding scene boundaries, hierarchy baking, and runtime scene streaming is fundamental to building scalable DOTS worlds.[^unity-entities-subscenes]

---

## 1. The Subscene Requirement

A Subscene is a standard Unity `.unity` scene asset referenced by a `Unity.Scenes.SubScene` component attached to a GameObject in your root scene:

* **In the Unity Editor**:
  * **Open Subscene**: The subscene is in *Authoring Mode*. GameObjects and MonoBehaviours are visible in the Hierarchy and editable in the Inspector.
  * **Closed Subscene**: The subscene is in *Entity Mode*. Authoring GameObjects are converted into live ECS entities and rendered via the DOTS batch renderer.
* **At Runtime / In Player Builds**:
  * Authoring GameObjects do not exist in player builds.
  * Only the serialized entity binary cache is loaded into memory, providing near-instantaneous load times and zero managed garbage collection overhead.

> [!IMPORTANT]
> Any GameObject carrying an Authoring `MonoBehaviour` placed in the root main scene will **not** be baked. It remains a standard managed GameObject at runtime. All entity authoring must be placed inside a Subscene.

---

## 2. Strict Hierarchy Separation

Maintain a clean structural division between managed Unity systems and unmanaged ECS worlds:

```
Root Main Scene (Managed Unity Realm)
├── Main Camera (URP Camera, AudioListener)
├── UI Document / Canvas (UI Toolkit or UGUI)
├── Global Volume (URP Post-Processing & Environment Lighting)
└── Entities_SubScene (GameObject with Unity.Scenes.SubScene component)
    └── [References: Level_Entities.unity]

Level_Entities.unity (Unmanaged DOTS Realm - Inside Subscene)
├── GameConfig (Singleton Authoring: Spawners, Level Boundaries)
├── PlayerSpawnPoint
├── EnvironmentGeometry (Static Renderable Meshes)
└── Lighting & Reflection Probes
```

| Realm | Objects Allowed | Reason |
| :--- | :--- | :--- |
| **Main Scene** | Cameras, UI Canvas, Post-Processing Volumes, AudioListeners, companion GameObjects. | Managed engines and third-party plugins require standard `GameObject` lifecycles. |
| **Subscene** | GameObjects with `Baker<T>` components, spawner configs, environment geometry, colliders. | Strictly converted to unmanaged entities during the baking pipeline. |

---

## 3. Runtime Scene Streaming via `SceneSystem`

Subscenes can be loaded, streamed, and unloaded dynamically at runtime from unmanaged `ISystem` structs using `SceneSystem`:[^unity-entities-load-scene]

### Step 1: Authoring Scene Reference
```csharp
using UnityEngine;
using Unity.Entities;
using Unity.Entities.Serialization;

public class LevelManagerAuthoring : MonoBehaviour
{
    public UnityEditor.SceneAsset NextLevelScene;

    class Baker : Baker<LevelManagerAuthoring>
    {
        public override void Bake(LevelManagerAuthoring authoring)
        {
            var entity = GetEntity(TransformUsageFlags.None);
            AddComponent(entity, new LevelLoaderConfig
            {
                SceneReference = new EntitySceneReference(authoring.NextLevelScene)
            });
        }
    }
}

public struct LevelLoaderConfig : IComponentData
{
    public EntitySceneReference SceneReference;
}
```

### Step 2: Streaming in an `ISystem`
```csharp
using Unity.Entities;
using Unity.Scenes;
using Unity.Burst;

[BurstCompile]
public partial struct LevelStreamSystem : ISystem
{
    private Entity _loadedSceneEntity;

    [BurstCompile]
    public void OnCreate(ref SystemState state)
    {
        state.RequireForUpdate<LevelLoaderConfig>();
    }

    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        var config = SystemAPI.GetSingleton<LevelLoaderConfig>();

        // 1. Asynchronously load the subscene
        if (_loadedSceneEntity == Entity.Null)
        {
            _loadedSceneEntity = SceneSystem.LoadSceneAsync(
                state.WorldUnmanaged, 
                config.SceneReference
            );
        }

        // 2. Poll loading progress
        if (_loadedSceneEntity != Entity.Null && 
            SceneSystem.IsSceneLoaded(state.WorldUnmanaged, _loadedSceneEntity))
        {
            // Scene is fully loaded and entities are active
        }
    }

    [BurstCompile]
    public void OnDestroy(ref SystemState state)
    {
        // 3. Unload when tearing down
        if (_loadedSceneEntity != Entity.Null)
        {
            SceneSystem.UnloadScene(state.WorldUnmanaged, _loadedSceneEntity);
        }
    }
}
```

### Scene Sections
Large subscenes can partition entities into **Scene Sections** during baking:
* **Section 0**: Always loaded first. Contains essential collision geometry, physics bodies, and gameplay spawn points.
* **Section 1+**: High-detail visual meshes, decorations, and props that can stream in asynchronously without stalling gameplay logic.

---

## 4. Transform Hierarchy Baking (Parent & Child)

When authoring parent-child GameObjects inside a Subscene:
* **Dynamic Hierarchies**: If parent and child GameObjects are both baked with `TransformUsageFlags.Dynamic`, the baker automatically attaches a `Parent` component to the child entity and a `Child` dynamic buffer element to the parent entity. Runtime transform systems propagate movements down the tree.
* **Static Flattening**: If children do not move relative to their parent at runtime, bake them with `TransformUsageFlags.Renderable` or `TransformUsageFlags.WorldSpace`. Unity bakes their absolute world position directly, completely omitting `Parent` and `Child` components and eliminating runtime hierarchy update calculations.

---

## 5. Best Practices & Guidelines

* **Subscene Placement**:
  * *Prefer*: Placing all DOTS/ECS authoring GameObjects strictly inside a Subscene.
  * *Avoid*: Placing authoring scripts in the root main scene (they will never be baked into entities).
* **Managed/Unmanaged Separation**:
  * *Prefer*: Keeping Cameras, Canvas UI, and AudioListeners in the root main scene.
  * *Prefer*: Keeping gameplay singletons, spawners, and environment geometry inside the Subscene.
* **Hierarchy Optimization**:
  * *Prefer*: `TransformUsageFlags.Renderable` for static children to flatten hierarchies and avoid runtime `Parent`/`Child` buffer overhead.
  * *Prefer*: `TransformUsageFlags.Dynamic` strictly when child objects must move or rotate relative to their parent at runtime.
* **Streaming Strategy**:
  * *Prefer*: Using `SceneSystem.LoadSceneAsync()` with `EntitySceneReference` for asynchronous runtime streaming.

---

## 6. Cross-References

- ECS Foundations: [ECS Fundamentals vs OOP](ecs-fundamentals.md)
- Authoring & Bakers: [Authoring & Baking](baking.md)
- Runtime Instantiation: [Entity Spawning & Prefabs](entity-spawning.md)
- Agentic Workflows: [Agentic DOTS/ECS Scene Assembly](agentic-scene-assembly.md)
- Managed Bridges: [Hybrid ECS & Managed Bridges](hybrid-ecs.md)

[^unity-entities-subscenes]: Unity Entities 1.4 - Subscenes
[^unity-entities-load-scene]: Unity Entities 1.4 - Loading Scenes
[^unity-entities-workflow-intro]: Unity Entities 1.4 - ECS Workflow Introduction
