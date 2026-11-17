#!/usr/bin/env bash
# main と全 case/* ブランチを push する (push イベントの run が起動する)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

git push -u origin main
for b in $(git branch --format='%(refname:short)' | grep '^case/' | sort); do
  git push -u origin "$b"
done
