# shellcheck shell=bash
# Checks that values copied across files agree, and that limits in
# different files stay in order. Sourced by scripts/check.sh, which runs
# each check from the folder its start line names.

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
	expect_same "dev.sh's relay_port and the relay's -addr default" "$(pick scripts/dev.sh '^relay_port=([0-9]+)$')" \
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
