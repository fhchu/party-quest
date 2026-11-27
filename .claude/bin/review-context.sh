#!/usr/bin/env bash
# Prints what the reviewer subagent (.claude/agents/reviewer.md) reads
# before judging a branch, in one call: the commit under review, its log
# and diff against BASE (or against PREVIOUS, a re-review's earlier sha),
# and the rule files it reviews against, all read from WORKTREE.
#
#   review-context.sh WORKTREE BRANCH BASE [PREVIOUS]
set -eu

[ $# -eq 3 ] || [ $# -eq 4 ] || {
	echo "Usage: review-context.sh WORKTREE BRANCH BASE [PREVIOUS]" >&2
	exit 1
}
worktree="$1" branch="$2" base="$3" previous="${4:-}"
cd "$worktree"

# The rule files a review checks against, from the repo root.
rules=(CLAUDE.md .claude/rules/design.md .claude/rules/style.md .claude/rules/tests.md)

commit="$(git rev-parse "$branch")"
from="${previous:-$base}"
echo "== Reviewing $branch at $commit"
echo
echo "== Commits since $base"
git log --oneline "$base..$commit"
echo
echo "== Files changed since $from"
git diff --stat "$from...$commit"
for rule in "${rules[@]}"; do
	echo
	echo "== $rule"
	cat "$rule"
done
echo
echo "== git diff $from...$commit"
git diff "$from...$commit"
