---
description: Defining, baking, querying, and updating resizable array components (IBufferElementData) and parallel job lookups in Unity Entities 1.4+.
generated:
  at: 2026-09-07T08:55:00Z
  by: curator/antigravity
sources:
  - id: unity-entities-buffer-create
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/components-buffer-create.html
    title: Unity Entities 1.4 - Create a Dynamic Buffer Component
  - id: unity-entities-buffer-jobs
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/components-buffer-jobs.html
    title: Unity Entities 1.4 - Dynamic Buffers in Jobs
  - id: unity-entities-buffer-set-capacity
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/components-buffer-set-capacity.html
    title: Unity Entities 1.4 - Declare InternalBufferCapacity for a DynamicBuffer
status: stable
tags:
  - dots
  - ecs
  - components
  - dynamic-buffer
  - memory
  - performance
title: Dynamic Buffers
type: Architecture Guide
---
# Dynamic Buffers

A dynamic buffer component is an ECS component that acts as a resizable array. It associates an ordered list of unmanaged data elements with a single entity.[^unity-entities-buffer-create]

---

## 1. Defining Buffer Element Types

Implement `IBufferElementData` on an unmanaged struct. Use `[InternalBufferCapacity(N)]` to reserve inline storage for $N$ elements directly inside the 16KB archetype chunk:[^unity-entities-buffer-set-capacity]

```csharp
using Unity.Entities;

// Archetype tag distinguishing player entities
public struct PlayerTag : IComponentData { }

// Stores up to 8 elements inline inside the chunk.
// If count exceeds 8, ECS reallocates the buffer onto an external native heap.
[InternalBufferCapacity(8)]
public struct InventoryItem : IBufferElementData
{
    public int ItemId;
    public int Quantity;

    // Optional convenience conversion for single-field operations
    public static implicit operator InventoryItem(int itemId) => new InventoryItem { ItemId = itemId, Quantity = 1 };
}
```

---

## 2. Baking Dynamic Buffers

Initialize dynamic buffers inside a `Baker<T>` using `AddBuffer<T>(entity)`:

```csharp
using Unity.Entities;
using UnityEngine;

public class PlayerAuthoring : MonoBehaviour
{
    public int StartingPotions = 3;

    class Baker : Baker<PlayerAuthoring>
    {
        public override void Bake(PlayerAuthoring authoring)
        {
            var entity = GetEntity(TransformUsageFlags.Dynamic);

            // 1. Add identifying tag
            AddComponent<PlayerTag>(entity);

            // 2. Add dynamic buffer component to the player entity
            DynamicBuffer<InventoryItem> inventory = AddBuffer<InventoryItem>(entity);

            // 3. Populate initial elements
            inventory.Add(new InventoryItem 
            { 
                ItemId = 101, 
                Quantity = authoring.StartingPotions 
            });
        }
    }
}
```

---

## 3. Querying & Modifying Buffers (`SystemAPI.Query`)

In `ISystem` updates, query the entity's `DynamicBuffer<T>` alongside other components and tag filters:

```csharp
using Unity.Entities;
using Unity.Transforms;
using Unity.Burst;

[BurstCompile]
public partial struct PlayerInventorySystem : ISystem
{
    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        // Query player entities with their transform and inventory buffer
        foreach (var (transform, inventory) in 
            SystemAPI.Query<RefRO<LocalTransform>, DynamicBuffer<InventoryItem>>()
                     .WithAll<PlayerTag>())
        {
            // 1. Iterate over buffer elements (reverse loop when removing)
            for (int i = inventory.Length - 1; i >= 0; i--)
            {
                var item = inventory[i];

                if (item.Quantity <= 0)
                {
                    // Remove depleted items
                    inventory.RemoveAt(i);
                }
                else
                {
                    // Modify element in place
                    item.Quantity--;
                    inventory[i] = item;
                }
            }

            // 2. Append new elements to the player's buffer
            inventory.Add(new InventoryItem { ItemId = 202, Quantity = 1 });
        }
    }
}
```

---

## 4. Cross-Entity Lookups in Parallel Jobs (`BufferLookup<T>`)

When parallel jobs need to inspect or read buffers attached to other entities (e.g., when a player entity loots a target chest or enemy), use `BufferLookup<T>`:[^unity-entities-buffer-jobs]

```csharp
using Unity.Entities;
using Unity.Burst;
using Unity.Collections;

public struct TargetLootEntity : IComponentData
{
    public Entity Value;
}

[BurstCompile]
public partial struct PlayerLootJob : IJobEntity
{
    // Read-only access to any entity's InventoryItem buffer
    [ReadOnly] public BufferLookup<InventoryItem> InventoryLookup;

    public void Execute(in TargetLootEntity target, ref DynamicBuffer<InventoryItem> playerInventory)
    {
        // Safely inspect target entity's inventory buffer across threads
        if (InventoryLookup.HasBuffer(target.Value))
        {
            DynamicBuffer<InventoryItem> targetInventory = InventoryLookup[target.Value];

            for (int i = 0; i < targetInventory.Length; i++)
            {
                // Transfer items into player inventory
                playerInventory.Add(targetInventory[i]);
            }
        }
    }
}

[BurstCompile]
public partial struct LootSystem : ISystem
{
    private BufferLookup<InventoryItem> _inventoryLookup;

    [BurstCompile]
    public void OnCreate(ref SystemState state)
    {
        _inventoryLookup = state.GetBufferLookup<InventoryItem>(isReadOnly: true);
    }

    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        // Always refresh lookup handles before scheduling parallel jobs
        _inventoryLookup.Update(ref state);

        new PlayerLootJob
        {
            InventoryLookup = _inventoryLookup
        }.ScheduleParallel();
    }
}
```

---

## 5. Modifying Buffers via EntityCommandBuffer (ECB)

When structural modifications or deferred commands are required, use ECB buffer operations:

```csharp
var ecb = SystemAPI.GetSingleton<EndSimulationEntityCommandBufferSystem.Singleton>()
                   .CreateCommandBuffer(state.WorldUnmanaged);

// 1. Add buffer asynchronously at playback
DynamicBuffer<InventoryItem> deferredBuffer = ecb.AddBuffer<InventoryItem>(newEntity);

// 2. Append an element to an existing entity's buffer at playback
ecb.AppendToBuffer(playerEntity, new InventoryItem { ItemId = 303, Quantity = 5 });
```

---

## 6. Best Practices & Memory Guidelines

* **Capacity Sizing**:
  * *Prefer*: Tuning `[InternalBufferCapacity(N)]` to cover the common case (e.g., 4–8 elements). Elements remain contiguous in the 16KB chunk without external allocations.
  * *Avoid*: Setting internal capacity excessively high when only a few entities utilize multiple elements (wastes chunk space and reduces archetype density).
* **Preallocating & Batch Operations**:
  * *Prefer*: Using `buffer.EnsureCapacity(count)` or `buffer.Resize(count, NativeArrayOptions.UninitializedMemory)` when batch-inserting elements to prevent repeated native heap reallocations.
* **Parallel Job Lookups**:
  * *Prefer*: `[ReadOnly] BufferLookup<T>` for cross-entity buffer access in parallel jobs to maintain deterministic, race-free execution.

---

## 7. Cross-References

- Component Taxonomy: [DOTS Component Declarations](ecs-components.md)
- Systems Lifecycle: [High-Performance Systems with ISystem](ecs-systems.md)
- Parallel Scheduling: [Jobs & Native Collections](jobs-native-collections.md)
- Structural Commands: [Entity Command Buffers](ecb-structural.md)

[^unity-entities-buffer-create]: Unity Entities 1.4 - Create a Dynamic Buffer Component
[^unity-entities-buffer-jobs]: Unity Entities 1.4 - Dynamic Buffers in Jobs
[^unity-entities-buffer-set-capacity]: Unity Entities 1.4 - Declare InternalBufferCapacity for a DynamicBuffer
