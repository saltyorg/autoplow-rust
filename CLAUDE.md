# Autoplow: agent instructions

Autoplow is a Rust daemon for Saltbox that combines:
- media-server scan triggers
- per-file rclone uploads
- stream-aware throttling
- Arr ↔ media-server library parity
- Plex track preferences

Start with `docs/README.md`.

## How to work (mandatory)
- **Use the agent-skills plugin for every task in this repository.** Before starting, invoke the skill that matches the phase. If unsure, start with `agent-skills:using-agent-skills`. Follow each skill's steps, including its verification.
- **Surface assumptions** before non-trivial work. If unsure, stop and ask. Do not guess.
- **Specs before code:** `docs/specs/`. Tasks: `tasks/plan.md`, `tasks/todo.md`.
- **Record significant decisions as ADRs** in `docs/decisions/`. Never delete an ADR; supersede it.

## Quality bar (never weaken silently)
- **Read `CONSTRAINTS.md` before writing code. Do not weaken it to make a change pass.** Run `node scripts/floor-guard.mjs --base <ref>` before handing work back.
- The lint and CI policy in `docs/quality-policy.md` is enforced workspace-wide.
- **Fix the code, not the lint.** `#[allow]` is forbidden. A truly justified exception uses `#[expect(lint, reason = "...")]`, needs a row in the CONSTRAINTS.md Exceptions table, and must be called out in review.
- **Never** lower thresholds, delete or skip tests, or relax the toolchain pin or lints without an ADR.

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
