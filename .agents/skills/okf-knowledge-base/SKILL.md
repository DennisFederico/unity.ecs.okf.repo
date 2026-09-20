---
name: okf-knowledge-base
description: "Author, update, review, and maintain Open Knowledge Format (OKF) v0.2 knowledge cards, catalogs, and logs in the local repository. Use whenever creating new ECS knowledge cards, modifying existing cards, updating index.md or log.md, or validating bundle conformance with kiso-cli."
compatibility: "Any agent host with native filesystem and shell access."
---

# Open Knowledge Format (OKF) — Knowledge Base Authoring Guide

This repository hosts an [OKF v0.2](https://github.com/GoogleCloudPlatform/open-knowledge-format) knowledge bundle located at `ecs-okf/`.
Agents working in this repository MUST follow the authoring conventions, frontmatter schemas, link protocols, and validation steps described below.

## 1. Bundle Architecture & Storage Conventions

- **Bundle Root**: `ecs-okf/` (relative to the repository root).
- **Concept Cards**: Every non-reserved `.md` file is a standalone concept card.
- **Concept ID**: The concept ID is the filename without `.md` (e.g. `baking.md` -> ID: `baking`).
- **File Naming**: Lowercase kebab-case only (e.g. `entity-queries.md`, `dynamic-buffers.md`). No uppercase, no spaces, no `.mdx`.
- **Reserved Files**:
  - `index.md`: Catalog of all cards in the bundle.
  - `log.md`: Chronological changelog (newest entry first).

---

## 2. Concept Card Schema (YAML Frontmatter)

Every card MUST start with parseable YAML frontmatter with at least `type:`. Complete canonical cards should include all relevant metadata:

```yaml
---
type: Architecture Guide     # REQUIRED. Common types: Architecture Guide, Playbook, Troubleshooting Guide, Reference
title: Authoring & Baking   # Clear, descriptive title
description: Concise 1-2 sentence summary of the card's purpose and scope.
status: stable               # stable | draft | deprecated
tags:
  - dots
  - ecs
  - baking
generated:
  at: 2026-09-20T12:00:00Z   # ISO 8601 UTC timestamp (YYYY-MM-DDTHH:MM:SSZ)
  by: curator/agent-name     # Identifies the generating or authoring agent
sources:
  - id: unity-entities-baking # Kebab-case citation ID referenced in the body
    resource: https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/baking-overview.html
    title: Unity Entities 1.4 - Baking Overview
---
```

### Metadata Guidelines
- **`type`**: String, non-empty. Use consistent vocabulary:
  - `Architecture Guide`: Conceptual foundations, memory layout, system patterns.
  - `Playbook`: Step-by-step procedures, tool workflows, implementation recipes.
  - `Troubleshooting Guide`: Diagnostics, compilation errors, Burst limitations, resolutions.
  - `Reference`: API cheatsheets, component matrices, attribute tables.
- **`generated.at`**: Always format as full ISO 8601 UTC with explicit `Z` offset. Never use a bare date.
- **`sources`**: Every external technical claim or Unity documentation reference must have an entry in `sources` with a unique `id`.

---

## 3. Card Body Conventions

1. **Title Heading**: Begin the Markdown body with `# Title` (matching the frontmatter `title`).
2. **Citations & Footnotes**: Join claims directly to sources declared in frontmatter using Markdown footnotes:
   ```markdown
   Baking executes inside an isolated, headless Baking World.[^unity-entities-baking]
   ```
   *The footnote key `[^unity-entities-baking]` MUST match an `id` in `sources`.*
3. **Internal Cross-Linking**: Use standard Markdown relative links to other cards in the bundle:
   ```markdown
   For details on unmanaged components, see [DOTS Component Declarations](./ecs-components.md).
   ```
   - **Never** backtick links (`` `[text](./card.md)` `` is invalid).
   - **Never** use HTML `<a>` tags.
   - All links must resolve to valid `.md` files that exist in the bundle.
4. **Code Quality**:
   - Target **Unity Entities 1.4+** and **Unity 6+**.
   - Emphasize unmanaged `ISystem`, `IComponentData`, `SystemAPI.Query`, and Burst compilation.
   - Clarify boundaries between managed authoring (`MonoBehaviour`, `Baker<T>`) and unmanaged runtime.

---

## 4. Workflows

### Workflow A: Creating a New Card

1. **Check for Duplication**: Inspect `ecs-okf/index.md` or search existing cards in `ecs-okf/` to verify the topic isn't already covered.
2. **Choose Concept ID**: Formulate a kebab-case filename (e.g. `entity-hierarchies.md`).
3. **Write the Card**: Create `ecs-okf/<concept-id>.md` adhering to the frontmatter and body schema.
4. **Register in `index.md`**:
   - Open `ecs-okf/index.md`.
   - Add a bullet point under the appropriate category section:
     ```markdown
     * [Card Title](./<concept-id>.md) - One-line summary of topics covered.
     ```
5. **Record in `log.md`**:
   - Prepend a new entry to `ecs-okf/log.md`. Note: `kiso-cli` strictly requires the `##` heading to be ONLY the ISO date `## YYYY-MM-DD`:
     ```markdown
     ## YYYY-MM-DD

     ### Created <Title>
     - Added `ecs-okf/<concept-id>.md` covering <summary>.
     - Registered in `index.md`.
     ```
6. **Validate Conformance**:
   - Run:
     ```powershell
     kiso-cli.exe check -s ecs-okf
     ```
   - Confirm output is `No errors found.` Fix any warnings or broken links immediately.

---

### Workflow B: Updating / Fixing an Existing Card

1. **Read & Inspect**: Read `ecs-okf/<concept-id>.md` and its related cards.
2. **Edit Content**: Apply the required modifications, code updates, or API corrections.
3. **Update Frontmatter**:
   - Update `generated.at` or add `verified: [{ at: "<ISO-DATE>", by: "<agent>" }]`.
   - If new external documentation or URLs are cited, add them to `sources` and use corresponding `[^id]` footnotes in the body.
4. **Record in `log.md`**:
   - Prepend an entry to `ecs-okf/log.md`:
     ```markdown
     ## YYYY-MM-DD

     ### Updated <Title>
     - <Brief description of changes made>.
     ```
5. **Validate Conformance**:
   - Run:
     ```powershell
     kiso-cli.exe check -s ecs-okf
     ```
   - Confirm output is `No errors found.`

---

## 5. Conformance Verification with `kiso-cli`

Always validate the bundle after any change:

```powershell
kiso-cli.exe check -s ecs-okf
```

### Common Errors & Fixes
- `BROKEN_LINK`: A link `[text](./missing.md)` points to a file that does not exist or has a typo. Correct the path or filename.
- `INVALID_FRONTMATTER`: Missing `type:`, unquoted version string, or malformed YAML.
- `INVALID_OKF_VERSION`: Only the bundle root index may have `okf_version: "0.2"`. Individual concept cards or sub-indexes must NOT declare `okf_version`.
- `INVALID_LOG_DATE_FORMAT`: Headings in `log.md` must strictly be `## YYYY-MM-DD` without additional text on the heading line.
