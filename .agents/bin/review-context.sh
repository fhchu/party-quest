#!/usr/bin/env bash
# Prints what the reviewer subagent (.claude/agents/reviewer.md) reads
# before a first review of a branch, in one call: the commit under review,
# its log and diff against BASE, and the rule files it reviews against, all
# read from WORKTREE.
#
#   review-context.sh WORKTREE BRANCH BASE
set -eu

[ $# -eq 3 ] || {
	echo "Usage: review-context.sh WORKTREE BRANCH BASE" >&2
	exit 1
}
worktree="$1" branch="$2" base="$3"
cd "$worktree"

# The rule files a review checks against, from the repo root.
rules=(AGENTS.md .agents/rules/design.md .agents/rules/style.md .agents/rules/tests.md)

commit="$(git rev-parse "$branch")"
echo "== Reviewing $branch at $commit"
echo
echo "== Commits since $base"
git log --oneline "$base..$commit"
echo
echo "== Files changed since $base"
git diff --stat "$base...$commit"
for rule in "${rules[@]}"; do
	echo
	echo "== $rule"
	cat "$rule"
done
echo
echo "== git diff $base...$commit"
git diff "$base...$commit"
