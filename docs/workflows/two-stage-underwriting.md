# Two-Stage Underwriting Workflow

## Purpose

This package models an underwriting flow where a root job may later admit one hook-linked close job under the same underwriter.

The workflow stays outside `hook-contracts` because it depends on orchestration state that is specific to a two-stage settlement design:
- parent/close lineage
- active close slot management
- settlement identity pinned to the parent job
- replacement/recovery semantics for terminal close jobs

## Contract Roles

- `TwoStageUnderwritingHook`
  - the ACP-facing shell
  - owns workflow-only admin wiring for evaluator and coordinator
  - exposes workflow views such as `jobSettlementJobId`, `isAwaitingClose`, and active close lookup

- `TwoStageUnderwritingWorkflowCore`
  - owns commit locking and sidecar state
  - validates close-job admission against an approved parent
  - clears stale close slots after terminal close outcomes

- `TwoStageUnderwritingEvaluator`
  - verifies EIP-712 underwriter signatures
  - relays submitted-job `complete` / `reject` decisions into ACP

- `TwoStageUnderwritingCoordinator`
  - promotes funded jobs from `FeeEscrowed` to `Protected`

## Root Flow

1. Client creates a job pointing at `TwoStageUnderwritingHook` and the workflow evaluator.
2. Client commits underwriting terms with `setBudget(jobId, token, amount, abi.encode(commit))`.
3. The hook locks `{commit, paymentToken, budget}` and marks the job `Committed`.
4. Funding moves the job to `FeeEscrowed`.
5. The coordinator marks the job `Protected`.
6. Provider submits evidence whose hashes must match the committed underwriting terms.
7. For submitted jobs, the evaluator relays an underwriter-signed `complete` or `reject`.

While a job is still `Open`, the configured client may still reject it directly.

If the root commit set `allowCloseJob = true` and completion succeeds, the parent moves to `AwaitingClose`.

## Close Flow

1. A new ACP job is created for the close stage.
2. Its commit points to `parentJobId` and must reuse the same client, provider, evaluator, hook, and underwriter as the parent.
3. Only one active close slot may exist for a parent at a time.
4. The close job follows the same `Committed -> FeeEscrowed -> Protected -> EvidenceSubmitted` path.
5. Successful close completion clears the active close slot and collapses settlement identity back to the parent job, while parent linkage remains queryable for lookup and recovery.

## Recovery

- `Rejected`, `Cancelled`, and `Expired` close jobs release the active close slot for later replacement.
- Close rejection leaves the parent in `AwaitingClose`.
- Settlement identity for a close job remains the parent job id while the close stage is active.
- Submitted-job rejection is evaluator-gated, while `Open` jobs may still be rejected directly by the configured client.

## Verification

Current test coverage lives in:
- `test/TwoStageUnderwritingSmoke.t.sol`
- `test/TwoStageUnderwritingRootFlow.t.sol`
- `test/TwoStageUnderwritingCloseFlow.t.sol`
- `test/TwoStageUnderwritingRecovery.t.sol`
