---
description: Native Burst optimization, SIMD auto-vectorization, FloatMode.Fast directives, ProfilerMarker instrumentation, and mobile/console deployment tuning in Unity 6 and Entities 1.4+.
generated:
  at: 2026-09-08T00:15:00Z
  by: curator/antigravity
sources:
  - id: unity-burst-simd
    resource: https://docs.unity3d.com/Packages/com.unity.burst@1.8/manual/optimization-simd.html
    title: Unity Burst 1.8 - SIMD Vectorization
  - id: unity-burst-float-mode
    resource: https://docs.unity3d.com/Packages/com.unity.burst@1.8/manual/optimization-floating-point-options.html
    title: Unity Burst 1.8 - Floating-Point Precision Options
  - id: unity-entities-profiling
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/profile-overview.html
    title: Unity Entities 1.4 - Profiling Overview
status: stable
tags:
  - dots
  - burst
  - simd
  - optimization
  - profiling
  - floatmode
  - mobile
  - performance
title: Unity Platform & Burst Optimization
type: Architecture Guide
---
# Unity Platform & Burst Optimization

Achieving maximum frame rates across hardware targets—from mobile chipsets (ARM NEON) to high-end desktop and console CPUs (x86 AVX2)—requires leveraging Burst native compilation, hardware SIMD vectorization, and zero-allocation performance profiling.[^unity-burst-simd]

---

## 1. Burst Compiler Optimization Directives

By default, the Burst compiler follows standard floating-point precision rules. For gameplay physics, spatial transformations, and math-heavy simulations, configuring compilation directives yields massive throughput gains:[^unity-burst-float-mode]

```csharp
using Unity.Entities;
using Unity.Burst;

[BurstCompile(
    FloatMode = FloatMode.Fast, 
    FloatPrecision = FloatPrecision.Standard, 
    CompileSynchronously = true
)]
public partial struct HighThroughputSimulationSystem : ISystem
{
    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        // Simulation loops executing with SIMD hardware instructions
    }
}
```

### Directive Configuration:
* **`FloatMode.Fast`**: Permits the compiler to reorder algebraic calculations, eliminate redundant sub-expressions, and use hardware Fused Multiply-Add (FMA/`mad`) instructions. This unlocks aggressive auto-vectorization.
* **`FloatPrecision.Standard`**: Standardizes 32-bit single-precision floating-point operations, preventing costly 80-bit x87 hardware fallbacks.
* **`CompileSynchronously = true`**: Enforces synchronous native compilation when the system loads, eliminating first-frame JIT stalls and pipeline hitches in production builds.

> [!NOTE]
> **FloatMode.Fast Trade-off**: Algebraic reordering may introduce minor bit-level float differences compared to strict IEEE-754 mode. Do not use `FloatMode.Fast` for deterministic lockstep networking simulations where bit-identical cross-platform float math is mandatory.

---

## 2. SIMD Auto-Vectorization & Data Layout

SIMD (Single Instruction, Multiple Data) allows a CPU to execute an operation on multiple data elements in a single hardware cycle:[^unity-burst-simd]
* **x86 Architectures**: SSE4.2 (128-bit), AVX/AVX2 (256-bit, 8 floats per cycle).
* **ARM Architectures**: ARM NEON (128-bit, 4 floats per cycle on Android, iOS, and Apple Silicon).

### Leveraging SIMD in DOTS:
1. **Contiguous Chunk Storage**: Because ECS stores identical components sequentially inside 16KB memory chunks, Burst can stream contiguous vectors directly into SIMD registers with zero pointer dereferencing.
2. **Native Math Types**: Use `float4`, `float3`, `int4`, and `quaternion` from `Unity.Mathematics`. These unmanaged value types map directly to hardware vector registers:
   ```csharp
   // Hardware SIMD vector instruction (e.g., vmovups / fmla)
   float4 posA = new float4(1f, 2f, 3f, 4f);
   float4 posB = new float4(5f, 6f, 7f, 8f);
   float4 result = math.mad(posA, 2f, posB); // Single-cycle FMA instruction
   ```

---

## 3. Assembly Verification via Burst Inspector

To verify that systems and jobs are achieving native vectorization:
1. In the Unity Editor menu, select **Burst > Open Inspector...**.
2. Select your `ISystem` struct or `IJobEntity` job from the list.
3. Inspect the native disassembly pane:
   * **Vectorized Instructions (Green)**: Look for packed vector instructions such as `vmovups`, `vfmadd213ps` (x86) or `fmla.4s`, `ld1.4s` (ARM64).
   * **Scalar Instructions (Yellow/White)**: Individual float instructions (`movss`, `addss`) indicate the loop could not be vectorized.
   * **Branch Diagnostics**: Check for loop-carried dependencies or complex branching that forces scalar execution.

---

## 4. Zero-Allocation Profiling (`ProfilerMarker`)

To measure system execution times without introducing garbage collection overhead or managed reflection, instrument systems using unmanaged `ProfilerMarker` structs:[^unity-entities-profiling]

```csharp
using Unity.Entities;
using Unity.Burst;
using Unity.Profiling;

[BurstCompile]
public partial struct CombatResolutionSystem : ISystem
{
    // Static readonly marker compiles cleanly without allocations
    private static readonly ProfilerMarker s_CombatMarker = 
        new ProfilerMarker("CombatSystem.ResolveHits");

    [BurstCompile]
    public void OnUpdate(ref SystemState state)
    {
        // Scoped measurement block
        using (s_CombatMarker.Auto())
        {
            // Hot simulation logic...
        }
    }
}
```

### Profiling Rules:
* **Never Use Deep Profiling for Timing**: Deep Profiling injects managed instrumentation into every C# method call, distorting execution times and hiding native Burst performance gains.
* **Profile in Development Builds**: Always measure frame times on the target hardware using a **Development Build** connected to the Unity Profiler.
* **Identify Sync Bubbles**: In the Profiler CPU timeline, search for `WaitForJob` markers on the main thread; these highlight structural change sync points that are stalling worker threads.

---

## 5. Platform Deployment Tuning

### Mobile (Android & iOS)
* **Thermal Throttling**: Cap frame rates on startup (`Application.targetFrameRate = 60;` or `30` on low-end devices) to prevent mobile chipsets from overheating and dropping into sustained thermal throttling.
* **Worker Batch Tuning**: In `IJobEntity.ScheduleParallel(batchCount)`, tune the chunk batch size (default 32 to 64). Larger batch sizes reduce worker thread scheduling overhead on low-core mobile devices.
* **Texture Compression**: Use **ASTC** (Adaptive Scalable Texture Compression) across all modern mobile builds to reduce memory bandwidth pressure.

### Desktop & Console
* **Target Architecture**: Enable AVX2 target extensions in Burst Project Settings when targeting modern PCs and consoles to double SIMD register width from 128-bit to 256-bit.
* **Multi-Threaded Rendering**: Ensure the Scriptable Render Pipeline (URP) has **SRP Batcher** enabled to batch entity draw calls across the GPU.

---

## 6. Best Practices & Guidelines

* **Compiler Configuration**:
  * *Prefer*: `[BurstCompile(FloatMode = FloatMode.Fast, CompileSynchronously = true)]` for all gameplay systems and parallel worker jobs.
  * *Avoid*: Strict IEEE float modes unless deterministic cross-platform lockstep networking is mandatory.
* **Data Design**:
  * *Prefer*: `Unity.Mathematics` types (`float4`, `float3`, `quaternion`) to enable automatic SIMD vectorization.
  * *Avoid*: Storing data in scattered pointer arrays or non-contiguous structures.
* **Profiling Discipline**:
  * *Prefer*: `ProfilerMarker` inside unmanaged systems for accurate CPU timing.
  * *Prefer*: Standalone Development Player profiling over Editor profiling.
  * *Avoid*: Deep Profiling when taking real-world performance benchmarks.

---

## 7. Cross-References

- Core Architecture: [ECS Fundamentals vs OOP](ecs-fundamentals.md)
- Systems Architecture: [High-Performance Systems with ISystem](ecs-systems.md)
- Parallel Jobs: [Jobs & Native Collections](jobs-native-collections.md)
- Math & Determinism: [Working with Random in ECS](random-in-ecs.md)
- Compilation Diagnostics: [Common Compilation & Burst Errors](common-compilation-errors.md)

[^unity-burst-simd]: Unity Burst 1.8 - SIMD Vectorization
[^unity-burst-float-mode]: Unity Burst 1.8 - Floating-Point Precision Options
[^unity-entities-profiling]: Unity Entities 1.4 - Profiling Overview
