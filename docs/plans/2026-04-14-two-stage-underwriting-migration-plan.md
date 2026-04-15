# Two-Stage Underwriting Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate the workflow-heavy two-stage underwriting settlement scaffold into this companion repository as a self-contained Foundry package.

**Architecture:** Keep this repository self-contained. Recreate only the ACP-facing interfaces needed to compile and test the workflow package locally, then implement the workflow-specific hook, evaluator, coordinator, and state machine under `contracts/workflows/two-stage-underwriting/`. Finish with workflow-focused tests and docs.

**Tech Stack:** Solidity 0.8.x, Foundry, OpenZeppelin, forge-std, Markdown.

### Task 1: Set up dependencies and local ACP-facing interfaces

**Files:**
- Modify: `foundry.toml`
- Create: `remappings.txt`
- Create: `contracts/interfaces/IAgenticCommerce.sol`
- Create: `contracts/interfaces/IACPHook.sol`

**Step 1: Install the minimal external libraries**

Use Foundry libraries for:
- OpenZeppelin contracts
- forge-std

Do not add a direct source dependency on the `hook-contracts` repo.

**Step 2: Add local ACP-facing interfaces**

Define only the surface the workflow package needs:
- `IAgenticCommerce.Job`
- `IAgenticCommerce.JobStatus`
- `getJob`
- `complete`
- `reject`
- `IACPHook.beforeAction`
- `IACPHook.afterAction`

**Step 3: Verify the dependency/config layer**

Run:
- `forge build`

Expected:
- dependency imports resolve
- empty interface layer compiles

**Step 4: Commit**

Commit message:
- `chore: add local ACP interfaces and Foundry deps`

### Task 2: Implement the workflow contracts

**Files:**
- Create: `contracts/workflows/two-stage-underwriting/TwoStageUnderwritingTypes.sol`
- Create: `contracts/workflows/two-stage-underwriting/ITwoStageUnderwritingHookView.sol`
- Create: `contracts/workflows/two-stage-underwriting/TwoStageUnderwritingWorkflowCore.sol`
- Create: `contracts/workflows/two-stage-underwriting/TwoStageUnderwritingHook.sol`
- Create: `contracts/workflows/two-stage-underwriting/TwoStageUnderwritingEvaluator.sol`
- Create: `contracts/workflows/two-stage-underwriting/TwoStageUnderwritingCoordinator.sol`

**Step 1: Create the workflow-specific type layer**

Define:
- sidecar states
- commit shape
- evidence shape
- decision payloads

Keep the names explicitly workflow-scoped.

**Step 2: Implement the core workflow state machine**

Move:
- commit locking
- parent/close linkage
- active close slot management
- close-slot recovery
- evidence matching
- settlement identity helpers

**Step 3: Implement the ACP-facing hook shell**

Use a direct `IACPHook` implementation plus local routing for:
- `setBudget`
- `fund`
- `submit`
- `complete`
- `reject`

**Step 4: Implement evaluator and coordinator**

Add:
- EIP-712 signature relay evaluator
- funding orchestration coordinator

**Step 5: Verify**

Run:
- `forge build`

**Step 6: Commit**

Commit message:
- `feat: add two-stage underwriting workflow contracts`

### Task 3: Add focused workflow tests

**Files:**
- Create: `test/mocks/MockAgenticCommerce.sol`
- Create: `test/mocks/MockWiringTarget.sol`
- Create: `test/TwoStageUnderwritingRootFlow.t.sol`
- Create: `test/TwoStageUnderwritingCloseFlow.t.sol`
- Create: `test/TwoStageUnderwritingRecovery.t.sol`

**Step 1: Write the root-flow test first**

Cover:
- root commit admission
- funding transition
- coordinator protection
- evidence submission
- underwriter-driven completion or rejection path

**Step 2: Write the close-flow test**

Cover:
- approved parent enters `AwaitingClose`
- close commit requires matching actors and underwriter
- successful close clears linkage

**Step 3: Write the recovery test**

Cover:
- close rejection clears only the active close slot
- expired close can be replaced on next close attempt

**Step 4: Verify**

Run:
- `forge test`

**Step 5: Commit**

Commit message:
- `test: cover two-stage underwriting workflow flows`

### Task 4: Finalize repo-facing documentation

**Files:**
- Modify: `README.md`
- Modify: `contracts/workflows/two-stage-underwriting/README.md`
- Create: `docs/workflows/two-stage-underwriting.md`

**Step 1: Update the root README**

Describe the now-implemented workflow package and its boundary relative to `hook-contracts`.

**Step 2: Replace placeholder workflow docs**

Document:
- the two-stage flow
- the contract roles
- what remains intentionally workflow-specific

**Step 3: Verify**

Run:
- `forge build`
- `forge test`

**Step 4: Commit**

Commit message:
- `docs: document two-stage underwriting workflow package`
