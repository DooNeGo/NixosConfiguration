#!/usr/bin/env bash
set -euo pipefail

hooks=$(cd -- "$(dirname -- "$0")" && pwd)
repo=$(mktemp -d)
trap 'rm -rf -- "$repo"' EXIT
cd -- "$repo"
git init --quiet --initial-branch=main
git config user.name 'Merge test'
git config user.email merge-test@example.invalid
git config commit.gpgSign false
git config merge.gpgSign false
git config core.hooksPath /dev/null
git commit --quiet --allow-empty -m base
base=$(git rev-parse HEAD)

check_git_guard() {
  local expected=$1 command=$2 actual=0
  jq -nc --arg cwd "$repo" --arg command "$command" '{cwd:$cwd,tool_input:{command:$command}}' |
    bash "$hooks/guard-git.sh" || actual=$?
  if [[ $actual != "$expected" ]]; then
    printf 'Expected Git guard exit %s, got %s for %s\n' "$expected" "$actual" "$command" >&2
    return 1
  fi
}

git switch --quiet --create topic
check_git_guard 2 'git switch main && git merge --no-ff topic'
check_git_guard 0 'git merge --ff-only main'
check_git_guard 0 "git merge --no-ff main -m 'Merge main (tested); local only'"
check_git_guard 0 'git merge --no-ff main -m "Merge main (tested); local only"'
check_git_guard 2 'git merge --no-ff main -m "Merge main (tested)" && git status'
check_git_guard 2 "git merge --no-ff main -m \"\$(git switch main)\""
git commit --quiet --allow-empty -m first
git commit --quiet --allow-empty -m second
reviewed=$(git rev-parse HEAD)
git commit --quiet --allow-empty -m third
updated=$(git rev-parse HEAD)
git switch --quiet main
check_git_guard 2 'git merge --no-ff topic'

if output=$(bash "$hooks/merge-main.sh" --no-ff topic "$base" "$reviewed" 2>&1); then
  printf 'The stale merge unexpectedly succeeded.\n' >&2
  exit 1
fi
[[ $output = *'the branch moved'* ]]
[[ $(git rev-parse HEAD) = "$base" ]]
[[ -z $(git status --porcelain) ]]

bash "$hooks/merge-main.sh" --no-ff topic "$base" "$updated"
[[ $(git rev-parse HEAD^2) = "$updated" ]]
merged=$(git rev-parse HEAD)

git switch --quiet --create release+fix
git commit --quiet --allow-empty -m fix
fix=$(git rev-parse HEAD)
git switch --quiet main
bash "$hooks/merge-main.sh" --ff-only release+fix "$merged" "$fix"
[[ $(git rev-parse HEAD) = "$fix" ]]
printf 'Guarded merge tests passed.\n'
