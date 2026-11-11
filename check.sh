#!/usr/bin/env bash
# Runs every linter at once, then, if they all pass, every test suite at
# once. Run it after writing code. Exit code 0 means everything passed.
# A passing check prints one summary line; a failing one prints all its
# output.
#
# Needs: godot, go, golangci-lint, gdstyle, shellcheck, gitleaks (see the
# README).
# The backend's database tests need Docker running, or they skip.
#
# Also fails a branch that changes more than MAX_CHANGED_LINES lines against
# BASE (default origin/main; use the parent branch for a stacked branch).
# SIZE_OK=1 skips that check, for mechanical changes only. CI skips it too.
set -u
cd "$(dirname "$0")" || exit 1

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

names=()
summaries=()
pids=()

# start NAME SUMMARY DIR COMMAND...: runs COMMAND in DIR in the background.
# SUMMARY is a grep -E pattern for the output line to show when it passes.
# Output files are numbered, since names hold slashes.
start() {
	local name="$1" summary="$2" dir="$3"
	shift 3
	(cd "$dir" && "$@") > "$out/${#pids[@]}" 2>&1 &
	names+=("$name")
	summaries+=("$summary")
	pids+=("$!")
}

# Most lines (added plus deleted) a branch may change against BASE.
MAX_CHANGED_LINES=400

# Paths that don't count toward MAX_CHANGED_LINES. Pathspec globs: a * also
# matches across directories.
size_excludes=(
	# Reviewed as screenshots, not as text (see CLAUDE.md, UI).
	':(exclude)*.tscn'
	':(exclude)*.tres'
	# Written by Godot, not by hand.
	':(exclude)*.uid'
	':(exclude)*.import'
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

# check_size: fails when the branch, plus uncommitted work, changes more than
# MAX_CHANGED_LINES lines since it left BASE.
check_size() {
	local base="${BASE:-origin/main}" index changed
	# Stage everything, new files included, in a throwaway copy of the index,
	# so a check run before committing sees the whole change.
	index="$(mktemp)"
	cp "$(git rev-parse --git-path index)" "$index"
	GIT_INDEX_FILE="$index" git add -A
	changed="$(GIT_INDEX_FILE="$index" git diff --cached --numstat -M \
		"$(git merge-base "$base" HEAD)" -- . "${size_excludes[@]}" |
		awk '$1 != "-" { total += $1 + $2 } END { print total + 0 }')"
	rm -f "$index"
	echo "$changed changed lines against $base (limit $MAX_CHANGED_LINES)"
	if [ "$changed" -gt "$MAX_CHANGED_LINES" ]; then
		echo "Too big for one review. Split it along its seams into stacked"
		echo "branches (see CLAUDE.md). SIZE_OK=1 is only for mechanical changes."
		return 1
	fi
}

# summarize I: the last line of check I's output matching its pattern, with
# color codes removed.
summarize() {
	grep -E "${summaries[$1]}" "$out/$1" | tail -n 1 | sed $'s/\e\[[0-9;]*m//g'
}

# finish: waits for everything started, reports each, and returns 1 if any
# failed.
finish() {
	local failed=0 i
	for i in "${!pids[@]}"; do
		if wait "${pids[$i]}"; then
			printf 'ok    %s: %s\n' "${names[$i]}" "$(summarize "$i")"
		else
			failed=1
			printf 'FAIL  %s\n' "${names[$i]}"
			sed 's/^/      /' "$out/$i"
		fi
	done
	names=()
	summaries=()
	pids=()
	return "$failed"
}

echo "== lint"
start gdstyle "files checked" game gdstyle check --no-color --max-warnings 0 .
# golangci-lint refuses a second copy at once unless allowed to.
start golangci-lint/relay "issues" relay golangci-lint run --allow-parallel-runners ./...
start golangci-lint/server "issues" server golangci-lint run --allow-parallel-runners ./...
start golangci-lint/load-timeline "issues" game/tools/load_timeline \
	golangci-lint run --allow-parallel-runners ./...
# Silent when clean, so it says so itself.
start shellcheck "no issues" . sh -c \
	'shellcheck check.sh dev.sh game/run-tests.sh game/ui-gallery.sh deploy/*.sh && echo "no issues"'
# Secrets: every commit, then every file on disk, including ones not yet
# added to git.
start gitleaks "no leaks found" . sh -c \
	'gitleaks git --no-banner --no-color . && gitleaks dir --no-banner --no-color .'
if [ -n "${SIZE_OK:-}" ]; then
	echo "Size check skipped: SIZE_OK is set."
elif [ -z "${CI:-}" ]; then
	start size "changed lines" . check_size
fi
if ! finish; then
	echo "Lint failed; tests not run."
	exit 1
fi

echo "== test"
if ! docker info > /dev/null 2>&1; then
	echo "Docker isn't running: the backend's database tests will skip."
fi
start game "Overall Summary" game ./run-tests.sh
# go test prints a line per package; one line for all of them reads better.
start go-test/relay "all passed" relay sh -c 'go test ./... && echo "all passed"'
start go-test/server "all passed" server sh -c 'go test ./... && echo "all passed"'
start go-test/load-timeline "all passed" game/tools/load_timeline sh -c \
	'go test ./... && echo "all passed"'
if ! finish; then
	exit 1
fi

# After the tests, which import the project first.
echo "== measure"
start snapshot "full room" game godot --headless --path . -s res://tools/snapshot_size.gd
finish
