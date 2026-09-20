# Changelog

## 2026-09-20

### Updated EntityCommandBuffer Best Practices & Parallel Writing
- Reframed Section 4 ("System-Managed vs Manual ECB Lifecycle") to emphasize the record-and-forget pattern for runtime systems.
- Prohibited manual `ecb.Playback()` in runtime systems within the lifecycle comparison table and added a `[!CAUTION]` callout box.
- Updated lifecycle discipline guidelines in Section 5 to reinforce zero manual playback or disposal calls in runtime game systems.

### Transitioned to Standalone OKF v0.2 Bundle

- Decommissioned OpenKnowledge server configurations and CRDT shadow artifacts.
- Relocated knowledge bundle to root `./ecs-okf` as a clean, standalone OKF v0.2 bundle.
- Established baseline catalog of 24 canonical Unity ECS 1.4+ architecture, playbook, and troubleshooting cards.
- Refined `.agents/skills/okf-knowledge-base/` for native file-based authoring and `kiso-cli` validation.

