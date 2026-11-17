#!/usr/bin/env bash
# 各ブランチ × workflow × event の最新 run について、結論とログ中の重要な行を results/ に書き出す
#
# usage: scripts/collect.sh [branch...]   (省略時は main と全 case/*)
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
mkdir -p results

if [ $# -gt 0 ]; then
  branches=("$@")
else
  branches=(main $(git branch --format='%(refname:short)' | grep '^case/' | sort))
fi

pattern='Using locked action|lockfile|Download action repository|Getting action download info|BEFORE_ACTION_STEP_RAN|AFTER_ACTION_STEP_RAN|AFTER_NEW_ACTION_STEP_RAN|##\[error\]|missing pin|Unable to resolve|not allowed'

for b in "${branches[@]}"; do
  out="results/${b//\//_}.txt"
  {
    echo "################ $b"
    for wf in probe.yml probe-unonboarded.yml verify.yml; do
      for ev in push pull_request; do
        run=$(gh run list -R "$repo" -b "$b" -w "$wf" -e "$ev" -L 1 \
          --json databaseId,status,conclusion,headSha,url 2>/dev/null | jq -c '.[0] // empty' || true)
        [ -z "$run" ] && continue
        id=$(jq -r .databaseId <<<"$run")
        echo
        echo "======== $wf / $ev"
        jq -r '"status=\(.status) conclusion=\(.conclusion) sha=\(.headSha[0:7])\n\(.url)"' <<<"$run"

        # job ごとの step 実行状況 (どこで落ちたか)
        gh api "repos/$repo/actions/runs/$id/jobs" \
          -q '.jobs[] | "  job: \(.name) conclusion=\(.conclusion)", (.steps[]? | "    step[\(.number)] \(.name): \(.conclusion)")' || true

        # job が作られずに失敗した場合などのアノテーション
        for jid in $(gh api "repos/$repo/actions/runs/$id/jobs" -q '.jobs[].id' 2>/dev/null); do
          gh api "repos/$repo/check-runs/$jid/annotations" \
            -q '.[] | "  annotation[\(.annotation_level)]: \(.message)"' 2>/dev/null || true
        done

        # startup_failure は job が作られず API でメッセージが取れないので、Web の annotations を取得する (public repo 前提)
        if [ "$(jq -r .conclusion <<<"$run")" = "startup_failure" ]; then
          curl -sL -H 'X-Requested-With: XMLHttpRequest' "https://github.com/$repo/actions/runs/$id/annotations_partial" \
            | sed -e 's/<[^>]*>/ /g' -e 's/&quot;/"/g' -e "s/&#39;/'/g" -e 's/&lt;/</g;s/&gt;/>/g;s/&amp;/\&/g' \
            | tr -s ' \n' | grep -v -E '^ *$|data-|<div|^ *>|Show (more|less)' | sed 's/^/  startup: /' || true
        fi

        echo "  --- log (filtered)"
        gh run view -R "$repo" "$id" --log 2>/dev/null \
          | grep -E "$pattern" | grep -v -E '^\S+\s+\S+\s+\S+\s+\^\[\[36;1m' | sed 's/^/  /' | head -40 || true
      done
    done
  } | tee "$out"
done
