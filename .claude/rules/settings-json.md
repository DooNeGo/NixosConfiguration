---
paths:
  - ".claude/settings.json"
  - ".claude/hooks/**"
---

# Permission rules in settings.json

- One wildcard pattern per command, not one line per spelling: `Bash(git branch* -f*)` instead of `-f`, `-d -f`, `-f -d`. The `deny` rules already use the form.
- Write a short option with a space before it (`* -f*`, not `*-f*`): without it the pattern also matches `feature-fix`. A spelling that has no space before it (`-df`) stays a separate prefix rule (`Bash(git branch -df:*)`).
- `.claude/hooks/guard-git.sh` is the check; the `ask` rules are its fallback for a missing `jq`, and hold only the commands the hook asks on every branch. A rule here asks on every branch, so a command that is protected for `main` only (rebase, merge, reset, branch -f) lives in the hook alone.
