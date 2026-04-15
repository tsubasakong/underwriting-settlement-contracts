# Two-Stage Underwriting Workflow

This directory contains the workflow-specific underwriting implementation that was intentionally split out of `hook-contracts`.

Contracts in this package:
- `TwoStageUnderwritingHook.sol`: ACP-facing hook shell with workflow-only wiring and view surface
- `TwoStageUnderwritingWorkflowCore.sol`: internal state machine for commit locking, sidecar state, parent/close linkage, and close-slot recovery
- `TwoStageUnderwritingEvaluator.sol`: EIP-712 relay for underwriter-signed `complete` / `reject` decisions
- `TwoStageUnderwritingCoordinator.sol`: coordinator that promotes funded jobs into the protected state
- `TwoStageUnderwritingTypes.sol`: workflow-scoped commit, evidence, decision, and sidecar-state types

This package is intentionally application-shaped. It is not meant to collapse back into the reusable hook examples surface in `hook-contracts`.
