#!/usr/bin/env bash
# Writes a release's build ID (its tag, such as v0.2.1) into
# game/project.godot, before the web export and the image build read it. The
# game server turns away a tab whose build differs (Protocol.build_id in
# game/net/protocol.gd).
#
# Usage: deploy/stamp-build.sh v0.2.1
set -euo pipefail
cd "$(dirname "$0")/.."
build_id="${1:?usage: deploy/stamp-build.sh <tag>}"
project=game/project.godot

# The setting is config/version under [application]: must match
# BUILD_ID_SETTING in game/net/protocol.gd. Any earlier value is replaced.
stamped=$(awk -v line="config/version=\"$build_id\"" '
	/^config\/version=/ { next }
	{ print }
	$0 == "[application]" { print line }
' "$project")
printf '%s\n' "$stamped" >"$project"
grep -qxF "config/version=\"$build_id\"" "$project" || {
	echo "stamp-build: no [application] section in $project" >&2
	exit 1
}
