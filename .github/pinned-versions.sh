#!/bin/sh
# Prints a Markdown line for each pinned version that is behind its
# project's latest GitHub release, and nothing when all are current. These
# are the pins Dependabot can't read (.github/dependabot.yml). Run by
# .github/workflows/versions.yml. Needs: gh, signed in.
#
# Emscripten (deploy/web-template/build.sh) is left out on purpose: it must
# match the version Godot's own web template used, not the newest.
set -eu

pin() { sed -n "s/^ *$1: *//p" "$2" | head -n 1; }

check() {
	name=$1 repo=$2 current=$3 file=$4
	latest=$(gh api "repos/$repo/releases/latest" --jq .tag_name)
	# Tags are like v1.2.3 or 4.7.2-stable; pins are bare versions.
	latest=${latest#v}
	latest=${latest%-stable}
	if [ "$latest" != "$current" ]; then
		echo "- **$name**: $current → $latest (pinned in \`$file\`; https://github.com/$repo/releases)"
	fi
}

ci=.github/workflows/check.yml
release=.github/workflows/release.yml
gdunit=game/addons/gdUnit4/plugin.cfg

check Godot godotengine/godot "$(pin GODOT_VERSION $ci)" "$ci, $release, deploy/Dockerfile"
check GdUnit4 godot-gdunit-labs/gdUnit4 "$(sed -n 's/^version="\(.*\)"$/\1/p' $gdunit)" "$gdunit"
check gdstyle atelico/gdstyle "$(pin GDSTYLE_VERSION $ci)" "$ci"
check golangci-lint golangci/golangci-lint "$(pin GOLANGCI_LINT_VERSION $ci)" "$ci"
check shellcheck koalaman/shellcheck "$(pin SHELLCHECK_VERSION $ci)" "$ci"
check gitleaks gitleaks/gitleaks "$(pin GITLEAKS_VERSION $ci)" "$ci"
check uv astral-sh/uv "$(pin UV_VERSION $release)" "$release"
