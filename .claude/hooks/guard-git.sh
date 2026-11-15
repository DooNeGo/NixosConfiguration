#!/usr/bin/env bash
# PreToolUse(Bash): ask before git commands that rewrite history, move main or discard work, in any
# spelling (`git -C dir push`, `git branch -df`, `a && git merge x`). A permission prefix rule matches one spelling only.
# A false positive costs one question; the force-push deny rule in settings.json still wins over this ask.
# Exit 1 does not block: without jq the prefix ask rules in settings.json stay as the fallback (blocking would stop every Bash call).
cmd=$(jq -r '.tool_input.command // empty') || {
  echo "guard-git.sh: cannot read the hook input with jq, only the prefix ask rules apply" >&2
  exit 1
}
reason=""
while IFS= read -r segment; do
  read -ra t <<< "$segment"
  i=0
  while [ "$i" -lt "${#t[@]}" ] && [ "${t[$i]##*/}" != git ]; do i=$((i + 1)); done
  [ "$i" -lt "${#t[@]}" ] || continue
  i=$((i + 1))
  # skip git's global options; -C, -c and the long path options take a separate argument
  while [ "$i" -lt "${#t[@]}" ]; do
    case "${t[$i]}" in
      -C | -c | --git-dir | --work-tree | --namespace) i=$((i + 2)) ;;
      -*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  sub="${t[$i]:-}"
  rest=("${t[@]:$((i + 1))}")
  flags=" ${rest[*]} "
  letters=""
  for a in "${rest[@]}"; do
    case "$a" in -[a-zA-Z]*) [[ "$a" != --* ]] && letters+="${a#-}" ;; esac
  done
  case "$sub" in
    merge | rebase | push | clean) reason="git $sub" ;;
    reset) [[ "$flags" == *" --hard "* ]] && reason="git reset --hard" ;;
    branch)
      if [[ "$letters" == *D* ]] || { [[ "$letters" == *d* || "$flags" == *" --delete "* ]] && [[ "$letters" == *f* || "$flags" == *" --force "* ]]; }; then
        reason="git branch force delete"
      fi
      ;;
    checkout) [[ "$flags" == *" . "* ]] && reason="git checkout . (discards worktree changes)" ;;
    restore)
      if [[ "$flags" == *" . "* || "$flags" == *" :/ "* ]]; then
        if [[ "$flags" != *" --staged "* && "$letters" != *S* ]] || [[ "$flags" == *" --worktree "* || "$letters" == *W* ]]; then
          reason="git restore . (discards worktree changes)"
        fi
      fi
      ;;
  esac
  [ -z "$reason" ] || break
done < <(printf '%s\n' "$cmd" | sed -E 's/(&&|\|\||;|\||\()/\n/g')
[ -n "$reason" ] || exit 0
jq -n --arg r "$reason: the owner confirms it" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}}'
