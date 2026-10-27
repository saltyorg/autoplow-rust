#!/usr/bin/env bash
# Fails if any commit subject in BEFORE..AFTER is not a Conventional Commit.
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
status=0
while IFS= read -r line; do
  sha="${line%% *}"; subject="${line#* }"
  if [[ "$subject" =~ ^Merge\  ]]; then continue; fi
  if ! [[ "$subject" =~ $pattern ]]; then
    echo "Not a Conventional Commit: $sha $subject"
    status=1
  fi
done < <(git log --format='%h %s' "$range")
[[ $status -eq 0 ]] && echo "check-commit-messages: OK"
exit $status
