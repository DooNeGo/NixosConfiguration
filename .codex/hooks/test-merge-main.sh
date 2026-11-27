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

git switch --quiet --create topic
git commit --quiet --allow-empty -m first
git commit --quiet --allow-empty -m second
reviewed=$(git rev-parse HEAD)
git commit --quiet --allow-empty -m third
updated=$(git rev-parse HEAD)
git switch --quiet main

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
