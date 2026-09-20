---
description: Diagnostic catalog of canonical namespace imports, Roslyn source generator rules, Burst compiler restrictions, unmanaged struct boundaries, and compilation resolutions in Unity Entities 1.4+.
generated:
  at: 2026-09-08T00:10:00Z
  by: curator/antigravity
sources:
  - id: unity-entities-source-generator
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/source-generator.html
    title: Unity Entities 1.4 - Source Generator & Diagnostics
  - id: unity-burst-manual
    resource: https://docs.unity3d.com/Packages/com.unity.burst@1.8/manual/index.html
    title: Unity Burst Compiler Manual
  - id: unity-entities-troubleshooting
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/common-issues.html
    title: Unity Entities 1.4 - Common Issues & Troubleshooting
status: stable
tags:
  - dots
  - ecs
  - diagnostics
  - compilation-errors
  - namespaces
  - source-generator
  - burst
  - troubleshooting
title: Common Compilation & Burst Errors
type: Troubleshooting Guide
---
# Common Compilation & Burst Errors

Because Unity Entities relies heavily on compile-time C# Roslyn Source Generators and native Burst compilation, code that is legal in standard managed C# can fail to compile in DOTS. This guide catalogs the most common compiler diagnostics, source generator constraints, and API hallucinations with their verified resolutions.[^unity-entities-source-generator]

---

## 1. Canonical Namespace Reference Map (CS0246)

The most frequent compile-time failure for AI developer agents is `CS0246: The type or namespace name 'X' could not be found`.

> [!CAUTION]
> **Prevent Cascading Hallucinations**: When encountering `CS0246`, never attempt to replace DOTS native types with managed approximations (e.g., substituting `Vector3` for `float3`, or `List<T>` for `DynamicBuffer<T>`). Simply verify and add the missing `using` directive at the top of the file:

| Missing Type / Symbol | Required Namespace | Assembly Scope |
| :--- | :--- | :--- |
| `ISystem`, `IComponentData`, `SystemAPI`, `Entity`, `RefRO<T>`, `RefRW<T>` | `using Unity.Entities;` | Unmanaged / Core |
| `float2`, `float3`, `float4`, `quaternion`, `math`, `Random` | `using Unity.Mathematics;` | Native Math |
| `LocalTransform`, `LocalToWorld`, `Parent`, `Child` | `using Unity.Transforms;` | Spatial Hierarchy |
| `[BurstCompile]`, `BurstCompile` | `using Unity.Burst;` | Burst Compiler |
| `NativeArray<T>`, `NativeList<T>`, `Allocator`, `FixedString64Bytes` | `using Unity.Collections;` | Native Collections |
| `GameObject`, `Transform`, `MonoBehaviour`, `Color` | `using UnityEngine;` | Managed Authoring |
| `UIDocument`, `VisualElement`, `Label`, `ProgressBar` | `using UnityEngine.UIElements;` | UI Toolkit |
| `Slider`, `Canvas`, `Image`, `TextMeshProUGUI` | `using UnityEngine.UI;` | Legacy uGUI |
| `SceneSystem`, `EntitySceneReference` | `using Unity.Scenes;` | Scene Streaming |

---

## 2. Quick Diagnostic Resolution Matrix

| Diagnostic / Symptom | Root Cause | Verified Resolution |
| :--- | :--- | :--- |
| **Source Generator Failure** | System struct not marked `partial` | Add `partial` keyword: `public partial struct MySystem : ISystem`. |
| **Invalid Query Type / Not Implemented** | `SystemAPI.Query` assigned to a variable | Place `SystemAPI.Query` directly inline inside the `foreach` statement. |
| **Generic Argument Limits Exceeded** | Duplicate component in `.WithAll` and `Query<...>` | Remove component from `.WithAll<T>()` if it is already in `Query<RefRO<T>>`. |
| **CS0208 (Managed Type in Struct)** | Managed types (`string`, `class`, `GameObject`) in struct | Use `FixedString64Bytes`, `DynamicBuffer<T>`, or `UnityObjectRef<T>`. |
| **Method Not Found (`FromObject`)** | Hallucinated factory methods on `UnityObjectRef<T>` | Use implicit assignment to store, explicit cast `(GameObject)objRef` to read. |
| **Method Not Found (`AddComponentEnable`)**| Hallucinated enableable baking methods | Call `AddComponent<T>()` followed by `SetComponentEnabled<T>(entity, false)`. |
| **Burst BC1000+ Rejection** | Calling managed methods or `UnityEngine.Random` | Use `Unity.Mathematics.Random`, `Unity.Collections`, and unmanaged types. |

---

## 3. Roslyn Source Generator Constraints

Unity's source generators intercept `SystemAPI` calls at compile time to generate Burst-compatible lookups. They enforce strict structural patterns:

### Constraint A: Systems Must Be `partial`
* **Error**: Source generator skips emitting backing code; `SystemAPI` throws compile errors.
* **Rule**: Any system struct implementing `ISystem` that uses `SystemAPI` must be declared as `public partial struct`:
  ```csharp
  [BurstCompile]
  public partial struct MovementSystem : ISystem // Correct: partial keyword included
  {
      [BurstCompile]
      public void OnUpdate(ref SystemState state) { /* ... */ }
  }
  ```

### Constraint B: Inline `SystemAPI.Query` Declaration
* **Error**: Attempting to store a query in a local variable (`var q = SystemAPI.Query<...>()`) fails because `SystemAPI.Query` is a compiler interceptor with no standalone runtime enumerator.
* **Rule**: Always write `SystemAPI.Query` directly within the `foreach` statement:
  ```csharp
  // Correct: declared inline
  foreach (var (transform, speed) in 
      SystemAPI.Query<RefRW<LocalTransform>, RefRO<MovementSpeed>>())
  {
      // ...
  }
  ```
* *Alternative*: If an entity query must be cached across frames or passed to jobs, construct an `EntityQuery` once during `OnCreate` via `SystemAPI.QueryBuilder().Build()`.

### Constraint C: Query Signature Redundancy
* **Error**: Generic argument limits exceeded or duplicate type errors.
* **Rule**: Do not add `.WithAll<T>()` if `T` is already in the `Query<...>` tuple. All components listed in `Query<RefRO<T>, RefRW<U>>` are implicitly required. Reserve `.WithAll<V>()` strictly for tag components not present in the tuple.

---

## 4. Unmanaged Struct Boundaries (CS0208)

* **Error**: `CS0208: Cannot take the address of, get the size of, or declare a pointer to a managed type ('MyComponent')`.
* **Cause**: An `IComponentData`, `ICleanupComponentData`, or `IBufferElementData` struct contains a managed reference type (e.g., `string`, `class`, `GameObject`, or arrays `int[]`).

### Correct Unmanaged Replacements:

```csharp
using Unity.Entities;
using Unity.Collections;
using UnityEngine;

public struct PlayerData : IComponentData
{
    // 1. Replace string with FixedString
    public FixedString64Bytes Name;

    // 2. Replace GameObject/Transform references with UnityObjectRef
    public UnityObjectRef<GameObject> CompanionPrefab;

    // 3. Unmanaged primitive types are fully supported
    public int Level;
    public float Health;

    // NOTE: For resizable arrays, declare an IBufferElementData struct in a separate file
}
```

---

## 5. API Casting Rules (No Hallucinated Methods)

### `UnityObjectRef<T>` Conversion
* **Error**: Calling non-existent factory methods such as `.FromObject()`, `.ToObject()`, or `.Instantiate()`.
* **Rule**: Rely strictly on language-level casting operators:
  ```csharp
  // 1. Managed to ECS (Implicit cast)
  companionLink.Target = authoring.MyGameObject;

  // 2. ECS to Managed (Explicit cast)
  GameObject go = (GameObject)companionLink.Target;
  ```

### `IEnableableComponent` Baking
* **Error**: Calling non-existent methods like `AddComponentEnable()` or `AddComponent(entity, component, false)`.
* **Rule**: Use standard `AddComponent` followed by `SetComponentEnabled`:
  ```csharp
  // 1. Add component to entity
  AddComponent(entity, new ShieldTag());

  // 2. Disable initial state if needed
  SetComponentEnabled<ShieldTag>(entity, false);
  ```

---

## 6. Burst Compiler Violations (BC1000+)

The Burst compiler (`com.unity.burst`) translates .NET bytecode into highly optimized native machine code. It rejects any code that interacts with the managed runtime:[^unity-burst-manual]

### Common Burst Incompatibilities:
1. **Managed Random**: Calling `UnityEngine.Random` inside Burst jobs causes compilation failure.
   * *Resolution*: Use `Unity.Mathematics.Random`.
2. **String Formatting**: Calling `string.Format`, `ToString()`, or string concatenation `$""`.
   * *Resolution*: Move text formatting to managed `SystemBase` presentation systems.
3. **Boxing Allocations**: Casting structs to `object` or calling non-generic interfaces.
   * *Resolution*: Pass concrete unmanaged structs by `in` or `ref`.
4. **Static State Access**: Accessing mutable static managed fields inside Burst jobs.
   * *Resolution*: Pass data into jobs via unmanaged component lookups or job fields.

---

## 7. Best Practices & Guidelines

* **Namespaces First**:
  * *Prefer*: Checking missing `using` directives before altering types.
  * *Avoid*: Replacing `float3` with `Vector3` or `FixedString` with `string` when encountering type errors.
* **Declaration Discipline**:
  * *Prefer*: Declaring systems as `public partial struct MySystem : ISystem`.
  * *Prefer*: Declaring `IComponentData` structs as pure unmanaged types without managed heap types.
* **Query Patterns**:
  * *Prefer*: Writing `SystemAPI.Query` directly inline in `foreach` statements.
  * *Prefer*: `SystemAPI.QueryBuilder()` for caching `EntityQuery` instances in `OnCreate()`.
* **Burst Safety**:
  * *Prefer*: `Unity.Mathematics.Random` with explicit non-zero seeds for randomized gameplay simulation.
  * *Avoid*: `UnityEngine.Random` or string formatting in Burst-compiled methods.
* **Conversion Discipline**:
  * *Prefer*: Implicit and explicit cast operators for `UnityObjectRef<T>`.
  * *Avoid*: Searching for or calling non-existent factory methods like `.FromObject()`.

---

## 8. Cross-References

- Component Rules: [DOTS Component Declarations](ecs-components.md)
- Systems Lifecycle: [High-Performance Systems with ISystem](ecs-systems.md)
- Query Building: [Entity Queries & Filtering](entity-queries.md)
- Mathematics & Random: [Working with Random in ECS](random-in-ecs.md)
- Companion Bridging: [Hybrid ECS & Companion GameObjects](hybrid-ecs.md)
- Performance & SIMD: [Unity Platform & Burst Optimization](unity-platform-optimization.md)

[^unity-entities-source-generator]: Unity Entities 1.4 - Source Generator & Diagnostics
[^unity-burst-manual]: Unity Burst Compiler Manual
[^unity-entities-troubleshooting]: Unity Entities 1.4 - Common Issues & Troubleshooting
