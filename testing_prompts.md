# Agent Authoring Test Prompts

These prompts are designed to test an AI agent (Antigravity, Copilot, Cursor, Claude Code, etc.) authoring and maintaining OKF knowledge cards using the [`.agents/skills/okf-knowledge-base`](file:///C:/Users/denni/Projects/unity.ecs.okf.repo/.agents/skills/okf-knowledge-base/SKILL.md) skill.

---

## Test Prompt 1: Create a New Knowledge Card

```markdown
You are an expert technical author working on the Unity ECS knowledge repository.
Follow the conventions and workflows defined in `.agents/skills/okf-knowledge-base/SKILL.md`.

Your task is to create a new canonical knowledge card on **Parent & Child Entity Hierarchies in Unity Entities 1.4+**:
1. Check `ecs-okf/index.md` and ensure the concept ID `entity-hierarchies` is unique.
2. Create `ecs-okf/entity-hierarchies.md` with:
   - Frontmatter: `type: Architecture Guide`, appropriate title, description, tags (`dots`, `ecs`, `hierarchy`, `transforms`), ISO 8601 UTC `generated.at`, and official Unity Entities documentation in `sources`.
   - Body: Explain the `Parent`, `Child`, and `PreviousParent` components, how baking converts GameObject parent-child transforms, structural change implications when reparenting entities at runtime via `EntityCommandBuffer`, and how `LocalTransform` and `PostTransformMatrix` propagate.
   - Cross-link to other related cards (such as `[Authoring & Baking](./baking.md)` and `[Entity Command Buffers](./ecb-structural.md)`).
   - Use footnote citations (e.g. `[^unity-entities-hierarchy]`) matching your declared `sources[].id`.
3. Register the new card in `ecs-okf/index.md` under the `## Architecture Guide` section with a one-line summary.
4. Prepend a new dated entry in `ecs-okf/log.md` using the strict `## YYYY-MM-DD` format describing the addition.
5. Run `kiso-cli.exe check -s ecs-okf` to verify that the bundle passes with 0 errors. If any warnings or errors are reported, resolve them before completing your turn.
```

---

## Test Prompt 2: Update / Fix an Existing Knowledge Card

```markdown
You are an expert technical author working on the Unity ECS knowledge repository.
Follow the conventions and workflows defined in `.agents/skills/okf-knowledge-base/SKILL.md`.

Your task is to update the existing knowledge card `ecs-okf/singletons.md`:
1. Read `ecs-okf/singletons.md`.
2. Update the card to add a dedicated section on **Accessing Singletons Inside Burst Jobs**:
   - Explain why `SystemAPI.GetSingleton<T>()` cannot be called inside `IJobEntity` or `IJobParallelFor` worker threads.
   - Provide the canonical pattern of passing the singleton value directly by value, or using `ComponentLookup<T>` passed into the job with `[ReadOnly]` for read access.
   - Include a concise, Burst-compatible code snippet demonstrating this pattern.
3. Update the frontmatter: update `generated.at` or add `verified` metadata with the current ISO timestamp and agent attribution.
4. Prepend a new dated entry in `ecs-okf/log.md` under the strict `## YYYY-MM-DD` heading detailing the update.
5. Run `kiso-cli.exe check -s ecs-okf` to verify that the bundle passes with 0 errors. If any warnings or errors are reported, resolve them before completing your turn.
```

