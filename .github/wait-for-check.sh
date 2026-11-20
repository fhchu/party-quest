#!/usr/bin/env bash
# Waits for the check workflow's run on a commit pushed to main, and fails
# unless it passed, so a release can't ship a commit CI failed or never
# checked. Run by .github/workflows/release.yml.
# Needs: gh, signed in (GH_TOKEN); SHA, the tagged commit.
set -euo pipefail

# How long to wait for a run still in progress, well over a check run's
# usual length (.github/workflows/check.yml). Must stay under the image
# job's timeout in .github/workflows/release.yml. Untuned.
WAIT_SEC=600
# Untuned.
POLL_SEC=15

sha="${SHA:?set SHA}"
deadline=$((SECONDS + WAIT_SEC))
while :; do
	read -r status conclusion < <(gh run list --workflow check.yml --branch main --event push \
		--commit "$sha" --limit 1 --json status,conclusion \
		-q '.[0] | "\(.status) \(.conclusion)"') || true
	case "${status:-}" in
	completed)
		if [ "$conclusion" = success ]; then
			echo "check passed on $sha"
			exit 0
		fi
		# A cancelled run fails here too: check.yml's concurrency cancels a
		# run on main when a newer push lands, so only the newest of several
		# quick merges is checked.
		echo "check ended '$conclusion' on $sha; fix main and tag a commit that passes." >&2
		exit 1
		;;
	"" | null)
		echo "no check run on main for $sha yet" ;;
	*)
		echo "check is $status on $sha" ;;
	esac
	if [ "$SECONDS" -ge "$deadline" ]; then
		echo "no passing check run on main for $sha after $WAIT_SEC s; tag a commit CI checked." >&2
		exit 1
	fi
	sleep "$POLL_SEC"
done
