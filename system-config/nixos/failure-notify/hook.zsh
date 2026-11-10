#!/usr/bin/env zsh
# Open failure-notify records in an interactive zsh (system-config/nixos/failure-notify.nix defines _failure_notify_dir).
# Open records are listed when a shell starts (not in every tmux pane) and a new one is printed before the next
# prompt, once per shell. Only builtins: this runs before every prompt.

zmodload zsh/datetime
typeset -gA _failure_notify_seen
_failure_notify_check() {
  local quiet=$1 f lines key stamp
  [[ -n $_failure_notify_dir ]] || return
  for f in $_failure_notify_dir/*(N.); do
    lines=("${(@f)$(<$f)}")
    (( $#lines >= 4 )) || continue
    (( lines[2] == 0 || lines[2] > EPOCHSECONDS )) || continue
    key="$f ${lines[1]}"
    [[ -z ${_failure_notify_seen[$key]} ]] || continue
    _failure_notify_seen[$key]=1
    [[ -z $quiet ]] || continue
    strftime -s stamp '%F %R' $lines[1]
    print -r -- $'\e[1;31m[failure]\e[0m '"${f:t} since $stamp: $lines[4] (dismiss: sudo failure-notify clear ${f:t})"
  done
}
_failure_notify_check ${TMUX:+quiet}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _failure_notify_check
