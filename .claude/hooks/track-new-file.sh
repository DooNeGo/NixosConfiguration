#!/usr/bin/env bash
# PostToolUse(Write): flakes see only git-tracked files, so mark a newly written file intent-to-add.
# Exit 2 hands stderr to Claude; exit 0 would hide the failure until Nix reports "not tracked by Git".
file=$(jq -r '.tool_input.file_path // empty') || {
  echo "track-new-file.sh: cannot read the hook input with jq" >&2
  exit 2
}
[ -n "$file" ] || exit 0
[ -n "$CLAUDE_PROJECT_DIR" ] || exit 0
cd "$CLAUDE_PROJECT_DIR" || {
  echo "track-new-file.sh: cannot cd to $CLAUDE_PROJECT_DIR" >&2
  exit 2
}
case "$file" in
  "$CLAUDE_PROJECT_DIR"/*) ;;
  *) exit 0 ;;
esac
git ls-files --error-unmatch -- "$file" > /dev/null 2>&1 && exit 0
git check-ignore -q -- "$file" && exit 0
git add -N -- "$file" 1>&2 || {
  echo "track-new-file.sh: git add -N failed for $file, run it by hand before a Nix build" >&2
  exit 2
}
