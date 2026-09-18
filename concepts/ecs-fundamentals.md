---
description: Core data-oriented architecture concepts (Entities, Components, Systems, Archetypes, Chunks) and unmanaged memory layout in Unity Entities 1.4+.
generated:
  at: 2026-09-04T22:30:00Z
  by: curator/antigravity
sources:
  - id: unity-entities-concepts
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/concepts-overview.html
    title: Unity Entities 1.4 - Concepts Overview
status: stable
tags:
  - dots
  - ecs
  - architecture
  - memory
  - performance
title: ECS Fundamentals vs OOP
type: Architecture Guide
---
# ECS Fundamentals vs OOP

Unity's Data-Oriented Technology Stack (DOTS) organizes gameplay state into contiguous, unmanaged memory blocks optimized for CPU cache lines and Burst compilation.[^unity-entities-concepts]

## Core Building Blocks

| Concept | Definition & Purpose | Idiomatic Usage |
| :--- | :--- | :--- |
| **Entity** | Lightweight 64-bit ID (`Index` + `Version`). Acts strictly as a lookup key. | Treat as an ID handle; manage via `EntityManager` or `EntityCommandBuffer`. |
| **Component** | Pure, unmanaged `struct` implementing `IComponentData`. | Contains state data only (blittable types, no managed class references). |
| **System** | Execution logic (`ISystem` struct with `[BurstCompile]`). | Queries components and transforms data in linear, vectorized loops. |
| **Archetype** | A unique combination of component types possessed by an entity. | Managed automatically by the `EntityManager`. |
| **Chunk** | A 16KB native memory block storing parallel arrays of components for an archetype. | Cache-friendly storage. Fits hundreds of entities per chunk for linear CPU prefetching. |
| **World** | Container holding an `EntityManager`, archetypes, chunks, and system groups. | Systems execute within their assigned World pipeline. |

## Memory Architecture

```
Traditional OOP (Scattered Managed Heap):
[GameObject] ──> Heap [Transform | Renderer | Scripts] (Frequent Cache Misses)

DOTS Archetype Chunk (16KB Native Memory Block):
Chunk (Archetype: LocalTransform + Velocity + Health):
[ LocalTransform, LocalTransform, LocalTransform, ... ]
[ Velocity,       Velocity,       Velocity,       ... ]
[ Health,         Health,         Health,         ... ]  <-- Streamed linearly to CPU Cache
```

## Canonical Example: Entity, Component, System

```csharp
using Unity.Entities;
using Unity.Mathematics;
using Unity.Burst;

// 1. Component: Pure unmanaged data struct
public struct MovementSpeed : IComponentData
{
    public float Value;
}

// 2. System: Unmanaged logic transforming component data
[BurstCompile]
public partial struct MovementSystem : ISystem
{
    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        float dt = SystemAPI.Time.DeltaTime;

        // Linear batch processing across matching archetype chunks
        foreach (var (transform, speed) in 
            SystemAPI.Query<RefRW<Unity.Transforms.LocalTransform>, RefRO<MovementSpeed>>())
        {
            transform.ValueRW.Position += new float3(0, 0, speed.ValueRO.Value * dt);
        }
    }
}
```

## Recommended Best Practices

* **Separation of Data & Logic**: Place state exclusively in `IComponentData` structs; place execution logic exclusively in `ISystem` structs.
* **Unmanaged Memory First**: Always make component structs unmanaged and blittable so the Burst compiler can vectorize instructions.
* **Stable Archetypes**: Keep entity component layouts stable during runtime loops.
  * *Prefer*: Use `IEnableableComponent` for high-frequency state toggling (e.g., active, stunned, visible).
  * *Avoid*: Frequently adding and removing component types at runtime, which forces entity migration between chunks.

## Cross-References
- Declare component types: [DOTS Component Declarations](ecs-components.md)
- Implement systems: [High-Performance Systems with ISystem](ecs-systems.md)
- Manage structural changes: [Entity Command Buffers](ecb-structural.md)

[^unity-entities-concepts]: Unity Entities 1.4 - Concepts Overview
