# Codex hooks and permissions

Project hooks live in `.codex/hooks.json` and run from a trusted project. Use `/hooks` to review and trust changes. Hook commands resolve the Git root so they also work when the session starts in a subdirectory.

The Git `PreToolUse` hook blocks protected commands with a reason on stderr and exit 2. The guarded main merge command matches the `prompt` rule in `.codex/rules/main-merge.rules`. The rule routes an eligible approval request to the configured reviewer. The merge workflow separately requires explicit owner authorization in chat. The owner runs other protected operations in their terminal. Force pushes are prohibited. Keep ordinary feature-branch work available.

Use a Codex `prefix_rule` for controlling execution outside the sandbox. Branch-aware checks belong in the hook. Hooks cover the supported tool paths and remain subject to the host's own permission policy.

Validate edits with representative hook JSON payloads and an isolated Git repository. Include ordinary commands on a feature branch, protected operations on main, and tool input without the fields the hook expects.
