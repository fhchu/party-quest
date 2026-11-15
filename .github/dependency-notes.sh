#!/bin/sh
# Fails if this PR adds a line to game/tests/dependencies.txt that its
# description doesn't name. Run by .github/workflows/dependencies.yml.
# Needs: BASE_SHA (the PR's base commit) and PR_BODY (its description).
set -eu

list=game/tests/dependencies.txt
added=$(git diff --no-color --unified=0 "$BASE_SHA" HEAD -- "$list" \
	| sed -n 's/^+\([^+#].*\)$/\1/p')
if [ -z "$added" ]; then
	echo "no new references across folders"
	exit 0
fi

missing=$(printf '%s\n' "$added" | while IFS= read -r line; do
	printf '%s' "$PR_BODY" | grep -qF -- "$line" || printf '%s\n' "$line"
done)
if [ -n "$missing" ]; then
	echo "This PR adds references across folders its description doesn't name."
	echo "Name each line below in the PR description, after the owner's OK:"
	printf '%s\n' "$missing"
	exit 1
fi
echo "every new reference across folders is named in the description"
