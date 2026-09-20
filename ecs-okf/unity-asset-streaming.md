---
description: Native ECS Content Archive streaming via EntitySceneReference, hybrid Addressables integration, asynchronous asset lifecycles, and memory release patterns in Unity Entities 1.4+.
generated:
  at: 2026-09-07T23:45:00Z
  by: curator/antigravity
sources:
  - id: unity-entities-content-management
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/scenes-loading.html
    title: Unity Entities 1.4 - Loading Scenes & Content Management
  - id: unity-entities-scenes-reference
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/scenes-subscenes.html
    title: Unity Entities 1.4 - Subscenes & Scene References
  - id: unity-addressables-manual
    resource: https://docs.unity3d.com/Packages/com.unity.addressables@1.21/manual/index.html
    title: Unity Addressables Manual
status: stable
tags:
  - dots
  - ecs
  - addressables
  - streaming
  - entity-scene-reference
  - scene-system
  - memory
title: Asset References & Streaming
type: Architecture Guide
---
# Asset References & Streaming

In Unity Entities, handling external assets requires distinguishing between **pure unmanaged ECS content** (Subscenes, Entities Graphics meshes, baked entity prefabs) and **managed engine assets** (AudioClips, Addressable companion prefabs, dynamic DLC textures). Using the correct content management strategy ensures zero-stall loading and prevents unmanaged memory leaks.[^unity-entities-content-management]

---

## 1. Native ECS Content Archives vs. Addressables

| Content Management Pipeline | Target Assets | Runtime Mechanism | Best Suited For |
| :--- | :--- | :--- | :--- |
| **ECS Content Archives** (Built-in) | Subscenes, Baked Prefabs, Entities Graphics meshes | Serialized raw entity binary chunks streamed via `SceneSystem` | Entire levels, static environments, baked entity swarms, simulation prefabs. |
| **Unity Addressables** (`com.unity.addressables`) | Managed GameObjects, AudioClips, UI sprites, dynamic DLC skins | Asynchronous bundle loading on the managed main thread | On-demand character skins, voiceover audio, downloadable episodic content. |

> [!IMPORTANT]
> **Entities Native Asset Rule**: Unity Entities 1.4+ intentionally decouples from runtime `Resources` and standalone `AssetBundles`. For DOTS worlds, use Unity's native **Content Archive** format managed through Subscenes and `EntitySceneReference`.[^unity-entities-content-management]

---

## 2. Native Subscene Streaming (`EntitySceneReference`)

For world chunks, levels, and large prefab catalogs, use `EntitySceneReference`. This struct serializes as an unmanaged weak reference during baking and resolves into content archives at runtime without keeping heavy managed asset handles in memory.[^unity-entities-scenes-reference]

### Step 1: Authoring Scene Reference
```csharp
using UnityEngine;
using Unity.Entities;
using Unity.Entities.Serialization;

public class WorldChunkAuthoring : MonoBehaviour
{
    // Serialized reference to a Subscene asset in the project
    public UnityEditor.SceneAsset ChunkSubscene;

    class Baker : Baker<WorldChunkAuthoring>
    {
        public override void Bake(WorldChunkAuthoring authoring)
        {
            var entity = GetEntity(TransformUsageFlags.None);
            AddComponent(entity, new WorldChunkConfig
            {
                SceneReference = new EntitySceneReference(authoring.ChunkSubscene)
            });
        }
    }
}

public struct WorldChunkConfig : IComponentData
{
    public EntitySceneReference SceneReference;
}
```

### Step 2: Streaming in an Unmanaged `ISystem`
```csharp
using Unity.Entities;
using Unity.Scenes;
using Unity.Burst;

[BurstCompile]
public partial struct WorldChunkLoaderSystem : ISystem
{
    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        // Iterate chunks requesting to be loaded
        foreach (var (chunk, entity) in 
            SystemAPI.Query<RefRO<WorldChunkConfig>>()
                     .WithNone<LoadedSceneTag>()
                     .WithEntityAccess())
        {
            // Asynchronously load the ECS content archive
            Entity sceneEntity = SceneSystem.LoadSceneAsync(
                state.WorldUnmanaged, 
                chunk.ValueRO.SceneReference
            );

            // Tag entity to track load state
            SystemAPI.SetComponent(entity, new LoadedSceneTag { SceneEntity = sceneEntity });
        }
    }
}

public struct LoadedSceneTag : IComponentData
{
    public Entity SceneEntity;
}
```

---

## 3. Hybrid Asset Streaming via Addressables

When an entity requires dynamic managed assets (such as an audio track or companion particle prefab from an Addressable catalog), bridge the load asynchronously through a managed `SystemBase`:[^unity-addressables-manual]

### 1. Request Component & Managed Bridge
```csharp
using Unity.Entities;
using UnityEngine;
using UnityEngine.AddressableAssets;
using UnityEngine.ResourceManagement.AsyncOperations;

public struct AssetLoadRequest : IComponentData
{
    public FixedString64Bytes AddressableKey;
}

public struct AssetHandleCleanup : ICleanupComponentData
{
    public AsyncOperationHandle<GameObject> Handle;
}
```

### 2. Async Loading in `SystemBase`
```csharp
using Unity.Entities;
using UnityEngine;
using UnityEngine.AddressableAssets;
using UnityEngine.ResourceManagement.AsyncOperations;

[UpdateInGroup(typeof(PresentationSystemGroup))]
public partial class AddressableLoadBridgeSystem : SystemBase
{
    protected override void OnUpdate()
    {
        var ecbSingleton = SystemAPI.GetSingleton<BeginPresentationEntityCommandBufferSystem.Singleton>();
        var ecb = ecbSingleton.CreateCommandBuffer(World.Unmanaged);

        // 1. Process pending load requests
        foreach (var (request, entity) in 
            SystemAPI.Query<RefRO<AssetLoadRequest>>()
                     .WithNone<AssetHandleCleanup>()
                     .WithEntityAccess())
        {
            string key = request.ValueRO.AddressableKey.ToString();
            AsyncOperationHandle<GameObject> handle = Addressables.LoadAssetAsync<GameObject>(key);

            // Attach cleanup component with the active handle
            ecb.AddComponent(entity, new AssetHandleCleanup { Handle = handle });
            ecb.RemoveComponent<AssetLoadRequest>(entity);

            // Handle asynchronous completion callback
            handle.Completed += op =>
            {
                if (op.Status == AsyncOperationStatus.Succeeded)
                {
                    // Instantiate companion GameObject on main thread
                    GameObject instance = Object.Instantiate(op.Result);
                    // Attach companion reference or initialize transform
                }
            };
        }
    }
}
```

---

## 4. Deterministic Memory Release via `ICleanupComponentData`

Every loaded Addressable handle **must** be explicitly released to prevent native memory leaks.[^unity-addressables-manual] Use a cleanup system in `PresentationSystemGroup` to release the asset when the entity is destroyed:

```csharp
[UpdateInGroup(typeof(PresentationSystemGroup))]
[UpdateAfter(typeof(AddressableLoadBridgeSystem))]
public partial class AddressableCleanupSystem : SystemBase
{
    protected override void OnUpdate()
    {
        var ecbSingleton = SystemAPI.GetSingleton<BeginPresentationEntityCommandBufferSystem.Singleton>();
        var ecb = ecbSingleton.CreateCommandBuffer(World.Unmanaged);

        // When the parent entity is destroyed, AssetHandleCleanup remains
        foreach (var (cleanup, entity) in 
            SystemAPI.Query<RefRO<AssetHandleCleanup>>()
                     .WithNone<LoadedAssetTag>()
                     .WithEntityAccess())
        {
            // Release the Addressable handle
            if (cleanup.ValueRO.Handle.IsValid())
            {
                Addressables.Release(cleanup.ValueRO.Handle);
            }

            // Remove cleanup component to finalize entity destruction
            ecb.RemoveComponent<AssetHandleCleanup>(entity);
        }
    }
}
```

---

## 5. The Zero-Stall Async Rule

Never invoke synchronous completion methods in performance-critical paths:

* **Stall Risk**: Calling `.WaitForCompletion()` on an `AsyncOperationHandle` halts the main thread until disk or network streaming finishes, inducing noticeable frame rate hitches.
* **Asynchronous Discipline**: Always await completion via `.Completed` delegates, coroutines, or non-blocking polling (`handle.IsDone`).

---

## 6. Best Practices & Guidelines

* **Native Streaming**:
  * *Prefer*: `EntitySceneReference` and `SceneSystem.LoadSceneAsync()` for Subscenes, world chunks, and entity prefabs.
  * *Avoid*: Using legacy `Resources.Load()` or standalone `AssetBundles` inside DOTS workflows.
* **Managed Companions**:
  * *Prefer*: Addressables for external dynamic assets (audio, skins, UI packs) bridged via `SystemBase`.
  * *Prefer*: Storing `AsyncOperationHandle` in an `ICleanupComponentData` to ensure deterministic memory release when entities are destroyed.
* **Frame Rate Integrity**:
  * *Prefer*: Non-blocking asynchronous loading patterns.
  * *Avoid*: Calling `.WaitForCompletion()` on Addressables in gameplay or presentation systems.

---

## 7. Cross-References

- Subscenes & Scene System: [DOTS/ECS Scene Architecture & Subscenes](ecs-scene-architecture.md)
- Companion Entities: [Hybrid ECS & Companion GameObjects](hybrid-ecs.md)
- Cleanup Lifecycle: [Cleanup Components](cleanup-components.md)
- Systems Architecture: [High-Performance Systems with ISystem](ecs-systems.md)
- Compilation Diagnostics: [Common Compilation & Burst Errors](common-compilation-errors.md)

[^unity-entities-content-management]: Unity Entities 1.4 - Loading Scenes & Content Management
[^unity-entities-scenes-reference]: Unity Entities 1.4 - Subscenes & Scene References
[^unity-addressables-manual]: Unity Addressables Manual
