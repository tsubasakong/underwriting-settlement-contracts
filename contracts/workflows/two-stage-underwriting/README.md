# Two-Stage Underwriting Workflow

This directory will hold the workflow-specific underwriting implementation that was intentionally split out of `hook-contracts`.

Expected contents:
- workflow-scoped hook entrypoints
- coordinator/orchestration logic
- parent/close state management
- workflow-specific types that should not leak back into reusable hook infrastructure
