#!/usr/bin/env bash
# Downloads the game's art from its Google Drive folder into
# game/client/assets/, subfolder for subfolder. The art isn't in git: it's
# the owner's, and the repo is public. The release workflow runs this
# before the web export; run it locally to pull the art too.
#
# Signs in with GOOGLE_ACCESS_TOKEN if it's set (the release workflow sets
# it), else with your gcloud login, which needs
# `gcloud auth login --enable-gdrive-access` once. Needs curl and jq
# (brew install jq).
#
# Fails if any download fails, or if a resource (.tres) in
# game/client/assets/ points at a file that isn't there afterwards, so a
# release never ships without its art. Google Docs, Sheets and the like
# can't be downloaded as files; keep only plain files in the folder.
set -euo pipefail
cd "$(dirname "$0")/.."

# PLACEHOLDER (hosting): the Drive folder that mirrors game/client/assets/.
# Not secret: only accounts it's shared with can read it.
folder_id="PLACEHOLDER"
assets="game/client/assets"
api="https://www.googleapis.com/drive/v3/files"
folder_type="application/vnd.google-apps.folder"

token="${GOOGLE_ACCESS_TOKEN:-$(gcloud auth print-access-token)}"

# Downloads everything in Drive folder $1 into directory $2, its subfolders
# into subdirectories.
fetch_folder() {
	local id="$1" dir="$2" page_token="" listing
	mkdir -p "$dir"
	while :; do
		local args=(
			--data-urlencode "q='$id' in parents and trashed = false"
			--data-urlencode "fields=nextPageToken, files(id, name, mimeType)"
			# Drive's largest page.
			--data-urlencode "pageSize=1000"
		)
		if [ -n "$page_token" ]; then
			args+=(--data-urlencode "pageToken=$page_token")
		fi
		listing="$(curl -fsS -G "$api" -H "Authorization: Bearer $token" "${args[@]}")"
		while IFS=$'\t' read -r file_id name mime; do
			if [ "$mime" = "$folder_type" ]; then
				fetch_folder "$file_id" "$dir/$name"
			else
				curl -fsS -H "Authorization: Bearer $token" -o "$dir/$name" \
					"$api/$file_id?alt=media"
				echo "fetched $dir/$name"
			fi
		done < <(jq -r '.files[] | [.id, .name, .mimeType] | @tsv' <<<"$listing")
		page_token="$(jq -r '.nextPageToken // empty' <<<"$listing")"
		if [ -z "$page_token" ]; then
			break
		fi
	done
}

fetch_folder "$folder_id" "$assets"

# Every file a resource here points at has to be here now.
missing=0
while IFS= read -r path; do
	if [ ! -f "game/${path#res://}" ]; then
		echo "missing game/${path#res://}: add it to the Drive folder" >&2
		missing=1
	fi
done < <(grep -rhoE --include='*.tres' 'path="res://client/assets/[^"]+"' "$assets" \
	| sed -E 's/^path="(.*)"$/\1/')
if [ "$missing" -ne 0 ]; then
	exit 1
fi
