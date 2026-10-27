# ADR-0015: What documentation belongs in the public repository

## Status
Accepted

## Date
2026-10-27

## Context
The repository is public. Early research and testing ran in a private environment and produced session logs, raw test output and environment details: hostnames, IPs, paths, credential sources. Those must not be published, but the knowledge they produced must survive for future contributors and agents.

## Decision
**Public (`docs/`):**
- `architecture.md`
- `specs/`
- `decisions/` (ADRs)
- `research/` (external projects and APIs, written neutrally)
- `platform-notes/` (verified third-party behaviour, with versions and method)
- `quality-policy.md`

**Never public:**
- environment details (hosts, IPs, domains, user names, machine-specific paths, credential sources)
- raw test output
- session logs and spike code

Those are kept in private working notes outside the repository.

**Writing rules:**
- **Test knowledge** is recorded as versioned platform notes, not as test reports.
- **Research** about other projects describes behaviours and lessons, not bug lists.

**Enforcement:** `scripts/check-public-docs.sh` (a denylist) runs locally and in CI. `CLAUDE.md` states the rule for agents.

## Alternatives Considered
- **Publish everything:** leaks environment details and confuses readers with superseded history.
- **Publish only specs:** loses why decisions were made and what was verified.

## Consequences
- **Superseded decisions** remain as ADRs, so the history is public without the session narrative.
- **Live tests** read endpoints and credentials from environment variables, never from files in the repo.
