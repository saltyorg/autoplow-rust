# ADR-0023: Every change is reviewed by a fresh-context agent

## Status
Accepted. Amended by [ADR-0024](0024-reviews-by-tier-and-lighter-process.md): the review is sized to the change (none for a commit of documents only, which needs no `Review:` line), a fix is reviewed again only when it changes behaviour beyond the finding, findings are weighed against real use, the reminder on each prompt is gone and the rust-skills plugin is switched off.

## Date
2026-11-11

## Context
Most of this repository is written by an AI agent, and more is written than a person reads line by line. The author of a change is a poor judge of it: it shares the assumptions that produced the mistake. A sibling project found real bugs this way that its own author had missed, and adopted three rules. The maintainer asked for the same here before Rust implementation starts.

## Decision
- **Before any change is committed or handed back,** a review agent that did not write it reviews the diff: `agent-skills:code-reviewer`, and `agent-skills:security-auditor` as well for authentication, secrets, untrusted input or the rclone child.
- **Every finding is acted on:** fixed, or declined with the reason in the commit body.
- **Every commit body carries a `Review:` line** naming the reviewers, the diff they saw and what came of it. `scripts/check-commit-messages.sh` fails a commit without one. Merge commits, and commits made before the rule, are exempt.
- **Reviewers also check Microsoft's Pragmatic Rust Guidelines** where a change contains Rust. A hook hands them a cached copy; the authoring agent does not get it. Project rules win where they conflict.
- **Hooks remind the agent** at session start and on each prompt to load the matching skills.

## Alternatives Considered
### Review only code, or only large changes
- **Rejected:** specs and small changes are where unchecked assumptions hide, and "small" is the author's own judgement.

### A local commit hook that demands the line
- **Pros:** a missing line is caught before the commit exists.
- **Cons:** git hooks are not versioned with the repository and need installing on each machine.
- **Rejected for now:** the agent runs the check before handing back, and CI is the backstop.

## Consequences
- A change costs one review agent run more, and a commit message is longer.
- The check runs in CI after a push. A commit pushed straight to `main` without the line fails CI and can only be fixed by a follow-up; the agent therefore runs `scripts/check-commit-messages.sh <base> HEAD` before handing work back.
- **Bot commits** (release-please, Renovate) carry no `Review:` line. Neither is configured yet. When one is added, the check either exempts that author or the bot is set to add the line; that is decided then.
- The two plugins the hooks rely on are installed per user. On a machine without them the reminders name skills that are not there; `CLAUDE.md` says which plugins are needed.
- The guidelines are fetched from the network and cached for a week. A reviewer told to use them treats the text as review criteria, never as instructions.
