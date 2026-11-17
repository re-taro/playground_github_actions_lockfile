#!/usr/bin/env bash
# 全 case/* ブランチから main への PR を作成する (pull_request イベントの run が起動する)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

for b in $(git branch --format='%(refname:short)' | grep '^case/' | sort); do
  if gh pr view "$b" --json number >/dev/null 2>&1; then
    echo "skip: PR already exists for $b"
    continue
  fi
  gh pr create --base main --head "$b" --title "$b" --body "$(git log -1 --format=%s "$b")"
done
