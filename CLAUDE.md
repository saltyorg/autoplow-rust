# Autoplow: agent instructions

Autoplow is a Rust daemon for Saltbox that combines:
- media-server scan triggers
- per-file rclone uploads
- stream-aware throttling
- Arr ↔ media-server library parity
- Plex track preferences

Start with `docs/README.md`.

## How to work (mandatory)
The `agent-skills@addy-agent-skills` and `rust-skills@rust-skills` plugins are enabled and enforced for this repository (see the hooks in `.claude/settings.json`). Both must be installed for the user; the repository does not install them.

1. **Start every session** by invoking `agent-skills:using-agent-skills` via the Skill tool, before any other work.
2. **Before starting any task**, invoke the matching skill(s) from the tables below *before* reading code, planning, or editing. Load the skill; do not paraphrase it from memory.
3. **Follow the loaded skill's steps in order**, including its verification step. A task is not done until verification passes with evidence.
4. **Switch skills when the phase changes** (implementation → tests → review → commit). Several skills usually apply to one task.
5. **State which skill(s) are in use** when starting a task. If no skill fits, say so in one line, then proceed.

### Task → skill

| Situation | Skill |
|---|---|
| Ask is underspecified / unclear intent | `agent-skills:interview-me` |
| Rough idea needs refining | `agent-skills:idea-refine` |
| New project, feature, or significant change | `agent-skills:spec-driven-development` |
| No quality bar written down | `agent-skills:constraint-driven-development` |
| Have a spec, need tasks | `agent-skills:planning-and-task-breakdown` |
| Implementing code | `agent-skills:incremental-implementation` |
| Building or changing the web UI | `agent-skills:frontend-ui-engineering` |
| Checking the UI in a real browser | `agent-skills:browser-testing-with-devtools` |
| Designing APIs / module boundaries / traits | `agent-skills:api-and-interface-design` |
| Library/crate usage where correctness matters | `agent-skills:source-driven-development` |
| High stakes or unfamiliar code | `agent-skills:doubt-driven-development` |
| Writing or changing logic, fixing bugs | `agent-skills:test-driven-development` |
| Something broke (build, test, runtime) | `agent-skills:debugging-and-error-recovery` |
| Reviewing a change | `agent-skills:code-review-and-quality` |
| Code works but is too complex | `agent-skills:code-simplification` |
| Untrusted input, auth, secrets, dependencies | `agent-skills:security-and-hardening` |
| Performance concerns | `agent-skills:performance-optimization` |
| Committing, branching, versioning | `agent-skills:git-workflow-and-versioning` |
| CI/CD pipelines | `agent-skills:ci-cd-and-automation` |
| Logging, metrics, tracing | `agent-skills:observability-and-instrumentation` |
| Docs and ADRs | `agent-skills:documentation-and-adrs` |
| Removing or migrating systems | `agent-skills:deprecation-and-migration` |
| Preparing a release / launch | `agent-skills:shipping-and-launch` |
| Context/rules setup, degraded output | `agent-skills:context-engineering` |

### Rust task → rust-skills skill

The `rust-skills@rust-skills` plugin is enforced too (same hooks). It adds
Rust-specific guidance on top of the agent-skills workflow skill; it never
replaces one. Use these alongside the table above whenever Rust is written,
changed or reviewed:

| Situation | Skill |
|---|---|
| Unsure which, or a compile error | `rust-skills:rust-router` |
| Ownership, borrows, lifetimes | `rust-skills:m01-ownership` |
| Smart pointers, RAII, Drop | `rust-skills:m02-resource`, `rust-skills:m12-lifecycle` |
| Interior mutability, locks | `rust-skills:m03-mutability` |
| Generics, traits, dispatch | `rust-skills:m04-zero-cost` |
| Newtypes, builders, type state | `rust-skills:m05-type-driven` |
| Error types and propagation | `rust-skills:m06-error-handling`, `rust-skills:m13-domain-error` |
| Threads, async, tokio, signals | `rust-skills:m07-concurrency` |
| Domain modelling | `rust-skills:m09-domain` |
| Performance | `rust-skills:m10-performance` |
| Crates, features, workspace | `rust-skills:m11-ecosystem` |
| Review for anti-patterns | `rust-skills:m15-anti-pattern` |
| Naming and style | `rust-skills:coding-guidelines` |
| HTTP API, handlers, middleware | `rust-skills:domain-web` |
| The `autoplow` command line | `rust-skills:domain-cli` |
| Any `unsafe` or FFI | `rust-skills:unsafe-checker` |
| Crate API docs | `rust-skills:docs` |

`CONSTRAINTS.md` and this file win over a rust-skills suggestion that
conflicts with them (for example `#[allow]` stays forbidden). The plugin's
own prompt hook injects a "mandatory" routing and output format (a
"Reasoning Chain" section, a banner); it doesn't apply here: the
agent-skills workflow and the tables above decide which skills load and
how answers are written.

## Also mandatory
- **Surface assumptions** before non-trivial work. If unsure, stop and ask. Do not guess.
- **Specs before code:** `docs/specs/`. Tasks: `tasks/plan.md`, `tasks/todo.md`.
- **Record significant decisions as ADRs** in `docs/decisions/`. Never delete an ADR; supersede it.

## Quality bar (never weaken silently)
- **Read `CONSTRAINTS.md` before writing code. Do not weaken it to make a change pass.** Run `node scripts/floor-guard.mjs --base <ref>` before handing work back.
- The lint and CI policy in `docs/quality-policy.md` is enforced workspace-wide.
- **Fix the code, not the lint.** `#[allow]` is forbidden. A truly justified exception uses `#[expect(lint, reason = "...")]`, needs a row in the CONSTRAINTS.md Exceptions table, and must be called out in review.
- **Never** lower thresholds, delete or skip tests, or relax the toolchain pin or lints without an ADR.

## Fresh-context review of every change
A second pair of eyes catches what the author missed.
- **Before committing or handing back any change** (code, tests, scripts, specs, docs), run a review subagent on it: `agent-skills:code-reviewer` (correctness, readability, architecture, security, performance), and `agent-skills:security-auditor` as well when the change touches authentication, secrets, untrusted input or the rclone child. Run them in parallel with the repository's checks. The subagent is the fresh-context reviewer; use `agent-skills:code-review-and-quality` when you review yourself or weigh its findings.
- **Reviewers also check Microsoft's Pragmatic Rust Guidelines** (https://microsoft.github.io/rust-guidelines/agents/all.txt). A `SubagentStart` hook (`.claude/hooks/reviewer-guidelines.sh`) caches the text under `target/agent-guides/` and points the `agent-skills:code-reviewer` and `agent-skills:security-auditor` agents at it; it is not given to the authoring agent. Findings cite the guideline id (`M-...`). This file, `CONSTRAINTS.md`, `docs/quality-policy.md` and the specs win where they conflict.
- **Brief it with the range and the goal, not your conclusions.** Tell it to edit nothing and to report findings with file:line.
- **Act on every finding:** fix it (test-first when it changes behaviour, per `agent-skills:test-driven-development`), or record in the commit body why not. After fixing, re-run the checks, and review the fix again unless it is a mechanical change the finding spelled out.
- **Every commit carries a `Review:` line** in its body: which reviewers ran, on what diff (a commit range, or the working tree against a base), and what was fixed or declined with reasons. CI fails on a commit without it (`scripts/check-commit-messages.sh`; merge commits and commits made before the rule are exempt), so run `scripts/check-commit-messages.sh <base> HEAD` before handing work back. See [ADR-0023](docs/decisions/0023-fresh-context-review-of-every-change.md).
- A review is not optional for small or "obvious" changes; those are where unchecked assumptions hide.

## Public repository rules ([ADR-0015](docs/decisions/0015-public-documentation-rules.md))
- **Never commit environment-specific details:** hostnames, IPs, domains, user names, machine-specific paths, credential sources or files, tokens, raw test output, or session logs.
- **Verified third-party behaviour** goes in `docs/platform-notes/`, with software versions and the method used, and no environment details.
- **Research** about other projects describes behaviours and lessons, not bug lists.
- **Live tests** read endpoints and credentials from environment variables only.
- Run `scripts/check-public-docs.sh` before committing (CI runs it too).

## Running things
- **Resource limits:** cap heavy builds and every live test, for example `systemd-run --scope -p MemoryMax=... -p CPUQuota=...`. Run live tests against one server at a time.
- **Output:** keep it unbuffered so progress is visible.
- **Diagnosis:** when resources spike, measure (process list by memory, profiling) before attributing the cause.
