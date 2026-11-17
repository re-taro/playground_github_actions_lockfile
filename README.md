# playground_github_actions_lockfile

GitHub Actions の workflow dependency lockfile (`.github/workflows/actions.lock`) と workflow 定義がずれているとき、
**GitHub Actions 自体が実行時にどう振る舞うか** を検証する。

- lockfile を正として実行するのか / 定義 (`uses:`) を正とするのか / そもそも実行されないのか
- 失敗するならどのタイミングか (Set up job か、該当 step か)
- `push` と `pull_request` で挙動が変わるか (どちらの lockfile が使われるか)

## 構成

| ファイル | 役割 |
|---|---|
| `.github/workflows/probe.yml` | 検証対象。`before-action` (run) → `actions/checkout@v4.2.2` → `after-action` (run) |
| `.github/workflows/verify.yml` | `gh actions-lock --verify`。lockfile の改変に影響されないよう action を使わずに checkout する |
| `.github/workflows/actions.lock` | `gh actions-lock --no-narrow` で生成 (main) |

`probe` の `before-action` step が実行されたかどうかで、失敗が Set up job 時点か step 到達時点かを判別する。
実際に実行されたコミットは Set up job ログの `Download action repository '...' (SHA:...)` で確認する。

参考 SHA (`actions/checkout`):

| | SHA |
|---|---|
| `v4.2.2` | `11bd71901bbe5b1630ceea73d27597364c9af683` |
| `v4.2.2` の親 (タグ履歴内の古いコミット) | `e3d2460bbb42d7710191569f88069044cfb9d8cf` |
| `v4.2.1` | `eef61447b9ff4aafe5dcd4e0bbf5d482be7e7871` |
| 履歴外 (`actions/setup-node` のコミット) | `436c65619b12c9e37ff20a4700145cc387898a7d` |

## ケース

各ケースは main から 1 コミットだけ進めたブランチ。`--verify` の列はローカルで確認済み (gh-actions-lock v0.4.1)。

| ブランチ | 変更 | `--verify` | 実行時の予想 | 結果 |
|---|---|---|---|---|
| `main` | なし | ok | lockfile の SHA (`11bd719`) で実行 | |
| `case/1a-workflow-ref-changed` | workflow の `uses:` だけ `v4.2.1` に | `ref-changed`, `stale` | missing pin で失敗 | |
| `case/1b-workflow-new-action` | workflow に `actions/setup-node@v4.4.0` を追加 | `not-pinned` | missing pin で失敗 | |
| `case/2a-lockfile-ref-changed` | lockfile の ref だけ `v4.2.1` に (SHA も v4.2.1 のもの) | `ref-changed`, `stale` | missing pin で失敗 | |
| `case/2b-lockfile-older-commit` | lockfile の SHA を `v4.2.2` の親コミットに | `tag-commit-mismatch` | **古いコミット (`e3d2460`) で実行される** | |
| `case/2c-lockfile-unrelated-commit` | lockfile の SHA を履歴外のコミットに | `unreachable-pin` | 実行時に拒否 | |
| `case/3-lockfile-stale-entry` | lockfile に未使用エントリを追加 | `stale` | 影響なしで成功 | |
| `case/4-unonboarded-workflow` | lockfile 未登録の workflow `probe-unonboarded.yml` を追加 | `not-pinned` | lockfile を使わずタグ解決で実行 (Require lockfile ポリシーなし) | |

## 手順

1. GitHub に `re-taro/playground_github_actions_lockfile` を作成し、remote を追加する

   ```sh
   git remote add origin https://github.com/re-taro/playground_github_actions_lockfile.git
   ```

2. push する (`push` イベントの run)

   ```sh
   scripts/push-all.sh
   ```

3. PR を作る (`pull_request` イベントの run)

   ```sh
   scripts/open-prs.sh
   ```

4. 全 run の完了後に結果を収集する (`results/` に出力)

   ```sh
   scripts/collect.sh                      # 全ブランチ
   scripts/collect.sh case/2b-lockfile-older-commit   # 個別
   ```
