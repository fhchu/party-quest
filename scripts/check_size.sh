# shellcheck shell=bash
# The size check: how much a branch may change against its base. Sourced by
# scripts/check.sh, which runs each check from the folder its start line
# names.

# Most lines (added plus deleted) a branch may change against BASE.
MAX_CHANGED_LINES=400
# The branch the size check measures from.
BASE="${BASE:-origin/main}"

# Paths that don't count toward MAX_CHANGED_LINES. Pathspec globs: a * also
# matches across directories.
size_excludes=(
	# Reviewed as screenshots, not as text (see .agents/rules/ui.md).
	':(exclude)*.tscn'
	':(exclude)*.tres'
	# Written by Godot, not by hand.
	':(exclude)*.uid'
	':(exclude)*.import'
	':(exclude)*.gdbuild'
	# Third-party code, copied in.
	':(exclude)game/addons'
	# Written by go mod, not by hand.
	':(exclude)*go.sum'
	# Tests are easy to review next to the code they check.
	':(exclude)*_test.go'
	':(exclude)game/tests'
	# Binary files have no line count.
	':(exclude)*.png'
)

# whole_change_index: prints the path of a throwaway copy of the index with
# everything staged, new files included, so a check run before committing
# sees the whole change. The caller removes it. Fails, leaving nothing
# behind, when git can't stage the change.
whole_change_index() {
	local index
	index="$(mktemp)"
	if ! cp "$(git rev-parse --git-path index)" "$index" ||
		! GIT_INDEX_FILE="$index" git add -A; then
		rm -f "$index"
		return 1
	fi
	echo "$index"
}

# check_size: fails when the branch, plus uncommitted work, changes more than
# MAX_CHANGED_LINES lines since it left BASE.
check_size() {
	local index changed
	index="$(whole_change_index)" || return 1
	# Files deleted whole don't count (--diff-filter=d).
	changed="$(GIT_INDEX_FILE="$index" git diff --cached --numstat -M --diff-filter=d \
		"$(git merge-base "$BASE" HEAD)" -- . "${size_excludes[@]}" |
		awk '$1 != "-" { total += $1 + $2 } END { print total + 0 }')"
	rm -f "$index"
	echo "$changed changed lines against $BASE (limit $MAX_CHANGED_LINES)"
	if [ "$changed" -gt "$MAX_CHANGED_LINES" ]; then
		echo "Too big for one review. Split it along its seams into stacked"
		echo "branches (see .agents/rules/workflow.md). SIZE_OK=1 is only for mechanical changes."
		return 1
	fi
}
