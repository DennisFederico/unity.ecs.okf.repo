# Unity ECS / DOTS Knowledge Base (OpenKnowledge + OKF)

An authoritative, curated [OpenKnowledge](https://openknowledge.ai/) knowledge base delivering high-performance **Unity Entities 1.4+ (DOTS)** patterns to AI developer assistants via the **Model Context Protocol (MCP)**.

This repository serves as the dedicated backend for an OpenKnowledge server running the Open Knowledge Format (`okf`) plugin. It isolates the knowledge base and OpenKnowledge Git hooks into an independent repository, ensuring clean separation from target game codebases and development harnesses.

---

## Purpose & Problem Solved

Modern AI coding agents frequently hallucinate when writing Unity DOTS code due to mixed training data containing deprecated paradigms (e.g., obsolete `IAspect`, pre-1.0 hybrid patterns, or illegal managed allocations inside Burst jobs). 

This repository provides an authoritative, zero-hallucination ground truth:
* **Entities 1.4+ Canonical Standards**: Modern unmanaged `ISystem`, `[BurstCompile]`, `EntityCommandBuffer`, and Authoring/Baking workflows.
* **Positive-Only Examples**: Strict adherence to working patterns with explicit "Prefer X / Avoid Y" guidance.
* **Decoupled Architecture**: Running as an independent background MCP server allows multiple IDEs (ZooCode, VS Code, Antigravity, Rider) to query shared ECS knowledge concurrently over standard HTTP/SSE.

---

## Initialization & Seeding

This repository was initialized using the [OpenKnowledge CLI](https://openknowledge.ai/):

```bash
# 1. Initialize OpenKnowledge repository with custom content directory and JSON formatting
ok init --no-mcp --content-dir okf-ecs --no-skills --json

# 2. Seed the OKF plugin for Open Knowledge Format schema management
ok seed -p okf --root .\okf-ecs
```

### Directory Structure
```
unity.ecs.okf.repo/
├── start_ok.ps1            # Windows PowerShell server launcher
├── start_ok.sh             # macOS / Linux Bash server launcher
├── README.md               # Repository documentation
├── .ok/                    # OpenKnowledge project configuration and indexes
└── okf-ecs/                # Designated content directory
    ├── index.md            # Catalog root index
    └── concepts/           # 23 canonical Entities 1.4+ concept cards (Layers 1–7)
```

---

## Starting the Server

The server runs on port **`61894`** and exposes HTTP/SSE endpoints. Launch scripts are provided for Windows and Unix environments:

### Windows (PowerShell)
Run `start_ok.ps1`:
```powershell
$env:OK_RECLAIM_DISABLE = "1"
ok start -p 61894 --only server --idle-shutdown off
```

### macOS / Linux (Bash)
Run `start_ok.sh`:
```bash
#!/bin/bash
export OK_RECLAIM_DISABLE="1"
export OK_ALLOW_EXTERNAL="1"
ok start -p 61894 --only server --idle-shutdown off
```

### Important Configuration Notes
* **`OK_RECLAIM_DISABLE=1`**: **Crucial setting.** Prevents OpenKnowledge from running its auto-repair sweep against client configuration files (`mcp_config.json`). This ensures client MCP configurations referencing the HTTP/SSE URL remain intact and are not overwritten by local stdio process definitions.
* **`--only server`**: Runs the standalone MCP server without launching the interactive terminal UI.
* **`--idle-shutdown off`**: Keeps the server running indefinitely in the background so it remains responsive across agent sessions.

### Endpoints
* **MCP Protocol Endpoint (SSE)**: `http://127.0.0.1:61894/mcp`
* **Readiness Probe**: `http://127.0.0.1:61894/readyz` (returns HTTP 200 when ready)
* **Health Probe**: `http://127.0.0.1:61894/healthz` (returns HTTP 200 when healthy)

---

## Client MCP Configuration Examples

Connecting to the OpenKnowledge server over HTTP/SSE eliminates local process spawning conflicts, reduces memory overhead, and allows multiple coding agents to share the same knowledge instance.

Add the following configuration snippet to your assistant's MCP configuration:

### ZooCode / Roo Code (`.roo/mcp.json`)
```json
{
  "mcpServers": {
    "open-knowledge": {
      "serverURL": "http://127.0.0.1:61894/mcp",
      "type": "sse"
    }
  }
}
```

### VS Code (`.vscode/mcp.json`)
```json
{
  "servers": {
    "open-knowledge": {
      "serverURL": "http://127.0.0.1:61894/mcp",
      "type": "sse"
    }
  }
}
```

### Antigravity / Gemini CLI (`~/.gemini/config/mcp_config.json`)
```json
{
  "mcpServers": {
    "open-knowledge": {
      "serverURL": "http://127.0.0.1:61894/mcp",
      "type": "sse"
    }
  }
}
```

---

## Exposed MCP Tools

When connected, the server exposes the standard OpenKnowledge tool suite:

* **`open-knowledge:search`**: Keyword and semantic search across the entire concept card library.
* **`open-knowledge:read`**: Retrieves full card contents by slug (e.g., `concepts/baking` or `concepts/unity-input-system`).
* **`open-knowledge:list`**: Lists all available cards and navigation structure.
* **`open-knowledge:exec`**: Executes OpenKnowledge CLI management commands.

---

## Concept Curriculum (Layers 1–7)

The `okf-ecs/concepts/` directory contains 23 grounded concept cards:

| Layer | Focus Area | Cards Included |
| :--- | :--- | :--- |
| **Layer 1** | **Core Paradigms** | `ecs-fundamentals.md`, `ecs-components.md` |
| **Layer 2** | **Data Layouts & Types** | `singletons.md`, `enableable-components.md`, `dynamic-buffers.md`, `cleanup-components.md`, `aspects.md` |
| **Layer 3** | **Execution & Scheduling** | `ecs-systems.md`, `entity-queries.md`, `jobs-native-collections.md`, `random-in-ecs.md` |
| **Layer 4** | **Structural Changes & Lifecycle** | `ecb-structural.md`, `ecb-best-practices.md`, `entity-spawning.md` |
| **Layer 5** | **Authoring & Scene Assembly** | `baking.md`, `ecs-scene-architecture.md`, `agentic-scene-assembly.md` |
| **Layer 6** | **Cross-Paradigm Bridges** | `hybrid-ecs.md`, `unity-input-system.md`, `unity-ui-performance.md`, `unity-asset-streaming.md` |
| **Layer 7** | **Diagnostics & Optimization** | `common-compilation-errors.md`, `unity-platform-optimization.md` |

---

## References

* **OpenKnowledge**: [https://openknowledge.ai/](https://openknowledge.ai/)
* **Unity Entities Documentation**: [Unity Entities Package Manual](https://docs.unity3d.com/Packages/com.unity.entities@1.4/manual/index.html)
* **AI Development Harness**: Used alongside [unity.ai.dev.harness](https://github.com/dennis/unity.ai.dev.harness)

