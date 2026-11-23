---
name: merge-branch
description: Merges a finished branch into main - review check, squash to logical commits, fast-forward or merge commit, branch deletion. Use when the owner tells to merge a branch into main ("влей в main", "слей ветку").
---

# Merge a branch into main

Use the branch named in the request (default: the current branch) and any explicitly named next branch.

Done when the branch is merged into `main` (fast-forward for one commit, a merge commit for more), deleted, and nothing else was rebased, pushed or touched.

1. Unrelated changes (lock files, other agents' files) are reported and left out of every commit. The branch's own uncommitted work is committed in logical groups first (the merge command is the ask to commit); the review of step 3 covers the working tree when the branch has no commits.
2. Harness pass, before the review (during the task the harness is not touched unless the owner asks): `rg -n` the old wording of what the branch changed (a renamed term, option or file, a replaced behaviour) in docs, rules, skills, `AGENTS.md`, `--help` and comments, and fix what went stale; update the memory files that name the branch or its state. Show the harness diff to the owner together with the review.
3. A review of the branch must be visible in this conversation and its findings fixed or accepted. If it has not run, review the full branch diff, report findings with file and line references, and stop for the owner's decision before merging.
4. Squash to the logical commits (one concern per commit, documentation separate): `git reset --soft $(git merge-base main HEAD)` and `git reset` (no `git add -N` first: it registers deletions in the wrong group), then stage each group with `git add -A -- <paths>` and commit it with an English message. Check `git diff --cached --stat` before each commit; when a file belongs to two groups, put the whole file into the later one. After the last commit, build the first commit alone (`git checkout HEAD~N`) and return. `git rebase -i` does not work here.
5. The Codex Git hook reserves updates to `main` for the owner's terminal. After authorization, prepare the verified commands for the owner. First count `git rev-list --count main..<branch>`: then switch to `main`. One commit -> `git merge --ff-only <branch>`; two or more -> `git merge --no-ff <branch> -m "Merge <branch>"` (add the attribution lines as further `-m` paragraphs; `git merge -F -` does not read stdin). When `main` has moved, ask the owner before rebasing the branch.
6. After the owner applies the merge, verify that the expected tip is reachable from `main` before deleting the merged branch with `git branch -d <branch>`.
7. Rebase another branch only when `--rebase-next` or the owner names it; push never, unless asked.

After the merge, report the resulting `git log --oneline` of `main` and the branches left.
