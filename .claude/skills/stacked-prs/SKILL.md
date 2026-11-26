---
name: stacked-prs
description: Open, extend or update a stack of PRs (branches cut from one another, each PR based on the one below), linked with gh stack link. Use when work is split across branches, when check.sh says a branch is too big, or when adding a branch on top of an open PR.
---

# Stacked PRs

The rules are in `.claude/rules/workflow.md` ("Branch size") and the
`design-sketch` skill ("Branches"); this is the procedure.

1. **Plan the layers** in the sketch, bottom to top. Each layer
   stays under `check.sh`'s size limit and passes `./check.sh` on its
   own; a layer changing `.md` files alone skips it.
2. **Cut each branch from the one below**, in its own worktree off the
   parent branch, not `main`. For a milestone, the top branch reuses the
   milestone's branch name (e.g. `phase2-m1`).
3. **Check each layer against its parent:** `BASE=<parent branch>
   ./check.sh`. The commit hook does this from the open PR's base once the
   PR exists; before that, put `BASE=<parent>` in the commit command.
4. **Open the PRs bottom up**, each based on the one below:
   `gh pr create --base <parent branch> --head <branch> --body-file <file>`.
   The bottom PR's base is `main`. The description gives a summary,
   behavior changes, how it was checked, and the "New files" and "New
   dependencies" lines (see `.claude/rules/design.md`).
5. **Link the stack:** first check each branch's PR is still open
   (`gh pr list --head <branch> --state open`) and leave merged ones out.
   Then `gh stack link <open branches, bottom to top>`. Run it again with
   the new branch added whenever the stack grows.

Never merge, and never commit to `main`.
