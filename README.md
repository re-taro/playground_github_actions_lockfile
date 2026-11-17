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
| `main` | なし | ok | lockfile の SHA (`11bd719`) で実行 | ✅ success。`11bd719` を取得 |
| `case/1a-workflow-ref-changed` | workflow の `uses:` だけ `v4.2.1` に | `ref-changed`, `stale` | missing pin で失敗 | ❌ **startup_failure**。`Invalid lockfile: The lockfile is missing actions/checkout@v4.2.1` |
| `case/1b-workflow-new-action` | workflow に `actions/setup-node@v4.4.0` を追加 | `not-pinned` | missing pin で失敗 | ❌ **startup_failure**。`Invalid lockfile: The lockfile is missing actions/setup-node@v4.4.0` |
| `case/2a-lockfile-ref-changed` | lockfile の ref だけ `v4.2.1` に (SHA も v4.2.1 のもの) | `ref-changed`, `stale` | missing pin で失敗 | ❌ **startup_failure**。`Invalid lockfile: The lockfile is missing actions/checkout@v4.2.2` |
| `case/2b-lockfile-older-commit` | lockfile の SHA を `v4.2.2` の親コミットに | `tag-commit-mismatch` | **古いコミット (`e3d2460`) で実行される** | ✅ success ⚠️ **`e3d2460` (古いコミット) で実行された** |
| `case/2c-lockfile-unrelated-commit` | lockfile の SHA を履歴外のコミットに | `unreachable-pin` | 実行時に拒否 | ❌ failure。Set up job で `Unable to resolve action actions/checkout@v4.2.2, unable to find version 436c656…` (step は 1 つも実行されない) |
| `case/3-lockfile-stale-entry` | lockfile に未使用エントリを追加 | `stale` | 影響なしで成功 | ✅ success。影響なし |
| `case/4-unonboarded-workflow` | lockfile 未登録の workflow `probe-unonboarded.yml` を追加 | `not-pinned` | lockfile を使わずタグ解決で実行 (Require lockfile ポリシーなし) | ✅ success。`probe-unonboarded` は `Using locked action versions` が出ず、タグ解決で実行 |

結果は `push` / `pull_request` (PR #1〜#7) のどちらでも同一。
`pull_request` では merge commit 上の lockfile (= PR 側の変更を含むもの) が使われる (2b で確認)。

### まとめ

1. workflow が参照する `owner/repo@ref` が lockfile に無い → **run 自体が起動しない** (startup_failure / `Invalid lockfile`)。workflow 側・lockfile 側どちらの変更でも同じ
2. エントリはあるが SHA が取得できない → Set up job で失敗
3. エントリがあり SHA がタグの履歴内 → **lockfile の SHA で普通に実行される** (実行時の検知なし。verify とレビューだけが防御)
4. workflow が lockfile 未登録 → lockfile を使わず従来どおりタグ解決 (Require lockfile ポリシーなしの場合)

## Require lockfile ポリシーを有効にした場合

リポジトリの Settings → Actions → Policies で作成 (UI のみ。公開 REST スキーマには rule type が未掲載)。
API 上は `{"type": "require_lockfile"}`、`enforcement: active`、`workflow_path.include: ["~ALL"]`。

`workflow_dispatch` / `pull_request` (rerun・reopen) で再実行した結果:

| ブランチ | ポリシーなし | ポリシーあり |
|---|---|---|
| `main` | ✅ success | ✅ success |
| `case/1a`・`1b`・`2a` | ❌ startup_failure (`Invalid lockfile`) | ❌ 変化なし。`workflow_dispatch` は API が 422 (`failed to parse workflow: Invalid dependency lockfile ...`) で拒否 |
| `case/2b-lockfile-older-commit` | ✅ `e3d2460` で実行 | ✅ **変化なし。古いコミットで実行される** |
| `case/2c-lockfile-unrelated-commit` | ❌ Set up job で失敗 | ❌ 変化なし |
| `case/3-lockfile-stale-entry` | ✅ success | ✅ 変化なし |
| `case/4` の `probe-unonboarded.yml` | ✅ タグ解決で実行 | ❌ **startup_failure**: `Workflow is not in the repository's lockfile. Run gh actions-lock ...` |

ポリシーが変えるのは「lockfile 未登録の workflow が lockfile なしで動く」ケースだけ。
登録済み workflow の不整合はポリシーなしでも実行時に弾かれ、2b (タグ履歴内の古いコミットへの書き換え) はポリシーがあっても防げない。

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
