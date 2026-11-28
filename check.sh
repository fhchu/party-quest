#!/usr/bin/env bash
# Runs every linter at once, then, if they all pass, every test suite at
# once. Run it after writing code. Exit code 0 means everything passed.
# A passing check prints one summary line; a failing one prints its output,
# or for the game suite only what failed. A passing run is recorded for the
# commit hook (pass_record); ./check.sh --pass-record prints that record for
# the files now and runs nothing.
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
		echo "Use public methods (.agents/rules/tests.md), or list it in $list with the owner's OK."
		return 1
	fi
	echo "no unlisted private members"
}

# check_banned_word: fails on any form of the words .agents/rules/style.md bans
# (Names: "Never ... in any form"), in tracked files and new ones not yet
# added, outside game/addons. A line holding the marker allow-synonyms is
# skipped; only the rule itself and this pattern need it.
check_banned_word() {
	local found
	local words='stand|stands|standing|stood|take|takes|taking|took|taken|takeover' # allow-synonyms
	found="$(git grep --untracked -nIiwE "$words" -- ':!game/addons' | grep -v allow-synonyms)"
	if [ -n "$found" ]; then
		echo "$found"
		echo "Say which meaning instead (.agents/rules/style.md, Names)."
		return 1
	fi
	echo "no banned word"
}

# check_no_assert: fails on a runtime assert in game code
# (.agents/rules/design.md, "Fail loudly at boundaries"): our own data and
# code are checked by tests.
check_no_assert() {
	local found
	found="$(git grep --untracked -nIE '(^|[^_[:alnum:]])assert\(' -- 'game/*.gd' ':!game/tests' ':!game/addons')"
	if [ -n "$found" ]; then
		echo "$found"
		echo "Check it in a test instead (.agents/rules/design.md, Principles)."
		return 1
	fi
	echo "no runtime asserts"
}

# fail_on_matches WHAT ADVICE PATTERN PATHSPEC...: fails, printing each line
# of the tracked and new files in PATHSPEC that matches the git grep -E
# PATTERN, then ADVICE; prints "no WHAT" when none does.
fail_on_matches() {
	local what="$1" advice="$2" pattern="$3" found
	shift 3
	found="$(git grep --untracked -nIE "$pattern" -- "$@" ':!game/addons')"
	if [ -n "$found" ]; then
		echo "$found"
		echo "$advice"
		return 1
	fi
	echo "no $what"
}

# check_must_match: fails on a comment asking that a copied value be kept
# equal by hand (.agents/rules/style.md, Comments).
check_must_match() {
	fail_on_matches "must-match comments" \
		"Read the value from one place, or add the pair to check_sync (.agents/rules/style.md, Comments)." \
		'(#|//).*([Mm]ust match|[Kk]eep in sync|[Kk]ept in sync|[Mm]ust stay in sync)' \
		'*.gd' '*.go' '*.sh' '*.py' ':!check.sh'
}

# check_debug_code: fails on code marked DEBUG, which is throwaway
# (.agents/rules/style.md, Comments). The [:] keeps this file from matching.
check_debug_code() {
	fail_on_matches "debug code" "Remove the DEBUG-marked code before committing." \
		'DEBUG[:]' '*.gd' '*.go' '*.sh' '*.py'
}

# check_bool_asserts: fails on a test asserting a comparison as a bool,
# whose failure says only "expected true" (.agents/rules/tests.md).
check_bool_asserts() {
	fail_on_matches "comparisons asserted as bools" \
		"Assert with the matcher for the value's type, such as assert_float(x).is_equal_approx(...) (.agents/rules/tests.md)." \
		'assert_bool\((is_equal_approx|is_zero_approx)\(|assert_bool\([^()]*( == | != | [<>]=? )[^()]*\)\.is_(true|false)\(\)' \
		'game/tests/*.gd'
}

# check_fixed_waits: fails on a test that waits a fixed time instead of for
# a condition (.agents/rules/tests.md).
check_fixed_waits() {
	fail_on_matches "fixed waits in tests" \
		"Wait for a condition, such as with _until, not a fixed time (.agents/rules/tests.md)." \
		'create_timer\(|time\.Sleep\(' 'game/tests/*.gd' '*_test.go'
}

# check_mocks: fails on a test that mocks a collaborator to check its calls
# (.agents/rules/tests.md).
check_mocks() {
	fail_on_matches "mocks in tests" \
		"Check the result (state, output, what reached the other side), not the calls made (.agents/rules/tests.md)." \
		'(^|[^_[:alnum:].])(mock|spy|verify)\(' 'game/tests/*.gd'
}

# Limits in different files and languages that must stay in order. Each is
# read as text, so a rewritten line fails here with "can't find" rather
# than passing.
# How many heartbeats the backend-silent alert's window must span, so one
# late heartbeat doesn't raise it.
MIN_HEARTBEATS_PER_SILENCE=2
# Time a release needs besides waiting for CI: v0.2.0's image job ran
# for under 8 minutes with the web template built from scratch.
RELEASE_BUILD_MIN=8

# pick FILE PATTERN: prints group 1 of the first line of FILE matching the
# sed -E PATTERN, or fails naming what it couldn't find. PATTERN holds no #.
pick() {
	local pattern="$2" value
	# Widened to the whole line, so only the group is left.
	[[ $pattern == ^* ]] || pattern=".*$pattern"
	[[ $pattern == *\$ ]] || pattern="$pattern.*"
	value="$(sed -nE "s#$pattern#\1#p" "$1" | head -n 1)"
	[ -n "$value" ] || { echo "can't find /$2/ in $1"; return 1; }
	echo "$value"
}

# check_limits: the backend's heartbeat against the silence alert, its own
# health check timeout against Docker's, and CI's job limit against the
# release gate's wait against the release job's limit.
check_limits() {
	local heartbeat silence probe docker ci wait release
	heartbeat="$(pick backend/cmd/api/health.go 'heartbeatInterval += ([0-9]+) \* time\.Minute')" || { echo "$heartbeat"; return 1; }
	silence="$(pick deploy/grafana/alerts.json 'absent_over_time\(.*\[([0-9]+)m\]')" || { echo "$silence"; return 1; }
	probe="$(pick backend/cmd/api/health.go 'healthcheckTimeout += ([0-9]+) \* time\.Second')" || { echo "$probe"; return 1; }
	docker="$(pick deploy/compose.yaml '^ +timeout: ([0-9]+)s')" || { echo "$docker"; return 1; }
	ci="$(pick .github/workflows/check.yml '^ +timeout-minutes: ([0-9]+)')" || { echo "$ci"; return 1; }
	wait="$(pick .github/wait-for-check.sh '^WAIT_SEC=([0-9]+)')" || { echo "$wait"; return 1; }
	# The image job's limit: the first in release.yml.
	release="$(pick .github/workflows/release.yml '^ +timeout-minutes: ([0-9]+)')" || { echo "$release"; return 1; }
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

# check_sync: values copied across files and languages agree, where the
# copies can't read one source. deploy/build.env is the source for what it
# holds.
check_sync() {
	local failed=0
	# shellcheck source=/dev/null
	. deploy/build.env
	# expect_same WHAT A B: fails, naming WHAT, unless A and B are equal and found.
	expect_same() {
		if [ -z "$2" ] || [ -z "$3" ] || [ "$2" != "$3" ]; then
			echo "$1 differ: '$2' and '$3'"
			failed=1
		fi
	}
	# expect_contains WHAT FILE TEXT: fails, naming WHAT, unless FILE holds TEXT.
	expect_contains() {
		grep -qF -- "$3" "$2" || { echo "$2 doesn't have $1: $3"; failed=1; }
	}
	local ws='[[:space:]]*'

	expect_same "relay/go.mod's toolchain and GO_VERSION" "$(pick relay/go.mod '^toolchain go(.+)$')" "$GO_VERSION"
	expect_same "backend/go.mod's toolchain and GO_VERSION" "$(pick backend/go.mod '^toolchain go(.+)$')" "$GO_VERSION"
	expect_contains "GAME_IMAGE" deploy/compose.yaml "image: $GAME_IMAGE:\${VERSION"
	expect_contains "BACKEND_IMAGE" deploy/compose.yaml "image: $BACKEND_IMAGE:\${VERSION"

	local secrets compose_secrets example_secrets release_secrets
	secrets="$(tr , '\n' <<<"$SECRET_NAMES" | sort)"
	compose_secrets="$(grep -oE '\$\{[A-Z_]+:\?' deploy/compose.yaml | tr -d ':?{$' |
		grep -vxE 'VERSION|DOMAIN' | sort -u)"
	example_secrets="$(grep -oE '^[A-Z_]+=' deploy/secrets.env.example | tr -d = | sort)"
	release_secrets="$(awk '/name: Start the version on the server/ { f = 1 } f && /run:/ { exit } f' \
		.github/workflows/release.yml | grep -oE '\$\{\{ secrets\.[A-Z_]+' | sed 's/.*\.//' | sort)"
	expect_same "the secrets compose.yaml reads and SECRET_NAMES" "$compose_secrets" "$secrets"
	expect_same "secrets.env.example's names and SECRET_NAMES" "$example_secrets" "$secrets"
	expect_same "the secrets release.yml's deploy step passes and SECRET_NAMES" "$release_secrets" "$secrets"

	local restarted
	restarted="$(pick backend/cmd/api/health.go "^${ws}restartedMsg = \"(.+)\"")"
	expect_contains "health.go's restartedMsg" deploy/entrypoint.sh "echo \"entrypoint: $restarted\""
	local alert_phrase
	alert_phrase="$(awk '/"uid": "pq-restarted"/ { f = 1 } f && /"expr"/ { print; exit }' deploy/grafana/alerts.json |
		sed -nE 's/.*\|= \\"([^\\]+)\\".*/\1/p')"
	case "$restarted" in
	*"$alert_phrase"*) [ -n "$alert_phrase" ] || { echo "can't find the pq-restarted alert's phrase"; failed=1; } ;;
	*) echo "the pq-restarted alert's phrase '$alert_phrase' isn't in restartedMsg '$restarted'"; failed=1 ;;
	esac

	local socket
	socket="$(pick deploy/compose.yaml "^${ws}- (/[^:]+\.sock):/[^:]+:ro$")"
	expect_same "the Docker socket in compose.yaml and config.alloy's hosts" \
		"$(grep -oE 'host += "unix://[^"]+"' deploy/alloy/config.alloy | sed -E 's/.*unix:\/\///; s/"//' | sort -u)" "$socket"

	expect_contains "BUILD_ID_SETTING's section" deploy/stamp-build.sh "\$0 == \"[$(pick game/net/protocol.gd 'BUILD_ID_SETTING := "([^/]+)/.*"')]\""
	expect_contains "BUILD_ID_SETTING's key" deploy/stamp-build.sh "line=\"$(pick game/net/protocol.gd 'BUILD_ID_SETTING := "[^/]+/(.+)"')="

	expect_same "GAME_PATH and gamePath" "$(pick game/net/protocol.gd 'GAME_PATH := "(.+)"')" "$(pick relay/main.go 'gamePath = "(.+)"')"
	expect_same "GAME_PORT and the relay's -game default" "$(pick game/net/protocol.gd 'GAME_PORT := ([0-9]+)')" \
		"$(pick relay/main.go '"game", "127\.0\.0\.1:([0-9]+)"')"
	expect_same "RELAY_PORT and the relay's -addr default" "$(pick game/net/protocol.gd 'RELAY_PORT := ([0-9]+)')" \
		"$(pick relay/main.go '"addr", ":([0-9]+)"')"
	expect_same "dev.sh's relay_port and the relay's -addr default" "$(pick dev.sh '^relay_port=([0-9]+)$')" \
		"$(pick relay/main.go '"addr", ":([0-9]+)"')"

	expect_same "web_shell.html's and export-web.sh's page flag for a turned canvas" \
		"$(pick game/client/web_shell.html '^window\.([A-Za-z]+) = false;$')" \
		"$(pick deploy/export-web.sh 'if\(window\.([A-Za-z]+)\)')"
	expect_same "web_shell.html's and export-web.sh's press placement for a turned canvas" \
		"$(pick game/client/web_shell.html '^window\.([A-Za-z]+) = function \(evt, rect, canvas\)')" \
		"$(pick deploy/export-web.sh 'return window\.([A-Za-z]+)\(evt,rect,canvas\)')"

	expect_same "UNSUPPORTED_BROWSER_TEXT and noBrotliText" \
		"$(grep -A1 'UNSUPPORTED_BROWSER_TEXT := ' game/client/client.gd | sed -nE 's/^[[:space:]]+"(.+)"\)$/\1/p')" \
		"$(pick relay/static.go 'noBrotliText = "(.+)\\n"')"

	local kind
	for kind in RELIABLE:Reliable UNRELIABLE:Unreliable ORDERED:Ordered PEER_ID:PeerID; do
		expect_same "frames.gd's ${kind%%:*} and frames.go's kind${kind#*:}" \
			"$(pick game/net/frames.gd "^${ws}${kind%%:*} = ([0-9]+),")" \
			"$(pick relay/frames.go "^${ws}kind${kind#*:} += ([0-9]+)")"
	done
	expect_same "MAX_FRAME and maxFrame" "$(pick game/net/frames.gd 'MAX_FRAME := (.+)$')" "$(pick relay/frames.go "^${ws}maxFrame = (.+)$")"
	expect_same "frames.gd's U32_SIZE and frames.go's lengthSize" \
		"$(pick game/net/frames.gd 'U32_SIZE := ([0-9]+)')" "$(pick relay/frames.go "^${ws}lengthSize = ([0-9]+)")"

	expect_same "MAX_PLAYERS and maxEarners" "$(pick game/server/lobby.gd '^const MAX_PLAYERS := ([0-9]+)')" \
		"$(pick backend/internal/runs/runs.go '^const maxEarners = ([0-9]+)')"
	expect_same "item_gold.tres's display_name and gold's name in items.json" \
		"$(pick game/shared/data/items/item_gold.tres '^display_name = "(.+)"$')" \
		"$(pick backend/items/items.json '"id": "gold", "name": "([^"]+)"')"
	expect_same "run.outcome's CHECK and outcomes" \
		"$(pick backend/migrations/00001_init.sql "CHECK \(outcome IN \((.+)\)\)" | tr -d "' ")" \
		"$(pick backend/internal/runs/runs.go '^var outcomes = \[\]string\{(.+)\}' | tr -d '" ')"

	expect_same "where the reviewer gate and review.py keep their records" \
		"$(pick .agents/hooks/before-bash.py '^REVIEWED_DIR = os\.path\.expanduser\("(.+)"\)$')" \
		"$(pick .agents/bin/review.py '^STATE = os\.path\.expanduser\("(.+)"\)$')"
	expect_contains "the review line review.py reads" .agents/agents/reviewer.md \
		"\`$(pick .agents/bin/review.py '^LINE_FORMAT = "(.+)"$')\`"
	expect_same "where the reviewer gate and review.py keep a review's report" \
		"$(pick .agents/hooks/before-bash.py '^REPORT_SUFFIX = "(.+)"$')" \
		"$(pick .agents/bin/review.py '^REPORT_SUFFIX = "(.+)"$')"
	expect_contains "the nit tag before-bash.py reads" .agents/agents/reviewer.md \
		"\`$(pick .agents/hooks/before-bash.py '^NIT_FORMAT = "(.+)"$')\`"
	expect_contains "the blocking tag before-bash.py reads" .agents/agents/reviewer.md \
		"\`$(pick .agents/hooks/before-bash.py '^BLOCKING_TAG = "(.+)"$') "

	expect_same "ui-shots-on-stop.py's SHEET and the contact sheet ui-gallery.sh writes" \
		"$(pick .agents/hooks/ui-shots-on-stop.py '^SHEET = "(.+)"$')" \
		"game/$(pick game/ui-gallery.sh '^DEFAULT_OUT=(.+)$')/$(pick game/tools/ui_gallery/ui_gallery.gd '^const SHEET_FILE := "(.+)"$')"

	python3 .agents/bin/sync-agents.py --check || failed=1

	# A path-scoped rule names its files twice: globs for Antigravity, paths
	# for Claude Code.
	local rule
	for rule in .agents/rules/*.md; do
		grep -q '^trigger: glob$' "$rule" || continue
		expect_same "$rule's globs and paths" \
			"$(pick "$rule" '^globs: "(.+)"$')" \
			"$(sed -n '/^paths:$/,/^---$/s/^  - "\(.*\)"$/\1/p' "$rule" | paste -sd, - | sed 's/,/, /g')"
	done

	[ "$failed" = 0 ] && echo "copies in sync"
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
	'shellcheck check.sh dev.sh .agents/bin/*.sh game/run-tests.sh game/ui-gallery.sh deploy/*.sh deploy/grafana/*.sh deploy/web-template/*.sh .github/*.sh && echo "no issues"'
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
