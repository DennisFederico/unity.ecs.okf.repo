---
description: Automated DOTS/ECS scene assembly protocols, Unity CLI connection workflows, and subscene rigging sequences via official Unity CLI and com.unity.pipeline.
generated:
  at: 2026-10-18T18:07:00Z
  by: curator/antigravity
sources:
  - id: unity-entities-subscenes
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/scenes-subscenes.html
    title: Unity Entities 1.4 - Subscenes
  - id: unity-entities-workflow-intro
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/ecs-workflow-intro.html
    title: Unity Entities 1.4 - ECS Workflow Introduction
status: stable
tags:
  - dots
  - ecs
  - subscene
  - unity-cli
  - pipeline
  - scene-assembly
  - automation
title: Agentic DOTS/ECS Scene Assembly
type: Playbook
---
# Agentic DOTS/ECS Scene Assembly

When AI developer agents assemble DOTS/ECS scenes programmatically, they should interact with the Unity Editor using the official Unity CLI (`unity`) and the `com.unity.pipeline` Editor IPC package. Following deterministic scene assembly sequences, checking editor connection readiness, and separating structural hierarchy from human visual polish ensures robust automation without triggering blocking modal dialogs or compilation loops.

---

## 1. Editor Discovery & Connection Protocol

The official Unity CLI connects directly to running Unity Editor instances through standard IPC provided by `com.unity.pipeline`. All command operations are executed without high-overhead tool polling.

### Agent Discovery Protocol:
Before executing any scene or GameObject operations, the agent must establish connectivity:
1. **Verify Editor Status**: Call `unity status --format json` to ensure an Editor is running and reports `"state": "ready"`.
   * *Targeting Specific Workspaces*: When multiple Editors are active, supply `--project-path <path>` to target the correct project root.
2. **Discover Registered Commands**: Call `unity command --format json` to inspect the list of available commands registered by `com.unity.pipeline` and project packages.
3. **Auto-Tick & Background Execution**: Ensure the Editor continues updating while the agent operates asynchronously:
   ```bash
   unity command set_autotick
   unity command editor_set_run_in_background
   ```

---

## 2. Core Rule: Zero Disposable Editor Scripts

AI developer agents must **not** write temporary or disposable C# scripts (such as `[MenuItem]` or `EditorSceneManager` utilities) in project asset folders to construct or configure scenes.

* **Risk of Disposable Scripts**: Induces compilation passes, risks compilation errors that lock the editor in Safe Mode, and can trigger blocking modal dialogs or scene dirtying loops.
* **The Agentic Alternative**: Use registered CLI commands (`unity command <name>`) or execute one-shot C# expressions directly via `unity command eval '<C#>'`. This drives scene hierarchy modifications deterministically via editor IPC without introducing temporary source files into `Assets/`.

---

## 3. Canonical Subscene Assembly Sequence

To assemble a functional DOTS/ECS scene with a linked SubScene via the Unity CLI, execute the following deterministic sequence:

### Step 1: Create the Entity SubScene Asset
Create the unmanaged entity subscene first so its asset path is ready for linking:
1. **Create New Empty Scene**:
   * Execute:
     ```bash
     unity command eval 'UnityEditor.SceneManagement.EditorSceneManager.NewScene(UnityEditor.SceneManagement.NewSceneSetup.EmptyScene);'
     ```
   * *SubScene Hygiene Note*: Using `NewSceneSetup.EmptyScene` prevents Unity's default template from creating a Main Camera and Directional Light, guaranteeing zero duplicate lighting or camera conflicts.
2. **Populate Entity Authoring Hierarchy**:
   * Instantiate visual prefabs, create authoring GameObjects, and attach Authoring `MonoBehaviour` and `Baker<T>` components:
     ```bash
     # Example: Instantiate visual prefab into active SubScene
     unity command eval 'var prefab = UnityEditor.AssetDatabase.LoadAssetAtPath<UnityEngine.GameObject>("Assets/Prefabs/Asteroid.prefab"); UnityEditor.PrefabUtility.InstantiatePrefab(prefab);'
     ```
   * Wire serialized authoring references and configuration parameters.
3. **Save SubScene Asset**:
   * Execute:
     ```bash
     unity command eval 'UnityEditor.SceneManagement.EditorSceneManager.SaveScene(UnityEngine.SceneManagement.SceneManager.GetActiveScene(), "Assets/Scenes/<SceneName>_entities.unity");'
     ```

### Step 2: Create the Main Scene Asset
Create the root managed scene containing engine environment, lighting, camera, and managed/UI bridges:
1. **Create New Default Scene**:
   * Execute:
     ```bash
     unity command eval 'UnityEditor.SceneManagement.EditorSceneManager.NewScene(UnityEditor.SceneManagement.NewSceneSetup.DefaultGameObjects);'
     ```
2. **Configure Main Camera & Lighting**:
   * Adjust camera and light transforms for the scene perspective.
   * Ensure URP Camera Data (`UniversalAdditionalCameraData`) is present for Universal Render Pipeline projects.
3. **Construct UI & Managed Companions**:
   * Create Canvas (`Canvas`, `CanvasScaler`, `GraphicRaycaster`).
   * Create TextMeshPro HUD elements and attach managed bridge companions (`SystemBase` observers).

### Step 3: Link and Open the SubScene Anchor
Attach the `Unity.Scenes.SubScene` component and open it in the hierarchy:
1. **Create Anchor GameObject & Attach SubScene**:
   * Execute:
     ```bash
     unity command eval 'var anchor = new UnityEngine.GameObject("Entities_SubScene"); var sub = anchor.AddComponent<Unity.Scenes.SubScene>(); sub.SceneAsset = UnityEditor.AssetDatabase.LoadAssetAtPath<UnityEditor.SceneAsset>("Assets/Scenes/<SceneName>_entities.unity");'
     ```
2. **Save the Main Scene**:
   * Execute:
     ```bash
     unity command eval 'UnityEditor.SceneManagement.EditorSceneManager.SaveScene(UnityEngine.SceneManagement.SceneManager.GetActiveScene(), "Assets/Scenes/<SceneName>.unity");'
     ```
3. **Open SubScene in Hierarchy**:
   * In Unity 6 Entities, a SubScene is closed by default upon initial creation. To display contents in the Scene View and trigger live baking:
     ```bash
     unity command eval 'var sub = UnityEngine.Object.FindFirstObjectByType<Unity.Scenes.SubScene>(); Unity.Scenes.Editor.SubSceneUtility.EditScene(new Unity.Scenes.SubScene[] { sub });'
     ```
   *(Or click the "Open" button on the SubScene component in the Inspector).*
4. **Save Updated Scene Hierarchy**:
   * Execute:
     ```bash
     unity command eval 'UnityEditor.SceneManagement.EditorSceneManager.SaveScene(UnityEngine.SceneManagement.SceneManager.GetActiveScene(), "Assets/Scenes/<SceneName>.unity");'
     ```

---

## 4. Visuals & Rendering Handoff Protocol

Configuring Universal Render Pipeline (URP) Global Volumes, Post-Processing profiles (Bloom, Tonemapping, Color Adjustments), Skyboxes, and complex lighting rigs programmatically via CLI eval or reflection scripts is fragile and prone to unrecoverable asset corruption.

### The Human Handoff Pattern:
When scene hierarchy assembly is complete, the agent must document a **Visual Setup Checklist** for the user and halt automated modifications:

```markdown
### Visual Setup Handoff Checklist
- [ ] **Global Volume**: Add a Global Volume to the Main Scene and assign the URP Post-Processing profile.
- [ ] **Lighting**: Set up Directional Light intensity and environment reflection probes.
- [ ] **Materials**: Assign target materials to the environment mesh renderers.
```

---

## 5. Best Practices & Guidelines

* **Editor Discovery**:
  * *Prefer*: Running `unity status --format json` to ensure `"state": "ready"` before initiating scene tasks.
  * *Avoid*: Sending commands without verifying editor connectivity and target workspace path.
* **Tooling Discipline**:
  * *Prefer*: Using registered CLI commands or one-shot `unity command eval` for scene hierarchy construction.
  * *Avoid*: Writing throwaway `[MenuItem]` or `EditorSceneManager` C# scripts in `Assets/` to generate scenes.
* **SubScene Hygiene**:
  * *Prefer*: Using `NewSceneSetup.EmptyScene` when creating SubScenes so no default cameras or directional lights exist.
  * *Avoid*: Placing managed cameras, audio listeners, directional lights, or UI canvases inside SubScenes.
* **Baking & PlayMode Verification**:
  * *Prefer*: Executing the official PlayMode verification loop:
    ```bash
    unity command editor_play
    unity status --until-ready
    # Inspect console output for baking errors
    unity command editor_stop
    ```
* **Visual Polish**:
  * *Prefer*: Delegating complex post-processing and lighting asset tweaks to the human user via a structured handoff checklist.
  * *Avoid*: Attempting to configure URP Global Volumes or ScriptableObject asset profiles through raw script execution.

---

## 6. Cross-References

- Scene Structure: [DOTS/ECS Scene Architecture & Subscenes](ecs-scene-architecture.md)
- Authoring & Baking: [Authoring & Baking](baking.md)
- Prefab Instantiation: [Entity Spawning & Prefabs](entity-spawning.md)
- Managed Bridges: [Hybrid ECS & Managed Bridges](hybrid-ecs.md)

[^unity-entities-subscenes]: Unity Entities 1.4 - Subscenes
[^unity-entities-workflow-intro]: Unity Entities 1.4 - ECS Workflow Introduction
