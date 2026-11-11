#!/usr/bin/env bash
# Injects the agent-skills and rust-skills enforcement rule into Claude's context.
# Usage: agent-skills-reminder.sh <SessionStart|UserPromptSubmit>
set -euo pipefail

event="${1:?hook event name required}"

if [ "$event" = "SessionStart" ]; then
  msg='MANDATORY (autoplow): The agent-skills and rust-skills plugins are enforced in this repo. Before any other work, invoke the Skill tool with agent-skills:using-agent-skills. Then, for every task, invoke the matching agent-skills:* skill(s) listed in CLAUDE.md BEFORE reading code, planning, or editing, follow their steps in order including verification, and state which skill(s) you are using. For any task that writes, changes or reviews Rust, also invoke the matching rust-skills:* skill(s) from the CLAUDE.md rust-skills table (rust-skills:rust-router when unsure which). If no skill fits, say so in one line. Global ~/.claude/CLAUDE.md rules take precedence over conflicting skill steps.'
else
  msg='autoplow: invoke the matching agent-skills:* skill first, plus the matching rust-skills:* skill when the task touches Rust (unless ones loaded this session still cover it), or say none fits.'
fi

jq -n --arg event "$event" --arg msg "$msg" \
  '{hookSpecificOutput: {hookEventName: $event, additionalContext: $msg}}'
