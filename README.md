# Unity ECS Knowledge Repository (OKF v0.2)

An authoritative, machine-readable knowledge base of **modern Unity DOTS / Entities 1.4+ and Unity 6** architecture patterns, best practices, and troubleshooting guides, formatted according to the [Open Knowledge Format (OKF) v0.2](https://github.com/GoogleCloudPlatform/open-knowledge-format).

---

## Purpose & Motivation

Large Language Models (LLMs) used in AI coding assistants frequently struggle with Unity DOTS because their pre-training corpora contain deprecated code patterns (such as obsolete `IAspect` implementations, `Entities.ForEach`, old conversion workflows, and managed component misuse). 

This repository bridges that gap by maintaining an up-to-date, grounded corpus of canonical ECS patterns that can be queried directly by AI assistants (Antigravity, GitHub Copilot, Cursor, Claude Code, etc.) during active development.

---

## Repository Structure

```text
unity.ecs.okf.repo/
├── .agents/
│   └── skills/
│       └── okf-knowledge-base/   # Authoring & maintenance protocol for AI agents
├── ecs-okf/                      # The OKF v0.2 Knowledge Bundle
│   ├── index.md                  # Root catalog of all concept cards
│   ├── log.md                    # Chronological changelog
│   ├── baking.md                 # Concept card: Baker<T> and TransformUsageFlags
│   ├── ecs-systems.md            # Concept card: Unmanaged ISystem lifecycle
│   ├── singletons.md             # Concept card: Singleton patterns and Burst access
│   └── ... (24+ concept cards)
├── AGENTS.md                     # Agent role, grounding tools, and technical rules
├── start_kiso-okf.ps1            # Starts the Kiso MCP Server (Streamable HTTP on port 61080)
├── testing_prompts.md            # Verified test prompts for authoring agents
└── README.md                     # Repository documentation
```

---

## Consuming the Knowledge Base via MCP

The repository is served using [Kiso](https://github.com/oak-invest/kiso), an open-source OKF publishing engine and MCP server.

### 1. Start the Server
From the repository root, run:
```powershell
./start_kiso-okf.ps1
```
*(Runs `kiso-mcp-server.exe -s ecs-okf -H 127.0.0.1 -p 61080`)*.

### 2. Client Agent Configuration
Connect your AI agents (across multiple active projects) by adding the following to your agent host's MCP settings:

```json
{
  "mcpServers": {
    "kiso-okf": {
      "type": "streamable-http",
      "url": "http://127.0.0.1:61080/mcp",
      "alwaysAllow": [
        "search_concepts",
        "get_concept_content"
      ]
    }
  }
}
```

### Available Consumer Tools
* **`search_concepts(query)`**: Discovers relevant cards for a given architectural or troubleshooting query.
* **`get_concept_content(concept_id)`**: Fetches the complete Markdown content, code samples, and citations for a concept (e.g. `baking`, `ecb-best-practices`).

---

## Authoring & Maintenance

Authoring is performed directly on the filesystem using Git and standard file tools, guided by [`.agents/skills/okf-knowledge-base/SKILL.md`](.agents/skills/okf-knowledge-base/SKILL.md) and [`AGENTS.md`](AGENTS.md).

### Validation
To validate the bundle for link integrity, schema conformance, and reserved file rules:
```powershell
kiso-cli.exe check -s ecs-okf
```

### Static Site Generation
To build human-readable HTML documentation and an `llms.txt` file from this bundle:
```powershell
kiso-cli.exe build -s ecs-okf
```

