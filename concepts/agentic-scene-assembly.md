---
description: Automated DOTS/ECS scene assembly protocols, multi-editor port routing, and native component workflows via Anklebreaker Unity MCP.
generated:
  at: 2026-09-07T19:15:00Z
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
  - mcp
  - scene-assembly
  - automation
  - anklebreaker
title: Agentic DOTS/ECS Scene Assembly
type: Playbook
---
# Agentic DOTS/ECS Scene Assembly

When AI developer agents assemble DOTS/ECS scenes programmatically, they must interact with the Unity Editor using the native tooling suite of `anklebreaker-unity-mcp`. Following deterministic scene assembly sequences, managing editor instance ports, and separating structural hierarchy from human visual polish ensures robust automation without triggering blocking modal dialogs or compilation loops.

---

## 1. Multi-Editor Port & Instance Management

The `anklebreaker-unity-mcp` server can manage multiple concurrent Unity Editor instances. All MCP tool actions are routed to a specific editor instance through its designated **port** or **instance ID**.

### Agent Discovery Protocol:
Before executing any scene or GameObject operations, the agent must establish connectivity:
1. **List Active Instances**: Call `unity_list_instances` to retrieve running editors, their project paths, process IDs, and connection ports.
2. **Target Matching Instance**: Identify the instance matching the active workspace path and verify its assigned port.
3. **Select Instance**: Call `unity_select_instance` (or pass the port/instance ID parameter) to set the active communication channel.
4. **Health Check**: Call `unity_editor_ping` or `unity_editor_state` to ensure the editor is responsive and not currently in Play Mode or recompiling assemblies.

---

## 2. Core Rule: Zero Disposable Editor Scripts

AI developer agents must **not** write temporary or disposable C# scripts (such as `[MenuItem]` or `EditorSceneManager` utilities) in project asset folders to construct or configure scenes.

* **Risk of Disposable Scripts**: Induces compilation passes, risks compilation errors that lock the editor, and can trigger blocking modal dialogs or scene dirtying loops.
* **The Agentic Alternative**: Use native MCP scene and component tools (`unity_scene_new`, `unity_gameobject_create`, `unity_component_add`, `unity_component_set_reference`) to configure the scene deterministically via editor IPC.

---

## 3. Canonical Subscene Assembly Sequence

To assemble a functional DOTS/ECS scene with a linked SubScene via `anklebreaker-unity-mcp`, execute the following deterministic sequence:

### Step 1: Create the Entity SubScene Asset
Create the unmanaged entity subscene first so its asset path is ready for linking:
1. **Create New Empty Scene**:
   * Tool: `unity_scene_new`
   * Parameters: `discardUnsavedChanges: true`
2. **SubScene Hygiene (Mandatory)**:
   * Unity's default template automatically adds a camera and directional light. These MUST be deleted immediately to prevent overlapping cameras and lights with the Main Scene:
   * Tool: `unity_gameobject_delete`
   * Parameters: `path: "Main Camera"`
   * Tool: `unity_gameobject_delete`
   * Parameters: `path: "Directional Light"`
   * Verify hierarchy is 100% empty via `unity_scene_hierarchy`.
3. **Populate Entity Authoring Hierarchy**:
   * Instantiate prefabs: `unity_asset_instantiate_prefab` (`prefabPath`, `name`, `position`, `rotation`).
   * Create authoring GameObjects: `unity_gameobject_create` (`name`, `primitiveType: "Empty"`, `position`).
   * Attach Authoring MonoBehaviours: `unity_component_add` (`gameObjectPath`, `componentType`).
   * Wire serialized prefab and asset references: `unity_component_set_reference` (`path`, `componentType`, `propertyName`, `assetPath`).
4. **Save SubScene Asset**:
   * Tool: `unity_scene_save`
   * Parameters: `path: "Assets/Scenes/<SceneName>_entities.unity"`

### Step 2: Create the Main Scene Asset
Create the root managed scene containing engine environment, lighting, camera, and managed/UI bridges:
1. **Create New Scene**:
   * Tool: `unity_scene_new`
   * Parameters: `saveFirst: true`
2. **Configure Main Camera & Lighting**:
   * Adjust transform: `unity_gameobject_set_transform` (`path: "Main Camera"`, `position: {"x": 0, "y": 25, "z": -15}`, `rotation: {"x": 60, "y": 0, "z": 0}`).
   * Adjust light: `unity_gameobject_set_transform` (`path: "Directional Light"`, `rotation: {"x": 50, "y": -30, "z": 0}`).
   * Ensure URP Camera Data is attached in URP projects (`UniversalAdditionalCameraData`).
3. **Construct UI & Managed Companions**:
   * Create Canvas (`Canvas`, `CanvasScaler`, `GraphicRaycaster`).
   * Create TextMeshPro HUD elements and attach `ScoreBridgeMonoBehaviour`.
   * Wire UI component references using `unity_component_set_reference` (`path`, `componentType`, `propertyName`, `referenceGameObject`, `referenceComponentType`).

### Step 3: Link and Open the SubScene Anchor
Attach the `Unity.Scenes.SubScene` component and open it in the hierarchy:
1. **Create Anchor GameObject**:
   * Tool: `unity_gameobject_create`
   * Parameters: `name: "Entities_SubScene"`, `primitiveType: "Empty"`
2. **Attach SubScene Component**:
   * Tool: `unity_component_add`
   * Parameters: `gameObjectPath: "Entities_SubScene"`, `componentType: "Unity.Scenes.SubScene"`
3. **Assign Scene Asset Reference**:
   * Tool: `unity_component_set_reference`
   * Parameters:
     * `path`: `"Entities_SubScene"` (NOTE: `path`, not `gameObjectPath`)
     * `componentType`: `"Unity.Scenes.SubScene"`
     * `propertyName`: `"_SceneAsset"`
     * `assetPath`: `"Assets/Scenes/<SceneName>_entities.unity"`
4. **Save the Main Scene**:
   * Tool: `unity_scene_save`
   * Parameters: `path: "Assets/Scenes/<SceneName>.unity"`
5. **Open SubScene in Hierarchy**:
   * In Unity 6 Entities, a SubScene is closed by default. To display contents in the Scene View and trigger live baking:
   * Tool: `unity_execute_code`
   * Code:
     ```csharp
     var subScene = UnityEngine.Object.FindFirstObjectByType<Unity.Scenes.SubScene>();
     var t = System.Type.GetType("Unity.Scenes.Editor.SubSceneUtility, Unity.Scenes.Editor");
     t.GetMethod("EditScene", System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static)
      .Invoke(null, new object[] { new Unity.Scenes.SubScene[] { subScene } });
     ```
   *(Or click the "Open" button on the SubScene component in the Inspector).*
6. **Save Updated Scene Hierarchy**:
   * Tool: `unity_scene_save`
   * Parameters: `path: "Assets/Scenes/<SceneName>.unity"`

---

## 4. Visuals & Rendering Handoff Protocol

Configuring Universal Render Pipeline (URP) Global Volumes, Post-Processing profiles (Bloom, Tonemapping, Color Adjustments), Skyboxes, and complex lighting rigs programmatically via MCP or reflection scripts is fragile and prone to unrecoverable asset corruption.

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

* **Editor Routing**:
  * *Prefer*: Calling `unity_list_instances` to capture the correct editor port before initiating scene tasks.
  * *Avoid*: Sending tool calls without verifying editor state and port target.
* **Tooling Discipline**:
  * *Prefer*: Using native MCP component tools (`unity_scene_new`, `unity_component_add`, `unity_component_set_reference`) for scene hierarchy construction.
  * *Avoid*: Writing throwaway `[MenuItem]` or `EditorSceneManager` scripts to generate scenes.
* **Assembly Sequence**:
  * *Prefer*: Creating the `_entities.unity` SubScene before creating the Main Scene to enable seamless reference assignment.
  * *Prefer*: Saving the scene immediately after linking references via `unity_scene_save`.
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
