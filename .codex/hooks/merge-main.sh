#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf 'Usage: bash .codex/hooks/merge-main.sh [--dry-run] {--ff-only|--no-ff} BRANCH EXPECTED_MAIN REVIEWED_TIP\n'
}

fail() {
  printf 'merge-main.sh: %s\n' "$1" >&2
  exit 1
}

if [[ ${1:-} = --help || ${1:-} = -h ]]; then
  usage
  exit 0
fi
dry_run=false
if [[ ${1:-} = --dry-run ]]; then
  dry_run=true
  shift
fi
if [[ $# -ne 4 || ( $1 != --ff-only && $1 != --no-ff ) ]]; then
  usage >&2
  exit 2
fi
mode=$1
branch=$2
expected_main=$3
reviewed_tip=$4

[[ $(git symbolic-ref --quiet HEAD) = refs/heads/main ]] || fail 'check out main first'
working_tree=$(git status --porcelain)
[[ -z $working_tree ]] || fail 'the working tree must be clean'
if git rev-parse --verify --quiet MERGE_HEAD >/dev/null; then
  fail 'a merge is already in progress'
fi

main_tip=$(git rev-parse --verify refs/heads/main)
[[ $main_tip = "$expected_main" ]] || fail 'main moved; rerun the preflight checks'
branch_ref=$(git rev-parse --symbolic-full-name --verify --end-of-options "$branch") ||
  fail 'specify one unambiguous local branch'
[[ $branch_ref = "refs/heads/$branch" ]] || fail 'specify one unambiguous local branch'
branch_tip=$(git rev-parse --verify "$branch_ref")
[[ $branch_tip = "$reviewed_tip" ]] || fail 'the branch moved; review it again before merging'

count=$(git rev-list --count "$main_tip..$branch_tip")
[[ $mode = --ff-only && $count -eq 1 || $mode = --no-ff && $count -gt 1 ]] ||
  fail 'use --ff-only for one new commit and --no-ff for two or more'

if $dry_run; then
  printf 'Ready to merge %s with %s.\n' "$branch" "$mode"
  exit 0
fi

# Git must still use the reviewed tip if the branch moves after the check.
if [[ $mode = --no-ff ]]; then
  exec git merge --no-ff -m "Merge branch '$branch'" "$branch_tip"
fi
exec git merge --ff-only "$branch_tip"
