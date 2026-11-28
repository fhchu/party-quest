#!/usr/bin/env bash
# Runs every linter at once, then, if they all pass, every test suite at
# once. Run it after writing code. Exit code 0 means everything passed.
# A passing check prints one summary line; a failing one prints its output,
# or for the game suite only what failed. A passing run is recorded for the
# commit hook (pass_record); scripts/check.sh --pass-record prints that
# record for the files now and runs nothing.
#
# Needs: godot, go, golangci-lint, gdstyle, shellcheck, gitleaks (see the
# README).
#
# Also fails a branch that changes more than MAX_CHANGED_LINES lines against
# BASE (default origin/main; use the parent branch for a stacked branch).
# SIZE_OK=1 skips that check, for mechanical changes only. CI skips it too.
set -u
cd "$(dirname "$0")/.." || exit 1

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

# The checks, by kind. check_size.sh holds BASE, which pass_record reads too.
# shellcheck source=scripts/check_size.sh
. scripts/check_size.sh
# shellcheck source=scripts/check_rules.sh
. scripts/check_rules.sh
# shellcheck source=scripts/check_copies.sh
. scripts/check_copies.sh

# pass_record: what a passing run checked: the working tree's files (new
# ones included), the commit the size check measured from, and whether
# SIZE_OK skipped it. A passing run writes it to the checkout's git dir, and
# the commit hook (.agents/hooks/before-bash.py) lets a commit through only
# when --pass-record prints the same record for the files there now.
pass_record() {
	local index tree merge_base
	index="$(whole_change_index)" || return 1
	tree="$(GIT_INDEX_FILE="$index" git write-tree)"
	rm -f "$index"
	[ -n "$tree" ] || return 1
	merge_base="$(git merge-base "$BASE" HEAD)" || return 1
	echo "$tree $merge_base ${SIZE_OK:+size-ok}"
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

# strip_codes: stdin without terminal color and cursor codes.
strip_codes() {
	sed $'s/\e\[[0-9;]*[A-Za-z]//g'
}

# Lines from the end of the game suite's output a failure shows: the overall
# summary, or the last lines before a crash.
GAME_TAIL_LINES=12
# Lines a failure shows from each SCRIPT ERROR line, that line included: the
# error, then where Godot found it.
SCRIPT_ERROR_LINES=3

# game_failures FILE: the parts of the game suite's output FILE that say what
# failed: each failed test with its report, script errors, and its last
# GAME_TAIL_LINES lines. The rest is thousands of lines of passing tests and
# errors that tests raise on purpose.
game_failures() {
	strip_codes < "$1" | awk -v tail="$GAME_TAIL_LINES" -v error_lines="$SCRIPT_ERROR_LINES" '
		/ > .* FAILED/ { report = 1 }
		/SCRIPT ERROR/ { after = error_lines }
		report || after > 0 { print }
		after > 0 { after-- }
		report && /^[[:space:]]*$/ { report = 0 }
		{ last[NR % tail] = $0 }
		END {
			print "..."
			for (i = NR - tail + 1; i <= NR; i++) if (i > 0) print last[i % tail]
		}'
}

# failure_output I: what check I's output shows when it fails.
failure_output() {
	if [ "${names[$1]}" = game ]; then
		game_failures "$out/$1"
	else
		strip_codes < "$out/$1"
	fi
}

# summarize I: the last line of check I's output matching its pattern, with
# terminal codes removed.
summarize() {
	grep -E "${summaries[$1]}" "$out/$1" | tail -n 1 | strip_codes
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
			failure_output "$i" | sed 's/^/      /'
			grep -qE "$LEAKED" "$out/$i" &&
				printf '      Leaked at exit: rerun the step with --verbose to see what.\n'
		fi
	done
	names=()
	summaries=()
	pids=()
	return "$failed"
}

if [ "${1:-}" = --pass-record ]; then
	pass_record
	exit
fi

echo "== lint"
start gdstyle "files checked" game gdstyle check --no-color --max-warnings 0 .
start godot-warnings "scripts loaded" game check_warnings
# golangci-lint refuses a second copy at once unless allowed to.
start golangci-lint/relay "issues" relay golangci-lint run --allow-parallel-runners ./...
start golangci-lint/backend "issues" backend golangci-lint run --allow-parallel-runners ./...
# Silent when clean, so it says so itself.
start shellcheck "no issues" . sh -c \
	'shellcheck -x scripts/*.sh .agents/bin/*.sh game/run-tests.sh game/ui-gallery.sh deploy/*.sh deploy/grafana/*.sh deploy/web-template/*.sh .github/*.sh && echo "no issues"'
# Secrets: every commit, then every file on disk, including ones not yet
# added to git.
start gitleaks "no leaks found" . sh -c \
	'gitleaks git --no-banner --no-color . && gitleaks dir --no-banner --no-color .'
# Words too ambiguous to use, in any form (.agents/rules/style.md).
start banned-word "no banned word" . check_banned_word
start no-assert "no runtime asserts" . check_no_assert
start must-match "no must-match" . check_must_match
start debug-code "no debug code" . check_debug_code
start bool-asserts "no comparisons" . check_bool_asserts
start fixed-waits "no fixed waits" . check_fixed_waits
start mocks "no mocks" . check_mocks

start limits "limits in order" . check_limits
# Values copied across files, against deploy/build.env where it holds them.
start sync "copies in sync" . check_sync
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
start go-test/backend "all passed" backend sh -c 'go test ./... && echo "all passed"'
if ! finish; then
	exit 1
fi

# After the tests, which import the project first.
echo "== measure"
start snapshot "full lobby" game godot --headless --path . -s res://tools/snapshot_size.gd
start export "data files" game check_export
finish || exit 1
# After the tests, which can write files (Godot's import adds .uid files).
pass_record > "$(git rev-parse --git-path check-passed)" || exit 1
