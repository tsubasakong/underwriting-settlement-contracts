# underwriting-settlement-contracts

Workflow-oriented settlement and orchestration contracts for underwriting flows built on top of ERC-8183 ACP hooks.

## Purpose

This repository is the companion home for workflow-heavy underwriting logic that should not live in `hook-contracts`.

In particular, this repo is the intended landing zone for:
- two-stage parent/close underwriting flows
- workflow coordinators and orchestration state
- settlement identity bookkeeping
- larger workflow sequence documentation
- workflow-specific tests and recovery logic

`hook-contracts` should stay focused on reusable hook building blocks. This repo exists for the larger application-shaped workflow layer.

## Repository Boundary

Keep in `hook-contracts`:
- foundational hook routing infrastructure
- small reusable hook blocks
- the single-stage `UnderwritingHook` / `UnderwritingEvaluator` surface

Keep in this repository:
- workflow-specific underwriting coordinators
- parent/close linkage
- active close slot management
- recovery and replacement behavior for close flows
- multi-stage documentation and end-to-end workflow tests

## Current Package

This repository now includes an implemented workflow package under:

```text
contracts/workflows/two-stage-underwriting/
```

Main contracts:
- `TwoStageUnderwritingHook.sol`
- `TwoStageUnderwritingWorkflowCore.sol`
- `TwoStageUnderwritingEvaluator.sol`
- `TwoStageUnderwritingCoordinator.sol`
- `TwoStageUnderwritingTypes.sol`

The names stay intentionally workflow-scoped so the package does not read like a generic hook lego block.

## Repo Layout

```text
contracts/
  workflows/
    two-stage-underwriting/
docs/
  workflows/
  plans/
test/
```

## Implemented Flow

The current package models a two-stage parent/close underwriting workflow:
- a root job commits underwriting terms and may opt into a later close stage
- a coordinator promotes funded jobs from `FeeEscrowed` to `Protected`
- provider submission must match the committed evidence hashes
- an underwriter-signed evaluator relay finalizes submitted jobs via `complete` / `reject`
- while a job is still `Open`, the configured client may still reject it directly
- a successful root job can move into `AwaitingClose`
- one active close job may be admitted at a time, with replacement after terminal close outcomes

The detailed sequence is documented in [docs/workflows/two-stage-underwriting.md](./docs/workflows/two-stage-underwriting.md).

## Tooling

This repo is bootstrapped as a Foundry project with `contracts/` as the source root.

Primary commands:

```bash
forge build
forge test
```

## Getting Started

This repository uses Foundry git submodules for external libraries.

Fresh clone setup:

```bash
git clone --recurse-submodules https://github.com/tsubasakong/underwriting-settlement-contracts.git
cd underwriting-settlement-contracts
forge build
```

If the repo was already cloned without submodules:

```bash
git submodule update --init --recursive
forge build
```
