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
5. Before merging into `main`, run `git fetch origin` and compare `main` with `origin/main` using `git rev-list --left-right --count main...origin/main`. If `main` is behind only, have the owner run `git pull --ff-only origin main` from `main`. If both branches have unique commits, stop and ask how to reconcile them. If `main` is current or only ahead, proceed.
6. After the owner's explicit authorization in chat, count `git rev-list --count main..<branch>` and switch to `main`. Submit the guarded merge by local branch name as a standalone shell call using the command in `docs/codex-harness.md` and `sandbox_permissions: require_escalated`. Pass the main tip from preflight and the branch tip from review. Do not persist an approval prefix. If the guard reports that the branch moved, review the changes and request Auto-review again. The owner's consent still applies to the same branch. Stop and report any findings before merging. If `main` moved, rerun preflight and ask the owner before rebasing the branch.
7. Verify that the resulting `main` tip for a fast-forward, or its second parent for a merge commit, matches the reviewed branch tip. If it differs, report the discrepancy and stop. Delete the merged branch with `git branch -d <branch>` if it still points to the reviewed tip.
8. Rebase another branch only when `--rebase-next` or the owner names it; push never, unless asked.

After the merge, report the resulting `git log --oneline` of `main` and the branches left.
