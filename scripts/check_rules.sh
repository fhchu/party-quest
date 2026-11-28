# shellcheck shell=bash
# Checks that written rules are kept, by grepping the code. Sourced by
# scripts/check.sh, which runs each check from the folder its start line
# names.

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
		'*.gd' '*.go' '*.sh' '*.py'
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
