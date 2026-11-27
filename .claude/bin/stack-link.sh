#!/usr/bin/env bash
# Links a stack of open PRs on GitHub (the stacked-prs skill's last step).
#
#   stack-link.sh TOP_BRANCH
#
# Starts at TOP_BRANCH's open PR and follows each PR's base down to main,
# then runs gh stack link with those PRs, bottom to top. A merged layer
# drops out on its own, since GitHub moves its child's base down to the
# merged PR's base. Links by PR number, so gh stack link neither pushes a
# branch nor opens a PR.
set -eu

die() {
	echo "$1" >&2
	exit 1
}

[ $# -eq 1 ] || die "Usage: stack-link.sh TOP_BRANCH"

prs=()
branch="$1"
while [ "$branch" != main ]; do
	# "<number> <base branch>" of the branch's open PR, or nothing.
	pr="$(gh pr list --head "$branch" --state open --json number,baseRefName \
		-q '.[0] // empty | "\(.number) \(.baseRefName)"')"
	[ -n "$pr" ] || die "$branch has no open PR; open it before linking the stack."
	prs=("${pr%% *}" ${prs[@]+"${prs[@]}"})
	branch="${pr#* }"
done

[ "${#prs[@]}" -ge 2 ] || die "$1's PR is based on main: there's no stack to link."
echo "Linking PRs ${prs[*]} (bottom to top)."
gh stack link "${prs[@]}"
