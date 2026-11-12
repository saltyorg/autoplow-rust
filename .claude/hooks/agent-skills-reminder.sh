#!/usr/bin/env bash
# SessionStart hook: injects the agent-skills rule into Claude's context
# once a session. There is no reminder on every prompt: a skill is loaded
# when the phase of the work changes (ADR-0024).
set -euo pipefail

msg='autoplow: the agent-skills plugin is enabled for this repository. Start the session by invoking the Skill tool with agent-skills:using-agent-skills. After that, load the matching agent-skills:* skill from the CLAUDE.md table when the phase of the work changes (spec, plan, implementation, tests, debugging, review, commit, release). A skill loaded earlier in the session still covers its phase; say which skills are in use when a phase starts, or that none fits. Global ~/.claude/CLAUDE.md rules take precedence over conflicting skill steps.'

jq -n --arg msg "$msg" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $msg}}'
