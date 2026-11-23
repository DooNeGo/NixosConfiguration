#!/usr/bin/env bash
# Block Git commands reserved for the owner and force pushes.
input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<< "$input") || {
  echo "guard-git.sh: cannot read the hook input with jq" >&2
  exit 2
}
cwd=$(jq -r '.cwd // empty' <<< "$input")
cwd=${cwd:-$PWD}

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
        argument=${t[$((i + 1))]:-}
        case "$argument" in
          /*) dir=$argument ;;
          ?*) dir="$dir/$argument" ;;
        esac
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
    push)
      for a in "${rest[@]}"; do
        case "$a" in
          +* | --force | --force-with-lease | --force-with-lease=* | --mirror)
            echo "Force pushes are prohibited in this repository." >&2
            exit 2
            ;;
        esac
      done
      if [[ "$letters" == *f* ]]; then
        echo "Force pushes are prohibited in this repository." >&2
        exit 2
      fi
      reason="git push"
      ;;
    clean) reason="git clean" ;;
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
      elif [[ "$letters" == *[dMm]* || "$flags" == *" --delete "* || "$flags" == *" --move "* ]]; then
        for p in "${pos[@]}"; do is_main "$p" && reason="git branch move or delete involving main"; done
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
printf '%s requires the owner to authorize and run it in their terminal.\n' "$reason" >&2
exit 2
