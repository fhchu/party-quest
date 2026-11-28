#!/usr/bin/env bash
# Makes and removes a task's worktree under .claude/worktrees/, as
# .agents/rules/workflow.md asks. Run from any checkout of the repo.
#
#   worktree.sh new BRANCH [BASE]
#     Fetches origin, then checks BRANCH out in .claude/worktrees/BRANCH: the
#     local branch if there is one, else origin's (tracking it), else a new
#     branch from BASE (default origin/main; the parent branch for a stacked
#     one). Copies in the gitignored files .worktreeinclude lists. Prints the
#     worktree's path.
#
#   worktree.sh done BRANCH
#     Removes BRANCH's worktree if nothing in it is uncommitted and every
#     commit on BRANCH is on origin; otherwise says what's left and removes
#     nothing. The branch stays.
#
#   worktree.sh include
#     Copies in the gitignored files .worktreeinclude lists when the current
#     checkout is a worktree that has none of them yet. Antigravity's
#     SessionStart hook (.agents/hooks.json) runs it, since Antigravity
#     doesn't read .worktreeinclude for the worktrees it makes.
set -eu

die() {
	echo "$1" >&2
	exit 1
}

# The main checkout: the folder holding the repo's shared git dir.
main="$(cd "$(git rev-parse --git-common-dir)/.." && pwd)"

# included_patterns: the paths .worktreeinclude lists, from the repo root.
included_patterns() {
	while read -r line; do
		case "$line" in "" | "#"*) continue ;; esac
		echo "${line#/}"
	done < "$main/.worktreeinclude"
}

# copy_included DEST: copies the gitignored files .worktreeinclude lists from
# the main checkout into DEST.
copy_included() {
	local patterns=()
	while read -r line; do patterns+=("$line"); done < <(included_patterns)
	[ "${#patterns[@]}" -gt 0 ] || return 0
	(cd "$main" && git ls-files -z --others --ignored --exclude-standard -- "${patterns[@]}") |
		(cd "$main" && xargs -0 tar cf -) | (cd "$1" && tar xf -)
}

include() {
	local top patterns=()
	top="$(git rev-parse --show-toplevel)"
	[ "$top" != "$main" ] || return 0
	while read -r line; do patterns+=("$line"); done < <(included_patterns)
	[ "${#patterns[@]}" -gt 0 ] || return 0
	[ -z "$(cd "$top" && git ls-files --others --ignored --exclude-standard -- "${patterns[@]}")" ] || return 0
	copy_included "$top"
}

new() {
	local branch="$1" base="${2:-origin/main}" path
	path="$main/.claude/worktrees/$branch"
	[ ! -e "$path" ] || die "$path already exists."
	git -C "$main" fetch -q origin
	if git -C "$main" show-ref -q --verify "refs/heads/$branch"; then
		git -C "$main" worktree add -q "$path" "$branch"
	elif git -C "$main" show-ref -q --verify "refs/remotes/origin/$branch"; then
		git -C "$main" worktree add -q --track -b "$branch" "$path" "origin/$branch"
	else
		git -C "$main" worktree add -q --no-track -b "$branch" "$path" "$base"
	fi
	copy_included "$path"
	echo "$path"
}

done_with() {
	local branch="$1" path dirty unpushed
	path="$(git -C "$main" worktree list --porcelain |
		awk -v ref="branch refs/heads/$branch" '/^worktree / { p = $0; sub(/^worktree /, "", p) } $0 == ref { print p }')"
	[ -n "$path" ] || die "No worktree has $branch checked out."
	dirty="$(git -C "$path" status --porcelain)"
	[ -z "$dirty" ] || die "Not removed: $path has uncommitted changes:
$dirty"
	git -C "$main" fetch -q origin
	git -C "$main" show-ref -q --verify "refs/remotes/origin/$branch" ||
		die "Not removed: $branch isn't on origin. Push it first."
	unpushed="$(git -C "$main" log --oneline "origin/$branch..$branch")"
	[ -z "$unpushed" ] || die "Not removed: commits on $branch aren't on origin:
$unpushed"
	git -C "$main" worktree remove "$path"
	echo "Removed $path; $branch stays."
}

case "${1:-}" in
new) [ $# -ge 2 ] || die "Usage: worktree.sh new BRANCH [BASE]"; new "$2" "${3:-}" ;;
done) [ $# -eq 2 ] || die "Usage: worktree.sh done BRANCH"; done_with "$2" ;;
include) [ $# -eq 1 ] || die "Usage: worktree.sh include"; include ;;
*) die "Usage: worktree.sh new BRANCH [BASE] | done BRANCH | include" ;;
esac
