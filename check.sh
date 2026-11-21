#!/usr/bin/env bash
# Runs every linter at once, then, if they all pass, every test suite at
# once. Run it after writing code. Exit code 0 means everything passed.
# A passing check prints one summary line; a failing one prints all its
# output.
#
# Needs: godot, go, golangci-lint, gdstyle, shellcheck, gitleaks (see the
# README).
#
# Also fails a branch that changes more than MAX_CHANGED_LINES lines against
# BASE (default origin/main; use the parent branch for a stacked branch).
# SIZE_OK=1 skips that check, for mechanical changes only. CI skips it too.
set -u
cd "$(dirname "$0")" || exit 1

out="$(mktemp -d)"
# override.cfg too, in case the warnings check was cut short: the editor
# would read it.
trap 'rm -rf "$out" game/override.cfg' EXIT

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
	# Reviewed as screenshots, not as text (see agents/ui.md).
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
		echo "branches (see agents/design.md). SIZE_OK=1 is only for mechanical changes."
		return 1
	fi
}

# check_export: exports the web build's pack and checks it kept every data
# file's values, since the export rewrites them. Run from game/.
check_export() {
	godot --headless --path . --export-pack Web "$out/game.pck" > /dev/null 2>&1 &&
		godot --headless --path . -s res://tools/export_check.gd -- "$out/game.pck"
}

# check_warnings: loads every game script with each GDScript warning the
# editor shows raised to an error, and fails on any. Run from game/.
check_warnings() {
	local log="$out/warnings.log"
	# A fresh checkout has no import cache, so the addons' global classes
	# (GdUnitTestSuite) aren't known until it's built.
	godot --headless --path . --import > /dev/null 2>&1
	godot --headless --path . -s res://tools/warnings_check.gd -- --raise > /dev/null 2>&1
	godot --headless --path . -s res://tools/warnings_check.gd > "$log" 2>&1
	rm -f override.cfg
	if grep -A1 "SCRIPT ERROR" "$log"; then
		return 1
	fi
	grep "scripts loaded" "$log"
}

# check_private_members: fails on a test that uses another object's
# underscore member, unless game/tests/private_members.txt lists it, and on
# a listed one no longer used. Run from game/.
check_private_members() {
	local list=tests/private_members.txt found
	found="$(grep -rnoE --include='*.gd' '[A-Za-z0-9_)]\._[a-z][a-z0-9_]*' tests |
		while IFS=: read -r path line match; do
			member="_${match##*._}"
			if ! grep -qxE "(\*|$path) $member" "$list"; then
				echo "$path:$line uses $member"
			fi
		done
		# Lines for a single test whose member it no longer uses.
		grep -E '^tests/' "$list" | while read -r path member; do
			if ! grep -qE "[A-Za-z0-9_)]\.$member\b" "$path" 2> /dev/null; then
				echo "$list lists $path $member, which it no longer uses: remove the line"
			fi
		done)"
	if [ -n "$found" ]; then
		echo "$found"
		echo "Use public methods (agents/tests.md), or list it in $list with the owner's OK."
		return 1
	fi
	echo "no unlisted private members"
}

# check_banned_word: fails on any form of the word agents/design.md bans
# (Principles: "Never ... in any form"), in tracked files and new ones not
# yet added. A line holding the marker allow-stand is skipped; only the rule
# itself and this pattern need it.
check_banned_word() {
	local found
	found="$(git grep --untracked -nIiwE 'stand|stands|standing|stood' | grep -v allow-stand)" # allow-stand
	if [ -n "$found" ]; then
		echo "$found"
		echo "Say which meaning instead (agents/design.md, Principles)."
		return 1
	fi
	echo "no banned word"
}

# Limits in different files and languages that must stay in order. Each is
# read as text, so a rewritten line fails here with "can't find" rather
# than passing.
# How many heartbeats the backend-silent alert's window must span, so one
# late heartbeat doesn't raise it. Untuned.
MIN_HEARTBEATS_PER_SILENCE=2
# Time a release needs besides waiting for CI: v0.2.0's image job took
# under 8 minutes with the web template built from scratch.
RELEASE_BUILD_MIN=8

# grab FILE PATTERN: prints the first number in the first line of FILE
# matching the grep -E PATTERN, or fails naming what it couldn't find.
grab() {
	local line
	line="$(grep -m 1 -E "$2" "$1")" || { echo "can't find /$2/ in $1"; return 1; }
	grep -oE '[0-9]+' <<<"$line" | head -n 1
}

# check_limits: the backend's heartbeat against the silence alert, its own
# health check timeout against Docker's, and CI's job limit against the
# release gate's wait against the release job's limit.
check_limits() {
	local heartbeat silence probe docker ci wait release
	heartbeat="$(grab server/cmd/api/health.go 'heartbeatInterval += [0-9]+ \* time\.Minute')" || { echo "$heartbeat"; return 1; }
	silence="$(grab deploy/grafana/alerts.json 'absent_over_time\(.*\[[0-9]+m\]')" || { echo "$silence"; return 1; }
	probe="$(grab server/cmd/api/health.go 'healthcheckTimeout += [0-9]+ \* time\.Second')" || { echo "$probe"; return 1; }
	docker="$(grab deploy/compose.yaml '^ +timeout: [0-9]+s')" || { echo "$docker"; return 1; }
	ci="$(grab .github/workflows/check.yml '^ +timeout-minutes: [0-9]+')" || { echo "$ci"; return 1; }
	wait="$(grab .github/wait-for-check.sh '^WAIT_SEC=[0-9]+')" || { echo "$wait"; return 1; }
	# The image job's limit: the first in release.yml.
	release="$(grab .github/workflows/release.yml '^ +timeout-minutes: [0-9]+')" || { echo "$release"; return 1; }
	local failed=0
	if [ "$silence" -lt $((MIN_HEARTBEATS_PER_SILENCE * heartbeat)) ]; then
		echo "the backend-silent alert's ${silence}m window spans fewer than $MIN_HEARTBEATS_PER_SILENCE ${heartbeat}m heartbeats"
		failed=1
	fi
	if [ "$docker" -le "$probe" ]; then
		echo "Docker's ${docker}s health check timeout isn't above the backend's own ${probe}s"
		failed=1
	fi
	if [ "$wait" -le $((ci * 60)) ]; then
		echo "the release gate's ${wait}s wait isn't above CI's ${ci}-minute job limit"
		failed=1
	fi
	if [ $((release * 60)) -lt $((wait + RELEASE_BUILD_MIN * 60)) ]; then
		echo "the release job's ${release}-minute limit doesn't cover the ${wait}s wait plus a ${RELEASE_BUILD_MIN}-minute build"
		failed=1
	fi
	[ "$failed" = 0 ] && echo "limits in order"
}

# summarize I: the last line of check I's output matching its pattern, with
# color codes removed.
summarize() {
	grep -E "${summaries[$1]}" "$out/$1" | tail -n 1 | sed $'s/\e\[[0-9;]*m//g'
}

# finish: waits for everything started, reports each, and returns 1 if any
# failed.
# What Godot prints at exit for objects or resources nothing freed. A step
# that prints either fails, even if it passed otherwise.
LEAKED='ObjectDB instances were leaked|resources still in use at exit'

finish() {
	local failed=0 i
	for i in "${!pids[@]}"; do
		if wait "${pids[$i]}" && ! grep -qE "$LEAKED" "$out/$i"; then
			printf 'ok    %s: %s\n' "${names[$i]}" "$(summarize "$i")"
		else
			failed=1
			printf 'FAIL  %s\n' "${names[$i]}"
			sed 's/^/      /' "$out/$i"
			grep -qE "$LEAKED" "$out/$i" &&
				printf '      Leaked at exit: rerun the step with --verbose to see what.\n'
		fi
	done
	names=()
	summaries=()
	pids=()
	return "$failed"
}

echo "== lint"
start gdstyle "files checked" game gdstyle check --no-color --max-warnings 0 .
start godot-warnings "scripts loaded" game check_warnings
# golangci-lint refuses a second copy at once unless allowed to.
start golangci-lint/relay "issues" relay golangci-lint run --allow-parallel-runners ./...
start golangci-lint/server "issues" server golangci-lint run --allow-parallel-runners ./...
# Silent when clean, so it says so itself.
start shellcheck "no issues" . sh -c \
	'shellcheck check.sh dev.sh game/run-tests.sh game/ui-gallery.sh deploy/*.sh deploy/grafana/*.sh deploy/web-template/*.sh .github/*.sh && echo "no issues"'
# Secrets: every commit, then every file on disk, including ones not yet
# added to git.
start gitleaks "no leaks found" . sh -c \
	'gitleaks git --no-banner --no-color . && gitleaks dir --no-banner --no-color .'
# A word too ambiguous to use, in any form (agents/design.md).
start banned-word "no banned word" . check_banned_word

start limits "limits in order" . check_limits
# Tests use only public members, or ones the owner listed.
start private-members "private members" game check_private_members
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
start game "Overall Summary" game ./run-tests.sh
# go test prints a line per package; one line for all of them reads better.
start go-test/relay "all passed" relay sh -c 'go test ./... && echo "all passed"'
start go-test/server "all passed" server sh -c 'go test ./... && echo "all passed"'
if ! finish; then
	exit 1
fi

# After the tests, which import the project first.
echo "== measure"
start snapshot "full lobby" game godot --headless --path . -s res://tools/snapshot_size.gd
start export "data files" game check_export
finish
