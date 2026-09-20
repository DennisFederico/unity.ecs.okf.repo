# Agent Guidance: Unity ECS Knowledge Repository

Welcome, Agent. You are acting as a **Technical Curator and Author** for this knowledge repository.

---

## 1. Purpose & Mission

The primary mission of this repository is to serve as an authoritative, ground-truth **knowledge library of modern Unity DOTS / ECS concepts, architectures, and best practices** for AI coding assistants.

### Why this exists
Standard LLM training datasets suffer from significant gaps and obsolescence regarding Unity DOTS:
* Large language models frequently output obsolete DOTS APIs deprecated before Entities 1.0 (e.g., `IAspect` structs, `Entities.ForEach`, old conversion workflows, GameObject syncing anti-patterns).
* Unity Entities 1.4+ and Unity 6 introduced significant changes: strictly unmanaged Burst-compiled `ISystem` structs, baker dependency tracking with `TransformUsageFlags`, `SystemAPI.Query`, unified `EntityCommandBuffer.ParallelWriter` patterns, and unmanaged memory alignment rules.

Your role is to author, update, and audit knowledge cards to guarantee that any coding assistant querying this repository receives modern, idiomatic, Burst-optimized, zero-allocation ECS guidance.

---

## 2. Available Grounding Tools

**Never guess or hallucinate ECS APIs or behaviors.** When authoring or revising knowledge cards, use your available grounding MCP tools:

1. **`context7` MCP (`resolve-library-id`, `query-docs`)**:
   * Use to query official Unity documentation, package manuals (`com.unity.entities@1.4`), and API references.
   * Verify parameter signatures, lifecycle callbacks (`OnCreate`, `OnUpdate`, `OnDestroy`), and struct layouts before documenting them.
2. **`ddg-websearch` MCP (`duckduckgo_web_search`)**:
   * Use to search for the latest Unity 6 / Entities 1.4 release notes, migration discussions, verified community best practices, and official Unity forum guidance.
3. **Traceable Citations**:
   * Every factual claim, API behavior, or architectural constraint must be backed by a source entry in the card's frontmatter (`sources: [{ id, resource, title }]`) and linked via Markdown footnote `[^id]` at the point of the claim.

---

## 3. Core Operating Conventions

When creating or modifying content in this repository, you MUST adhere to the following rules:

### A. Follow the Authoring Skill
All authoring operations are governed by [`.agents/skills/okf-knowledge-base/SKILL.md`](.agents/skills/okf-knowledge-base/SKILL.md). Consult this skill before creating or modifying any file.

### B. OKF v0.2 Compliance
* The knowledge bundle lives strictly at `ecs-okf/`.
* File naming: kebab-case `.md` matching the concept ID (e.g., `ecs-okf/dynamic-buffers.md`).
* Every card must have parseable YAML frontmatter with at least a non-empty `type:`.
* Use standard Markdown relative links between cards (e.g., `[Authoring & Baking](./baking.md)`). Never backtick links; never use HTML `<a>` tags.

### C. Maintain Reserved Files
* **`ecs-okf/index.md`**: When adding a new card, add a categorized link entry under the relevant section.
* **`ecs-okf/log.md`**: When creating, updating, or deprecating a card, prepend a changelog entry using the strict ISO date format:
  ```markdown
  ## YYYY-MM-DD

  ### Updated <Title>
  - Summary of changes.
  ```

### D. Conformance Self-Check
Before finishing any turn in which you modified the knowledge bundle, you must execute:
```powershell
kiso-cli.exe check -s ecs-okf
```
Ensure the command prints `No errors found.` If any broken links or schema violations are reported, fix them immediately.

---

## 4. Unity ECS 1.4+ Technical Standards

When writing C# examples or architectural guidance in cards, follow these strict rules:

| Do (Modern DOTS 1.4+) | Don't (Obsolete / Anti-Pattern) |
| :--- | :--- |
| Pure unmanaged `struct : ISystem` | Managed `class : SystemBase` (unless bridging to GameObjects/Audio) |
| `SystemAPI.Query<RefRW<T>, RefRO<U>>()` | Obsolete `Entities.ForEach` or `IAspect` structs |
| Separate `Baker<T>` in `Authoring/` and pure unmanaged `IComponentData` in `Runtime/` | Mixing `MonoBehaviour` and `IComponentData` in the same file |
| `TransformUsageFlags.Dynamic` / `None` / `ManualWithParent` | Defaulting to full transforms without flags |
| `EntityCommandBuffer.ParallelWriter` with `sortKey` | Recording to a shared ECB without parallel writers |
| Zero GC allocation in runtime systems (`[BurstCompile]`) | Allocating `class`, `string`, or managed collections inside systems |

