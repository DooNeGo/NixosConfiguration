---
name: code-review
description: Independently review a branch, working tree, commit, or pull request for introduced bugs and consequential violations of project instructions. Use when asked for a code review.
---

# Code review

Review the scope the user names; if none is named, review the current working-tree changes, or the current branch against its merge base with the default branch when the working tree is clean. If the intended scope cannot be determined, ask. Include the relevant task or PR description when available.

Delegate independent reviews in parallel using available subagents: one for correctness and regressions, another for applicable project instructions and integration behavior. Give each the exact scope and relevant intent. If delegation is unavailable, perform both passes directly and say so.

Inspect the surrounding code as needed to establish whether a finding is real. Independently verify candidate findings against the actual code and applicable instructions; discard duplicates, pre-existing issues, speculation, and purely stylistic or naming concerns. Include input-dependent defects when their trigger and impact can be explained. Do not modify the reviewed code or publish comments unless the user requests it.

Report actionable findings in severity order with file and line references, the trigger and impact. If there are none, say so. State meaningful review limitations and checks that were not performed.
