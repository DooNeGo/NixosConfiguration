#!/usr/bin/env bash
# PreToolUse(Bash): ask before git commands that change `main` or cannot be taken back, in any spelling
# (`git -C dir push`, `git branch -df`, `a && git merge x`). A permission prefix rule matches one spelling only.
# Always asked: push, clean, reset --hard, checkout/restore of ".", force delete of a branch, tag -f. Asked only
# for main: merge, rebase and any reset while main is checked out, and branch -f/-M, switch -C, checkout -B,
# update-ref that name main. Other branches are the agent's to rewrite.
# A false positive costs one question; the force-push deny rule in settings.json still wins over this ask.
# Exit 1 does not block: without jq the prefix ask rules in settings.json stay as the fallback (blocking would stop every Bash call).
input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<< "$input") || {
  echo "guard-git.sh: cannot read the hook input with jq, only the prefix ask rules apply" >&2
  exit 1
}
cwd=$(jq -r '.cwd // empty' <<< "$input")

is_main() { [ "$1" = main ] || [ "$1" = refs/heads/main ]; }

reason=""
while IFS= read -r segment; do
  read -ra t <<< "$segment"
  i=0
  while [ "$i" -lt "${#t[@]}" ] && [ "${t[$i]##*/}" != git ]; do i=$((i + 1)); done
  [ "$i" -lt "${#t[@]}" ] || continue
  i=$((i + 1))
  dir=$cwd
  # skip git's global options; -C, -c and the long path options take a separate argument
  while [ "$i" -lt "${#t[@]}" ]; do
    case "${t[$i]}" in
      -C)
        dir=${t[$((i + 1))]:-$dir}
        i=$((i + 2))
        ;;
      -c | --git-dir | --work-tree | --namespace) i=$((i + 2)) ;;
      -*) i=$((i + 1)) ;;
      *) break ;;
    esac
  done
  sub="${t[$i]:-}"
  rest=("${t[@]:$((i + 1))}")
  flags=" ${rest[*]} "
  letters=""
  pos=()
  for a in "${rest[@]}"; do
    [ "$a" = -- ] && break
    case "$a" in
      --*) ;;
      -[a-zA-Z]*) letters+="${a#-}" ;;
      *) pos+=("$a") ;;
    esac
  done
  on_main() { [ "$(git -C "${dir:-.}" branch --show-current 2> /dev/null)" = main ]; }
  case "$sub" in
    push | clean) reason="git $sub" ;;
    merge | rebase) on_main && reason="git $sub on main" ;;
    reset)
      if [[ "$flags" == *" --hard "* ]]; then
        reason="git reset --hard (discards work)"
      elif on_main; then
        reason="git reset on main"
      fi
      ;;
    branch)
      if [[ "$letters" == *D* ]] || { [[ "$letters" == *d* || "$flags" == *" --delete "* ]] && [[ "$letters" == *f* || "$flags" == *" --force "* ]]; }; then
        reason="git branch force delete"
      elif [[ "$letters" == *M* ]]; then
        for p in "${pos[@]}"; do is_main "$p" && reason="git branch -M onto main"; done
      elif [[ "$letters" == *f* || "$flags" == *" --force "* ]]; then
        is_main "${pos[0]:-}" && reason="git branch -f main"
      fi
      ;;
    tag) [[ "$letters" == *f* || "$flags" == *" --force "* ]] && reason="git tag -f (moves a tag)" ;;
    update-ref) is_main "${pos[0]:-}" && reason="git update-ref main" ;;
    switch) [[ "$letters" == *C* || "$flags" == *" --force-create "* ]] && is_main "${pos[0]:-}" && reason="git switch -C main" ;;
    checkout)
      if [[ "$flags" == *" . "* ]]; then
        reason="git checkout . (discards worktree changes)"
      elif [[ "$letters" == *B* ]] && is_main "${pos[0]:-}"; then
        reason="git checkout -B main"
      fi
      ;;
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
