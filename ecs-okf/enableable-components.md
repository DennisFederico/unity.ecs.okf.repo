---
description: High-frequency state toggling without structural changes using IEnableableComponent, EnabledRefRW, and query filters in Unity Entities 1.4+.
generated:
  at: 2026-09-07T08:35:00Z
  by: curator/antigravity
sources:
  - id: unity-entities-enableable-intro
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/components-enableable-intro.html
    title: Unity Entities 1.4 - Enableable Components Introduction
  - id: unity-entities-enableable-use
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/components-enableable-use.html
    title: Unity Entities 1.4 - Using Enableable Components
  - id: unity-entities-enableable-structural
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/structural-changes-enableable-components.html
    title: Unity Entities 1.4 - Manage Structural Changes with Enableable Components
status: stable
tags:
  - dots
  - ecs
  - components
  - enableable
  - performance
  - systemapi
title: Enableable Components
type: Architecture Guide
---
# Enableable Components

Enableable components allow an entity's component state to be toggled on or off at runtime without triggering structural changes, memory chunk migrations, or synchronization points.[^unity-entities-enableable-intro]

Behind the scenes, Unity maintains a 1-bit-per-entity enable mask inside each chunk. Toggling the component simply flips this bit in place.

---

## 1. Defining Enableable Components

Implement both `IComponentData` and `IEnableableComponent` on unmanaged structs:

```csharp
using Unity.Entities;

// Standard enableable component with data
public struct MovementSpeed : IComponentData, IEnableableComponent
{
    public float Value;
}

// Enableable tag component (zero-size marker)
public struct StunnedTag : IComponentData, IEnableableComponent { }
```

---

## 2. Baking Enableable Components

Inside an authoring `Baker<T>`, attach the component as usual and set its starting enabled bit using `SetComponentEnabled<T>`:[^unity-entities-enableable-use]

```csharp
using Unity.Entities;
using UnityEngine;

public class StunAuthoring : MonoBehaviour
{
    public bool StartStunned = false;

    class Baker : Baker<StunAuthoring>
    {
        public override void Bake(StunAuthoring authoring)
        {
            var entity = GetEntity(TransformUsageFlags.Dynamic);

            // 1. Add component to establish the archetype
            AddComponent<StunnedTag>(entity);

            // 2. Configure initial enabled state
            SetComponentEnabled<StunnedTag>(entity, authoring.StartStunned);
        }
    }
}
```

---

## 3. Querying & Filtering Enableable Components

When matching entities, ECS evaluates enableable components according to query constraints:[^unity-entities-enableable-structural]

| Query Method | Behavior |
| :--- | :--- |
| **Default `SystemAPI.Query<T>()`** | Matches only entities where `T` is **present AND enabled**. |
| **`.WithAll<T>()`** | Matches only entities where `T` is **present AND enabled**. |
| **`.WithDisabled<T>()`** | Matches only entities where `T` is **present AND disabled**. |
| **`.WithPresent<T>()`** | Matches entities having `T` regardless of enabled state. |
| **`.WithOptions(EntityQueryOptions.IgnoreComponentEnabledState)`** | Ignores enable bits across the entire query. |

---

## 4. Toggling State in Idiomatic Systems (`EnabledRefRW`)

To read or update enable bits during linear query iteration, include `EnabledRefRW<T>` in the `SystemAPI.Query` tuple:

```csharp
using Unity.Entities;
using Unity.Burst;

[BurstCompile]
public partial struct StunRecoverySystem : ISystem
{
    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        // Query entities that currently have StunnedTag enabled
        foreach (var (speed, stunnedEnabled) in 
            SystemAPI.Query<RefRW<MovementSpeed>, EnabledRefRW<StunnedTag>>().WithAll<StunnedTag>())
        {
            // Recover from stun: disable StunnedTag in-place
            stunnedEnabled.ValueRW = false;

            // Re-enable movement speed in-place
            speed.ValueRW.Value = 5.0f;
        }
    }
}
```

### Finding and Re-enabling Disabled Components
Use `.WithDisabled<T>()` when searching for entities that need to be re-activated:

```csharp
[BurstCompile]
public partial struct StunApplySystem : ISystem
{
    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        // Query entities where StunnedTag is present but currently disabled
        foreach (var stunnedEnabled in 
            SystemAPI.Query<EnabledRefRW<StunnedTag>>().WithDisabled<StunnedTag>())
        {
            // Activate stun state without structural changes
            stunnedEnabled.ValueRW = true;
        }
    }
}
```

---

## 5. Direct `EntityManager` Operations

Outside queries, query or set enablement directly on entity references:

```csharp
// Check status
bool isStunned = state.EntityManager.IsComponentEnabled<StunnedTag>(entity);

// Set status on a single entity
state.EntityManager.SetComponentEnabled<StunnedTag>(entity, true);

// Batch toggle: set enabled status across an entire query without chunk migration
state.EntityManager.SetComponentEnabled<StunnedTag>(stunQuery, false);
```

---

## 6. Best Practices & Guidelines

* **Frequent State Transitions**:
  * *Prefer*: `IEnableableComponent` for high-frequency gameplay states (e.g., active, stunned, visible, attacking, cooldowns).
  * *Avoid*: Dynamically adding and removing `IComponentData` or Tag components at runtime, which triggers archetype migrations and main-thread sync points.
* **Vectorized Iteration**:
  * *Prefer*: `EnabledRefRW<T>` inside idiomatic `foreach` or `IJobEntity` to maintain predictable linear memory access.
* **Entity Existence Precondition**:
  * An entity must already possess the component type before `SetComponentEnabled` or `EnabledRefRW` can be used. Ensure the component is attached at bake or spawn time.

---

## 7. Cross-References

- Component Taxonomy: [DOTS Component Declarations](ecs-components.md)
- Systems Architecture: [High-Performance Systems with ISystem](ecs-systems.md)
- Query Building: [Entity Queries & Filtering](entity-queries.md)
- Authoring & Baking: [Baking & Authoring](baking.md)

[^unity-entities-enableable-intro]: Unity Entities 1.4 - Enableable Components Introduction
[^unity-entities-enableable-use]: Unity Entities 1.4 - Using Enableable Components
[^unity-entities-enableable-structural]: Unity Entities 1.4 - Manage Structural Changes with Enableable Components
