#!/usr/bin/env bash
# PostToolUse(Write): flakes see only git-tracked files, so mark a newly written file intent-to-add.
file=$(jq -r '.tool_input.file_path // empty')
[ -n "$file" ] || exit 0
cd "$CLAUDE_PROJECT_DIR" || exit 0
case "$file" in
  "$CLAUDE_PROJECT_DIR"/*) ;;
  *) exit 0 ;;
esac
git ls-files --error-unmatch -- "$file" > /dev/null 2>&1 \
  || git check-ignore -q -- "$file" \
  || git add -N -- "$file"
exit 0
