# Initial Companion Repo Bootstrap Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Bootstrap the public companion repo for workflow-heavy underwriting settlement code with a minimal, reviewable structure.

**Architecture:** Start with documentation-first boundaries and a Foundry-oriented directory layout. Do not migrate old code yet; establish the repo surface that will receive the workflow-specific extraction after the split PRs land in `hook-contracts`.

**Tech Stack:** Solidity 0.8.x, Foundry, Markdown, GitHub.

### Task 1: Create the top-level repo surface

**Files:**
- Create: `README.md`
- Create: `.gitignore`
- Create: `foundry.toml`

**Step 1: Add the root README**

Describe:
- the purpose of the companion repo
- what belongs here versus in `hook-contracts`
- the initial directory layout
- the first planned workflow package

**Step 2: Add `.gitignore`**

Ignore:
- `cache/`
- `out/`
- `broadcast/`
- `lib/`
- `.env*`
- `.DS_Store`

**Step 3: Add `foundry.toml`**

Configure Foundry to use:
- `contracts/` as the source root
- `test/` as the test root

### Task 2: Create the initial workflow-oriented directories

**Files:**
- Create: `contracts/workflows/two-stage-underwriting/README.md`
- Create: `docs/workflows/README.md`
- Create: `test/README.md`

**Step 1: Add the workflow contracts placeholder**

Describe the intended contents of the two-stage underwriting workflow package.

**Step 2: Add the workflow docs placeholder**

Describe the workflow-docs boundary for this repository.

**Step 3: Add the test placeholder**

Describe the kinds of workflow behavior this repo will test.

### Task 3: Verify and publish

**Files:**
- Verify: `README.md`
- Verify: `foundry.toml`

**Step 1: Run `forge build`**

Expected: success with the empty scaffold.

**Step 2: Review the resulting tree**

Expected top-level shape:
- `contracts/`
- `docs/`
- `test/`
- `README.md`
- `foundry.toml`

**Step 3: Commit and push**

Create the first commit on `main` with the repo bootstrap.
