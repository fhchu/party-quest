#!/usr/bin/env bash
# Hides from Godot every folder the web export leaves out, so the editor's
# Engine Compilation Configuration Editor detects only the classes the
# client uses. `on` puts a .gdignore in each folder the Web preset's
# exclude_filter (game/export_presets.cfg) names; `off` removes only the
# ones it added, and brings back the .uid files the editor deleted in those
# folders while they were hidden. While it's on, the tests can't run, so
# ./check.sh fails.
set -euo pipefail
cd "$(dirname "$0")/../../game"
marker="# Added by deploy/web-template/profile-scope.sh; remove with its 'off'."

# The filter is a comma-separated list such as "tests/*, sim/*"; each
# folder pattern ends in /*.
excluded_dirs() {
	sed -n 's/^exclude_filter="\(.*\)"$/\1/p' export_presets.cfg \
		| tr ',' '\n' | sed -n 's|^ *\(.*\)/\*$|\1|p'
}

case "${1:-}" in
on)
	excluded_dirs | while read -r dir; do
		if [ -d "$dir" ] && [ ! -e "$dir/.gdignore" ]; then
			echo "$marker" > "$dir/.gdignore"
			echo "hid $dir"
		fi
	done
	;;
off)
	excluded_dirs | while read -r dir; do
		if [ -f "$dir/.gdignore" ] && [ "$(head -n 1 "$dir/.gdignore")" = "$marker" ]; then
			rm "$dir/.gdignore"
			# Only deleted files git tracks, so no edit is overwritten.
			git ls-files --deleted -z -- "$dir/*.uid" | xargs -0 -r git checkout --
			echo "restored $dir"
		fi
	done
	;;
*)
	echo "usage: $0 on|off" >&2
	exit 2
	;;
esac
