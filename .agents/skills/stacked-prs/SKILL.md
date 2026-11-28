---
name: stacked-prs
description: Open, extend or update a stack of PRs (branches cut from one another, each PR based on the one below), linked with gh stack link. Use when work is split across branches, when check.sh says a branch is too big, or when adding a branch on top of an open PR.
---

# Stacked PRs

The rules are in `.agents/rules/workflow.md` ("Branch size") and the
`design-sketch` skill ("Branches"); this is the procedure.

1. **Plan the layers** in the sketch, bottom to top. Each layer
   stays under `check.sh`'s size limit and passes `scripts/check.sh` on its
   own; a layer changing `.md` files alone skips it.
2. **Cut each branch from the one below**, in its own worktree off the
   parent branch, not `main`: `.agents/bin/worktree.sh new <branch>
   <parent branch>`.
3. **Check each layer against its parent:** `BASE=<parent branch>
   scripts/check.sh`. The commit hook lets a commit through only after a run
   with the same base passed: it reads the base from the open PR once the
   PR exists; before that, put `BASE=<parent>` in the commit command.
4. **Open the PRs bottom up**, each based on the one below:
   `gh pr create --base <parent branch> --head <branch> --body-file <file>`.
   The bottom PR's base is `main`. The description gives a summary,
   behavior changes, how it was checked, the "New dependencies" line
   (see `.agents/rules/design.md`), and the reviewer's "Beyond the
   request" list if it gave one.
5. **Link the stack:** `.agents/bin/stack-link.sh <top branch>`. It
   follows the open PRs' bases down to `main` (a merged layer's branch is
   deleted, so GitHub has moved its child's base down) and links the PRs by number, so it never pushes or opens one. Run it
   again whenever the stack grows.

Never merge, and never commit to `main`.
