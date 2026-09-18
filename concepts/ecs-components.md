---
description: Canonical patterns for declaring unmanaged IComponentData structs, tags, and shared components in Unity Entities 1.4+, including memory alignment rules.
generated:
  at: 2026-09-04T23:05:00Z
  by: curator/antigravity
sources:
  - id: unity-entities-concepts-components
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/concepts-components.html
    title: Unity Entities 1.4 - Components Concept
  - id: unity-entities-buffer
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/components-buffer.html
    title: Unity Entities 1.4 - Dynamic Buffers
  - id: unity-entities-enableable
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/components-enableable.html
    title: Unity Entities 1.4 - Enableable Components
  - id: unity-entities-cleanup
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/components-cleanup.html
    title: Unity Entities 1.4 - Cleanup Components
status: stable
tags:
  - dots
  - ecs
  - components
  - memory
  - csharp
title: DOTS Component Declarations
type: Architecture Guide
---
# DOTS Component Declarations

Components in Unity Entities 1.4+ store unmanaged state data. While systems process execution logic, components define contiguous memory layouts optimized for CPU cache streaming and Burst compilation.[^unity-entities-concepts-components]

## 1. Component Categories Overview

| Category | Interface / Type | Official Definition & Purpose | Dedicated Guide |
| :--- | :--- | :--- | :--- |
| **Standard Component** | `IComponentData` | General unmanaged entity state stored contiguously in 16KB archetype chunks. | Section 2 below |
| **Tag Component** | `IComponentData` (0-byte) | Zero-size marker that defines an archetype without consuming chunk payload memory. | Section 3 below |
| **Dynamic Buffer** | `IBufferElementData` | *"A dynamic buffer component is a component that acts as a resizable array."* | [Dynamic Buffers](dynamic-buffers.md) |
| **Shared Component** | `ISharedComponentData` | Value-grouped component where entities with identical values share chunks. | Section 4 below |
| **Enableable Component** | `IEnableableComponent` | State toggling via chunk bitmasks without triggering structural changes. | [Enableable Components](enableable-components.md) |
| **Cleanup Component** | `ICleanupComponentData` | Preserves entity identity across `DestroyEntity` calls until cleanup completes. | [Cleanup Components](cleanup-components.md) |

---

## 2. Standard Component (`IComponentData`) & Struct Packing

Standard components must be unmanaged `struct` types. To minimize compiler-injected padding bytes and optimize cache line density, **order struct fields ascending by data type size**:

```csharp
using Unity.Entities;
using Unity.Mathematics;
using Unity.Collections;

// Optimal Memory Alignment: Fields sorted ascending by size (1B -> 2B -> 4B -> 8B)
// Total size: 24 bytes (0 padding waste)
public struct CharacterStats : IComponentData
{
    public byte TeamId;           // 1 byte  (Offset 0)
    public bool IsInvulnerable;   // 1 byte  (Offset 1)
    public short ArmorLevel;      // 2 bytes (Offset 2 - aligned to 2-byte boundary)
    public int MaxHealth;         // 4 bytes (Offset 4 - aligned to 4-byte boundary)
    public float MoveSpeed;       // 4 bytes (Offset 8 - aligned to 4-byte boundary)
    public int Experience;        // 4 bytes (Offset 12 - aligned to 4-byte boundary)
    public double LastAttackTime; // 8 bytes (Offset 16 - aligned to 8-byte boundary)
}
```

For unmanaged textual data, use fixed-size string buffers:
```csharp
public struct PlayerProfile : IComponentData
{
    public FixedString32Bytes DisplayName; // 32 bytes unmanaged
}
```

---

## 3. Tag Components (Zero-Size Markers)

Tag components declare an empty struct implementing `IComponentData`. They consume **0 bytes** of memory per entity within archetype chunks, but uniquely partition archetypes for fast query inclusion and exclusion:

```csharp
using Unity.Entities;

public struct PlayerTag : IComponentData { }
public struct EnemyTag : IComponentData { }
```

*Querying with Tags:*
```csharp
// Iterates only entities that possess PlayerTag
foreach (var (transform, speed) in 
    SystemAPI.Query<RefRO<LocalTransform>, RefRO<MoveSpeed>>().WithAll<PlayerTag>())
{
    // ...
}
```

---

## 4. Shared Components (`ISharedComponentData`)

Shared components group entities that possess identical values into dedicated chunks:

```csharp
using Unity.Entities;

public struct RenderLayer : ISharedComponentData
{
    public int LayerIndex;
}
```

### Shared Component Guidelines:
* *Prefer*: Low-cardinality values that partition large entity sets (e.g., subscene identifiers, rendering material IDs, team affiliations).
* *Avoid*: High-cardinality data or frequently mutated values (e.g., entity health or positions), which fragments memory into tiny, underutilized chunks.

---

## 5. Best Practices & Type Constraints

* **Unmanaged & Blittable**:
  * *Prefer*: SIMD-friendly types from `Unity.Mathematics` (`float3`, `quaternion`, `int2`, `float4`).
  * *Avoid*: Types from `UnityEngine` (`Vector3`, `Quaternion`) inside components, as they prevent auto-vectorization under the Burst compiler.
* **Asset & Object References**:
  * *Prefer*: `UnityObjectRef<T>` when an unmanaged component must store an unmanaged reference to a UnityEngine asset/authoring instance.
  * *Avoid*: Direct managed references (`GameObject`, `Transform`, `Material`) inside `IComponentData` structs.
* **State Toggling**:
  * *Prefer*: `IEnableableComponent` when toggling states frequently.
  * *Avoid*: Frequently adding and removing Tag components at runtime, which triggers costly archetype chunk migrations and sync points.

---

## 6. Cross-References

- Architecture: [ECS Fundamentals vs OOP](ecs-fundamentals.md)
- Resizable Arrays: [Dynamic Buffers](dynamic-buffers.md)
- Performance-Safe Toggling: [Enableable Components](enableable-components.md)
- Lifecycle & Destruction: [Cleanup Components](cleanup-components.md)
- Single-Instance Configuration: [Singleton Components](singletons.md)
- Authoring Conversion: [Baking & Authoring](baking.md)

[^unity-entities-concepts-components]: Unity Entities 1.4 - Components Concept
[^unity-entities-buffer]: Unity Entities 1.4 - Dynamic Buffers
[^unity-entities-enableable]: Unity Entities 1.4 - Enableable Components
[^unity-entities-cleanup]: Unity Entities 1.4 - Cleanup Components
