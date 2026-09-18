---
description: High-performance UI streaming from ECS to UI Toolkit and uGUI, companion overhead health bars via UnityObjectRef, zero-allocation dirty checking, and canvas rebuild mitigation in Unity 6 and Entities 1.4+.
generated:
  at: 2026-09-07T23:40:00Z
  by: curator/antigravity
sources:
  - id: unity-ui-performance
    resource: https://docs.unity3d.com/6000.0/Documentation/Manual/UIE-performance-considerations.html
    title: Unity 6 - Performance Considerations for Runtime UI
  - id: unity-ui-elements
    resource: https://docs.unity3d.com/6000.0/Documentation/Manual/UIElements.html
    title: Unity 6 - UI Toolkit Manual
  - id: unity-entities-systembase
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/systems-systembase.html
    title: Unity Entities 1.4 - SystemBase
  - id: unity-hybrid-components
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/hybrid-components.html
    title: Unity Entities 1.4 - Companion GameObjects
status: stable
tags:
  - dots
  - ecs
  - ui
  - ui-toolkit
  - ugui
  - unityobjectref
  - performance
  - data-streaming
  - healthbar
title: UI Performance & DOTS Data Streaming
type: Architecture Guide
---
# UI Performance & DOTS Data Streaming

In high-performance DOTS games, simulation systems update thousands of entities across worker threads at high frame rates. However, user interfaces—whether built with modern **UI Toolkit** or standard **uGUI**—execute on the managed main thread. Naively polling ECS state every frame and formatting strings causes continuous garbage collection spikes and forces heavy layout recalculations. High-performance UI integration relies on **change-driven streaming** and structural UI batching.[^unity-ui-performance]

---

## 1. The Two UI Topologies in DOTS

Production games divide UI into two distinct architectural patterns:

| UI Topology | Target Elements | Recommended Paradigm | Primary Challenge |
| :--- | :--- | :--- | :--- |
| **Central Game HUD** | Screen-space health, score, ammo, cooldown timers, minimaps. | `SystemBase` querying singletons in `PresentationSystemGroup`. | Avoiding per-frame string allocations and unnecessary canvas redraws. |
| **Per-Entity In-World UI** | World-space overhead health bars, enemy nameplates, floating damage numbers. | Companion pattern using `UnityObjectRef<T>` components. | Preventing hundreds of independent canvas rebuilds and transform churn. |

---

## 2. Scenario A: Central Game HUD

### Option 1: Modern UI Toolkit (`UIDocument` + `SystemBase`)
In Unity 6, runtime UI Toolkit uses a `UIDocument` component on a scene GameObject.[^unity-ui-elements] A lightweight View `MonoBehaviour` binds the visual tree to the managed `SystemBase`:

#### 1. View Hook (`MonoBehaviour`)
```csharp
using UnityEngine;
using UnityEngine.UIElements;
using Unity.Entities;

[RequireComponent(typeof(UIDocument))]
public class PlayerHUDView : MonoBehaviour
{
    private void OnEnable()
    {
        var uiDocument = GetComponent<UIDocument>();
        VisualElement root = uiDocument.rootVisualElement;

        // Register the visual root element with the managed ECS bridge system
        var world = World.DefaultGameObjectInjectionWorld;
        if (world != null && world.IsCreated)
        {
            var hudSystem = world.GetExistingSystemManaged<PlayerHUDBridgeSystem>();
            hudSystem?.BindUI(root);
        }
    }
}
```

#### 2. Managed Bridge (`SystemBase`)
```csharp
using Unity.Entities;
using UnityEngine.UIElements;

[UpdateInGroup(typeof(PresentationSystemGroup))]
public partial class PlayerHUDBridgeSystem : SystemBase
{
    private ProgressBar _healthBar;
    private Label _scoreLabel;

    // Cache values for dirty checking
    private float _lastHealth = -1f;
    private int _lastScore = -1;

    protected override void OnCreate()
    {
        RequireForUpdate<PlayerTag>();
        RequireForUpdate<Health>();
        RequireForUpdate<Score>();
    }

    public void BindUI(VisualElement root)
    {
        _healthBar = root.Q<ProgressBar>("player-health-bar");
        _scoreLabel = root.Q<Label>("player-score-label");
    }

    protected override void OnUpdate()
    {
        if (_healthBar == null) return;

        var health = SystemAPI.GetSingleton<Health>();
        var score = SystemAPI.GetSingleton<Score>();

        // Numerical update (zero string allocation) strictly on value change
        if (health.Current != _lastHealth)
        {
            _lastHealth = health.Current;
            _healthBar.value = (health.Current / health.Max) * 100f;
        }

        // Label update strictly on value change
        if (score.Value != _lastScore)
        {
            _lastScore = score.Value;
            _scoreLabel.text = score.Value.ToString();
        }
    }
}
```

---

### Option 2: Legacy uGUI (`Canvas` + `SystemBase`)
If using standard uGUI Canvas for the central HUD, reference the UI components directly in a view MonoBehaviour:

```csharp
using UnityEngine;
using UnityEngine.UI;
using TMPro;
using Unity.Entities;

public class GameHUDCanvasView : MonoBehaviour
{
    public Slider HealthSlider;
    public TextMeshProUGUI ScoreText;

    private void Start()
    {
        var world = World.DefaultGameObjectInjectionWorld;
        if (world != null && world.IsCreated)
        {
            var system = world.GetExistingSystemManaged<GameHUDCanvasSystem>();
            system?.RegisterView(this);
        }
    }
}

[UpdateInGroup(typeof(PresentationSystemGroup))]
public partial class GameHUDCanvasSystem : SystemBase
{
    private GameHUDCanvasView _view;
    private float _lastHealth = -1f;
    private int _lastScore = -1;

    public void RegisterView(GameHUDCanvasView view) => _view = view;

    protected override void OnUpdate()
    {
        if (_view == null) return;

        var health = SystemAPI.GetSingleton<Health>();
        var score = SystemAPI.GetSingleton<Score>();

        if (health.Current != _lastHealth)
        {
            _lastHealth = health.Current;
            _view.HealthSlider.value = health.Current / health.Max;
        }

        if (score.Value != _lastScore)
        {
            _lastScore = score.Value;
            _view.ScoreText.text = score.Value.ToString();
        }
    }
}
```

---

## 3. Scenario B: Per-Entity Overhead Health Bars (`UnityObjectRef<Slider>`)

For floating overhead health bars attached to hundreds of moving entities (e.g., enemies, minions, RTS units), use the **Companion Pattern** via `UnityObjectRef<T>`:[^unity-hybrid-components]

### 1. Component Definition
```csharp
using Unity.Entities;
using UnityEngine.UI;

public struct HealthBarLink : IComponentData
{
    // Unmanaged handle holding reference to the managed uGUI Slider
    public UnityObjectRef<Slider> Slider;
}
```

### 2. Managed SystemBase Sync
```csharp
using Unity.Entities;
using UnityEngine.UI;

[UpdateInGroup(typeof(PresentationSystemGroup))]
public partial class EntityHealthBarSystem : SystemBase
{
    protected override void OnUpdate()
    {
        // Query units possessing both simulated Health and a linked Slider
        foreach (var (health, link) in 
            SystemAPI.Query<RefRO<Health>, RefRO<HealthBarLink>>())
        {
            // Explicit cast from UnityObjectRef to UnityEngine.UI.Slider
            Slider slider = (Slider)link.ValueRO.Slider;
            if (slider != null)
            {
                float targetRatio = health.ValueRO.Current / health.ValueRO.Max;

                // Dirty check: only assign if the value has changed
                if (slider.value != targetRatio)
                {
                    slider.value = targetRatio;
                }
            }
        }
    }
}
```

> [!TIP]
> **World-Space Canvas Optimization**: Avoid placing an independent `Canvas` component on each individual enemy prefab. Instantiating hundreds of mini-canvases causes severe draw-call fragmentation. Instead:
> 1. Use a single shared World-Space Canvas for all floating health bars.
> 2. Sync the slider positions to entity transforms in `PresentationSystemGroup`.
> 3. Disable `Pixel Perfect` on all world-space sliders.

---

## 4. uGUI Canvas Partitioning & Rebuild Mitigation

In uGUI, modifying *any* graphic element (Image, Text) marks the entire parent Canvas dirty, forcing Unity to regenerate the vertex buffer for all child elements on the CPU.

### Multi-Canvas Splitting:
* **Static Canvas**: Borders, portrait frames, HUD backdrops, and stationary labels. Never recalculates vertex buffers.
* **Dynamic Canvas**: Health bars, score counters, ammo indicators, and animated blips. Rebuilds are isolated and fast.
* **Sub-Canvases**: Nested scroll rects, inventory grids, and lists. Place a nested `Canvas` component on dynamic sub-trees to isolate their rebuilds from the rest of the HUD.

### Critical uGUI Settings:
* **Disable Raycast Target**: Uncheck `Raycast Target` on all text labels, icons, and decorative borders that do not respond to clicks. This eliminates raycast traversal overhead during user input.
* **Assign Event Camera**: Always assign an explicit `Camera` reference to World Space and Screen Space - Camera canvases to prevent fallback queries to `Camera.main`.

---

## 5. Zero-Allocation Numerical Formatting

1. **Direct Float Bindings**: Bind progress bars and fill sliders to normalized values (`slider.value = ratio`) rather than formatting string percentages (`$"{val}%"`).
2. **Pre-Cached Integer Lookup Tables**: For bounded integer counters (e.g., player ammo `0..99`), use a pre-allocated static string array:
   ```csharp
   _ammoText.text = AmmoLookup[ammoCount];
   ```
3. **Threshold Filtering**: For continuous floating-point variables (e.g., distance, speed), only update the UI text when the value shifts past a noticeable threshold (e.g., `math.abs(newVal - oldVal) > 0.5f`).

---

## 6. Best Practices & Guidelines

* **Architecture**:
  * *Prefer*: `SystemBase` running in `PresentationSystemGroup` for all UI streaming bridges.
  * *Prefer*: `UnityObjectRef<Slider>` companion components for individual overhead health bars.
* **Dirty Checking**:
  * *Prefer*: Caching previous values and only mutating UI element properties when data actually changes.
* **UI Toolkit (Unity 6)**:
  * *Prefer*: Registering the visual tree via a lightweight View `MonoBehaviour` in `OnEnable()`.
  * *Prefer*: Using `usageHints |= UsageHints.DynamicTransform` on moving visual elements.
* **uGUI**:
  * *Prefer*: Splitting Static and Dynamic elements into separate Canvases.
  * *Prefer*: A single shared World-Space Canvas for unit health bars rather than per-unit Canvases.
  * *Avoid*: Leaving `Raycast Target` checked on non-interactive text and images.
  * *Avoid*: Formatting strings every frame inside update loops.

---

## 7. Cross-References

- Hybrid Systems: [Hybrid ECS & Companion GameObjects](hybrid-ecs.md)
- System Execution Order: [High-Performance Systems with ISystem](ecs-systems.md)
- Singletons: [Singleton Components](singletons.md)
- User Input: [Unity Input System in DOTS](unity-input-system.md)
- Asset Streaming: [Asset References & Streaming](unity-asset-streaming.md)

[^unity-ui-performance]: Unity 6 - Performance Considerations for Runtime UI
[^unity-ui-elements]: Unity 6 - UI Toolkit Manual
[^unity-entities-systembase]: Unity Entities 1.4 - SystemBase
[^unity-hybrid-components]: Unity Entities 1.4 - Companion GameObjects
