#!/usr/bin/env bash
# Fails if any commit subject in BEFORE..AFTER is not a Conventional Commit.
# It also fails a commit that breaks the other commit message rule:
# - every commit that changes anything but documents has a "Review:" line in
#   its body saying which review subagents ran and what came of their
#   findings (CLAUDE.md, "Fresh-context review, by tier"; ADR-0024).
#   Documents are the files under docs/ and tasks/ at the top of the
#   repository, except docs/quality-policy.md, which is part of the gate. A
#   commit of documents only needs no line: those are read at the plan's
#   checkpoints. A commit that changes no file needs one. This applies to
#   commits made after the one that introduced the rule: a commit whose
#   parent's copy of this script doesn't mention it is exempt, and so are
#   merge commits.
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
  # One path per line. --no-renames lists a moved file under both names, so
  # a file moved into docs/ still counts as a change outside it. With no
  # file at all the here-string is one empty line, which is not a document.
  files=$(git diff-tree --no-commit-id --name-only -r --no-renames "$sha")
  if grep -q 'Review:' <<<"$parent_script" \
    && { grep -qvE '^(docs|tasks)/' <<<"$files" \
      || grep -qxF 'docs/quality-policy.md' <<<"$files"; } \
    && ! grep -qE '^Review: .+' <<<"$body"; then
    echo "Missing 'Review:' line (the commit changes more than documents under docs/ and tasks/): $sha $subject"
    status=1
  fi
done < <(git log --format='%h %s' "$range")
[[ $status -eq 0 ]] && echo "check-commit-messages: OK"
exit $status
