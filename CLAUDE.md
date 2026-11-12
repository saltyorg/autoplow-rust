# Autoplow: agent instructions

Autoplow is a Rust daemon for Saltbox that combines:
- media-server scan triggers
- per-file rclone uploads
- stream-aware throttling
- Arr ↔ media-server library parity
- Plex track preferences

Start with `docs/README.md`.

## How to work (mandatory)
The `agent-skills@addy-agent-skills` plugin is enabled for this repository (see the hooks in `.claude/settings.json`). It must be installed for the user; the repository does not install it. The rust-skills plugin is switched off here ([ADR-0024](docs/decisions/0024-reviews-by-tier-and-lighter-process.md)); Rust questions go to the standard library's and each crate's own documentation (`agent-skills:source-driven-development`).

1. **Start every session** by invoking `agent-skills:using-agent-skills` via the Skill tool, before any other work.
2. **When the phase of the work changes** (spec → plan → implementation → tests → debugging → review → commit → release), invoke the matching skill(s) from the table below. Load the skill; do not paraphrase it from memory. A skill loaded earlier in the session still covers its phase: don't load it again for the next task of the same kind.
3. **Follow the loaded skill's steps in order**, including its verification step. A task is not done until verification passes with evidence.
4. **State which skill(s) are in use** when a phase starts. If no skill fits, say so in one line, then proceed.
5. **Keep the process in proportion.** Time goes to Autoplow's specs, code and tests. Work on the gate (the checks, the hooks, these instructions) or on records of the process needs a defect that affects Autoplow or a request from the maintainer.

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

## Also mandatory
- **Surface assumptions** before non-trivial work. If unsure, stop and ask. Do not guess.
- **Specs before code:** `docs/specs/`. Tasks: `tasks/plan.md`, `tasks/todo.md`.
- **Record significant decisions as ADRs** in `docs/decisions/`. Never delete an ADR; supersede it.

## Quality bar (never weaken silently)
- **Read `CONSTRAINTS.md` before writing code. Do not weaken it to make a change pass.** Run `node scripts/floor-guard.mjs --base <ref>` before handing work back.
- The lint and CI policy in `docs/quality-policy.md` is enforced workspace-wide.
- **Fix the code, not the lint.** `#[allow]` is forbidden. A truly justified exception uses `#[expect(lint, reason = "...")]`, needs a row in the CONSTRAINTS.md Exceptions table, and must be called out in review.
- **Never** lower thresholds, delete or skip tests, or relax the toolchain pin or lints without an ADR.

## Fresh-context review, by tier
A second pair of eyes catches what the author missed. The review is sized to the change ([ADR-0024](docs/decisions/0024-reviews-by-tier-and-lighter-process.md), which amends [ADR-0023](docs/decisions/0023-fresh-context-review-of-every-change.md)):

| What the change touches | Review |
|---|---|
| Only documents: files under `docs/` and `tasks/`, except `docs/quality-policy.md` | None for the commit. They are read at the plan's next checkpoint, or by the maintainer when a spec or ADR is approved. No `Review:` line. |
| Anything else: Rust and UI code, tests, the gate (`CLAUDE.md`, `CONSTRAINTS.md`, `docs/quality-policy.md`, `scripts/`, `.claude/`, `.github/`, `clippy.toml`, `deny.toml`, `rust-toolchain.toml`, manifests), files at the repository root | One `agent-skills:code-reviewer` run for the task, on its whole diff, in parallel with the repository's checks. |
| Authentication, secrets, untrusted input or the rclone child | `agent-skills:security-auditor` as well, when the task's spec or plan asks for it. |

- **One pass, one model.** A second pass on another model is for a checkpoint or the maintainer's request. Use `agent-skills:code-review-and-quality` when you review yourself or weigh the findings.
- **Reviewers also check Microsoft's Pragmatic Rust Guidelines** (https://microsoft.github.io/rust-guidelines/agents/all.txt). A `SubagentStart` hook (`.claude/hooks/reviewer-guidelines.sh`) caches the text under `target/agent-guides/` and points the `agent-skills:code-reviewer` and `agent-skills:security-auditor` agents at it; it is not given to the authoring agent. Findings cite the guideline id (`M-...`). This file, `CONSTRAINTS.md`, `docs/quality-policy.md` and the specs win where they conflict.
- **Brief it with the range and the goal, not your conclusions.** Tell it to edit nothing and to report findings with file:line.
- **Weigh every finding against how Autoplow runs on a Saltbox host.** Fix the ones that can happen in real use (test-first when it changes behaviour, per `agent-skills:test-driven-development`); decline the rest in the commit body with the reason. A finding doesn't become a plan of its own.
- **After fixing, re-run the checks.** Review the fix again only when it changes behaviour beyond what the finding spelled out.
- **A commit that changes anything but documents carries a `Review:` line** in its body: which reviewers ran, on what diff (a commit range, or the working tree against a base), and what was fixed or declined with reasons. Keep it to a few lines. CI fails on such a commit without it (`scripts/check-commit-messages.sh`; merge commits and commits made before the rule are exempt), so run `scripts/check-commit-messages.sh <base> HEAD` before handing work back.

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
