# ADR-0024: Reviews by tier, skills at phase changes, rust-skills off

## Status
Accepted. Amends [ADR-0023](0023-fresh-context-review-of-every-change.md): its review of every change, its `Review:` line in every commit, its reminder on each prompt and its reliance on two plugins are replaced by the rules below. Its reviewer agents, the `Review:` line for everything but documents, and the Pragmatic Rust Guidelines hook stand.

## Date
2026-11-12

## Context
ADR-0023 took three rules from a sibling project: a fresh-context review of every change, a `Review:` line in every commit, and reminders at session start and on each prompt to load the matching skills. The rust-skills plugin was enabled beside agent-skills, with a table of its skills in `CLAUDE.md`.

The sibling project has since measured what those rules cost and made them lighter:
- About 300 reviewer runs over 294 commits, a third of them on commits that changed no Rust. Each round produced findings, the findings became commits, and those commits needed rounds of their own.
- Its rust-skills skills were used 3 times, while the plugin's own prompt hook put about a hundred lines of routing text into the context of most prompts. Claude Code can't turn off one hook of an enabled plugin (https://code.claude.com/docs/en/hooks.md).
- Skills were loaded far less often than a rule asking for one before every task implies, with a reminder on every prompt.

This repository is further along the same road: it holds specs, ADRs and plans and no Rust yet, so nearly every commit so far is documents only, and each has needed a reviewer run since ADR-0023. The maintainer asked for the sibling project's changes here.

## Decision
### 1. Reviews by tier
| What the change touches | Review |
|---|---|
| Only documents: files under `docs/` and `tasks/` (specs, ADRs, research, platform notes, plans), except `docs/quality-policy.md` | None for the commit. The documents are read at the plan's next checkpoint, or by the maintainer when a spec or ADR is approved. No `Review:` line is needed. |
| Anything else: Rust and UI code, tests, the gate (`CLAUDE.md`, `CONSTRAINTS.md`, `docs/quality-policy.md`, `scripts/`, `.claude/`, `.github/`, `clippy.toml`, `deny.toml`, `rust-toolchain.toml`, manifests), files at the repository root | One `agent-skills:code-reviewer` run for the task, on the task's whole diff. A `Review:` line. |
| Authentication, secrets, untrusted input or the rclone child | `agent-skills:security-auditor` as well, when the task's spec or plan asks for it. |

- **One pass, on one model.** A second pass on another model is for a checkpoint, or when the maintainer asks.
- **A fix is reviewed again only when it changes behaviour beyond what the finding spelled out.** Otherwise the checks and the fix's test are its check.
- **Findings are weighed against how Autoplow runs on a Saltbox host** before they become work. A finding that can't happen in real use is declined in the commit body, with the reason.
- **`scripts/check-commit-messages.sh` asks for the `Review:` line only on a commit that changes something other than a document.** Documents are judged by path, at the top of the repository: `docs-extra/`, a `docs/` directory inside a crate and a Markdown file elsewhere are not documents. A commit that changes no file needs the line.

### 2. Skills when the phase changes
A skill is loaded when the phase of the work changes (spec, plan, implementation, tests, debugging, review, commit, release), and a skill loaded earlier in the session covers its phase. The reminder at session start stays; the reminder on each prompt is removed. `CLAUDE.md` also asks that the process be kept in proportion: work on the gate or on records of the process needs a defect that affects Autoplow or a request from the maintainer.

### 3. The rust-skills plugin is switched off
`.claude/settings.json` sets `"rust-skills@rust-skills": false`, which also overrides a contributor's user-level setting for this repository (a local settings file can still switch it on). The table of its skills in `CLAUDE.md` and the hook's mention of it are removed. Rust questions go to the standard library's and each crate's documentation (`agent-skills:source-driven-development`), and the reviewers keep Microsoft's Pragmatic Rust Guidelines.

### Unchanged
- The `Gate-Change:` trailer, the floor guard and every threshold in `CONSTRAINTS.md`.
- The reviewer guidelines hook.
- The human review at each phase checkpoint in `tasks/plan.md`.

## Alternatives Considered
### Keep a review for every commit, on a cheaper model
- **Pros:** nothing goes unread when it lands.
- **Cons:** the cost was the rounds, not the price of one run, and a cheaper model produces more of the findings that don't matter in use.
- **Rejected.**

### Review only at checkpoints
- **Pros:** the fewest runs.
- **Cons:** a defect in a task's code is built on for the rest of the phase.
- **Rejected for code and the gate; chosen for documents.**

### Count every Markdown file as a document
- **Cons:** `CONSTRAINTS.md`, `CLAUDE.md` and `docs/quality-policy.md` are the bar itself.
- **Rejected:** two directories by path, with the one gate file inside them named as an exception.

### Keep rust-skills, or copy a few of its skills into the repository
- **Cons:** the injected text on every prompt for skills that were hardly used; copies stop following upstream.
- **Rejected:** a skill that is missed can be copied in later, and a session that wants the plugin can switch it on locally.

## Consequences
- This loosens a rule in `CONSTRAINTS.md` (the Commit messages row), which is why it is an ADR. No threshold changes.
- A document-only commit costs the public-docs, link and commit-message checks and no reviewer. A wrong statement in a spec or plan can stand until the checkpoint; the code written from it is still reviewed, and the maintainer approves specs and ADRs.
- A fix made after a review is trusted to its test and the checks.
- Until Rust implementation starts, most commits here need no `Review:` line. This ADR's own commit changes gate files, so it carries one, and a `Gate-Change:` trailer for the lines the floor guard reports.
- `tasks/todo.md` names the security auditor for no task yet. Tasks that handle authentication, secrets, untrusted input or the rclone child need it written into the plan to get that review.
- No injected routing text from rust-skills, and its MCP server no longer starts for this repository.
- Bot commits (ADR-0023, Consequences) are still undecided; one that changes a file outside the documents would fail the check.
