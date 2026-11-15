---
name: merge-branch
description: Merges a finished branch into main - review check, squash to logical commits, fast-forward or merge commit, branch deletion. Use when the owner tells to merge a branch into main ("влей в main", "слей ветку").
argument-hint: "[branch] [--rebase-next BRANCH]"
---

# Merge a branch into main

Arguments: $ARGUMENTS (default: the current branch)

Done when the branch is merged into `main` (fast-forward for one commit, a merge commit for more), deleted, and nothing else was rebased, pushed or touched.

1. `git status` must be clean for the branch. Unrelated changes (lock files, other agents' files) are reported and left out of every commit.
2. A `/code-review` of this branch must already have run in this conversation with its findings reported and fixed or accepted. If not, run it, report its findings and stop: the owner merges only after seeing the review.
3. Squash to the logical commits (one concern per commit, documentation separate): `git reset --soft $(git merge-base main HEAD)`, then commit the groups again with English messages. `git rebase -i` does not work here.
4. `git switch main`, then count `git rev-list --count main..<branch>`: one commit -> `git merge --ff-only <branch>`; two or more -> `git merge --no-ff <branch> -m "Merge <branch>"` (add the attribution lines as further `-m` paragraphs; `git merge -F -` does not read stdin). When `main` has moved, ask the owner before rebasing the branch.
5. `git branch -d <branch>` right away, without asking: a merged branch is not kept.
6. Rebase another branch only when `--rebase-next` or the owner names it; push never, unless asked.

Report the resulting `git log --oneline` of `main` and the branches left.
