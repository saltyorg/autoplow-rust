#!/usr/bin/env bash
# Fails if any commit subject in BEFORE..AFTER is not a Conventional Commit.
# It also fails a commit that breaks the other commit message rule:
# - every commit has a "Review:" line in its body saying which review
#   subagents ran and what came of their findings (CLAUDE.md, "Fresh-context
#   review of every change"). This applies to commits made after the one
#   that introduced the rule: a commit whose parent's copy of this script
#   doesn't mention it is exempt, and so are merge commits.
# With no usable BEFORE (first push), checks every commit reachable from AFTER.
set -euo pipefail
before="${1:-}"
after="${2:-HEAD}"
if [[ -z "$before" || "$before" =~ ^0+$ ]] || ! git cat-file -e "$before^{commit}" 2>/dev/null; then
  range="$after"
else
  range="$before..$after"
fi
pattern='^(feat|fix|docs|chore|refactor|test|ci|build|perf|style|revert)(\([a-z0-9-]+\))?!?: [^ ].{0,99}$'
script=scripts/check-commit-messages.sh
status=0
while IFS= read -r line; do
  sha="${line%% *}"; subject="${line#* }"
  if [[ "$subject" =~ ^Merge\  ]]; then continue; fi
  if ! [[ "$subject" =~ $pattern ]]; then
    echo "Not a Conventional Commit: $sha $subject"
    status=1
  fi
  # Read git's output first: under pipefail, `git ... | grep -q` can fail
  # when grep stops reading early and misjudge the commit.
  parent_script=$(git show "$sha^:$script" 2>/dev/null || true)
  body=$(git log -1 --format=%b "$sha")
  if grep -q 'Review:' <<<"$parent_script" \
    && ! grep -qE '^Review: .+' <<<"$body"; then
    echo "Missing 'Review:' line: $sha $subject"
    status=1
  fi
done < <(git log --format='%h %s' "$range")
[[ $status -eq 0 ]] && echo "check-commit-messages: OK"
exit $status
