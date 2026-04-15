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

## Initial Layout

```text
contracts/
  workflows/
    two-stage-underwriting/
docs/
  workflows/
  plans/
test/
```

## Planned First Workflow Package

The initial extraction target is a two-stage underwriting package with names along these lines:

- `TwoStageUnderwritingHook.sol`
- `TwoStageUnderwritingWorkflowCore.sol`
- `TwoStageUnderwritingCoordinator.sol`
- `TwoStageUnderwritingTypes.sol`

Those names are intentionally workflow-scoped, so the package does not read like a generic lego block.

## Tooling

This repo is bootstrapped as a Foundry project with `contracts/` as the source root.

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
