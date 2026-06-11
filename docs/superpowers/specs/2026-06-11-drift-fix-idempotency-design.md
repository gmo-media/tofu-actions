# 設計書: drift-fix-claude の冪等化（既存PRスキップ）

- 日付: 2026-06-11
- 対象アクション: `drift-fix-claude/action.yaml`
- スコープ: 重複PRの防止（冪等性）のみ

## 背景と課題

`gmo-media/tofu-actions` には、Tofu/Terraform の構成コードと実機（実インフラ）の
差分（drift）を検出し、Slack へ通知し、Claude Code が差分を吸収する PR を自動作成する
フローが既に実装されている。

- 差分検出: `plan/action.yaml`（`has-diff` 出力）
- 通知: `notify-drift/action.yaml`（Slack incoming-webhook）
- 自動修正PR: `drift-fix-claude/action.yaml`（Claude Code が `.tf` を実機状態へ更新し PR 作成）
- オーケストレーション: `.github/workflows/quickstart-drift-check.yaml`
  （`workflow_call`、cron は呼び出し側 `examples-workflows/drift-check.yaml` で毎日 0:00 UTC）

### 課題

`drift-fix-claude` が作成するブランチ名はタイムスタンプ付き
（`fix-drift-<dir>-$(date +%Y%m%d-%H%M%S)`）であり、既存 PR の有無を確認しない。
そのため drift が解消されないまま cron が毎日走ると、**同一 dir の同一 drift に対して
PR が毎日量産される**。infra チームのレビュー負荷が増大する。

## ゴール / 非ゴール

### ゴール
- `drift-fix-claude` を**冪等**にする。すなわち、ある dir に対して **open 中**の
  drift-fix PR が既に存在する場合、（高コストな Claude 実行を含む）以降の処理を
  スキップし、重複 PR を作らない。

### 非ゴール（今回スコープ外）
- シークレット名不一致（`quickstart-drift-check.yaml` の `secrets.claude-api-key` と
  宣言 `anthropic-api-key` の不整合）の修正
- Claude が plan を "No changes" にできなかった場合の No-change ゲート
- PR のラベル付与 / assign 等の追跡性向上
- Slack 通知文言の変更（後述「既知の制約」参照）

## 採用方針

**案1: アクション内ガード + ヘッドブランチパターンで判定。**

判定ロジックを `drift-fix-claude/action.yaml` の内部に閉じることで、
「このアクションを呼べば冪等」という性質が呼び出し側に漏れない。
`quickstart-drift-check.yaml` などの呼び出し側ワークフローは無変更。

### 検討した代替案
- 案2: PR 本文の隠しマーカー（またはラベル）で判定 — ブランチ命名に依存せず最も堅牢だが、
  GitHub 検索のインデックス遅延の影響を受けうる／部品が増える。
- 案3: ワークフロー側でゲート — 挙動は読みやすいが、アクション自体は非冪等のままで、
  利用する全ワークフローでゲートを複製する必要がありカプセル化されない。

案1を採用。

## アーキテクチャ / コンポーネント境界

- 新規アクションは作らず、既存 `drift-fix-claude/action.yaml` を拡張する。
- アクション**先頭に `guard` ステップを1つ追加**し、既存の全ステップ
  （`config`, `branch`, save plan, setup claude, fix drift, commit, create-pr）に
  `if: steps.guard.outputs.skip != 'true'` を付与してゲートする。
  - `guard` を最初に置くことで、スキップ時は `read-config` の実行も省ける。
- 追加アウトプット:
  - `skipped`: `true` / `false`（スキップしたか）
  - `existing-pr-number`: スキップ時に検出した既存 PR 番号（未スキップ時は空）
  - 既存の `pr-url` / `branch-name` はスキップ時は空（呼び出し側は現状未使用）。

## データフロー

```
plan (has-diff=true)
  └─ drift-fix-claude 呼び出し (dir, plan, github-token, ...)
       └─ guard: open PR を列挙し、この dir の drift-fix ブランチに一致する PR があるか?
            ├─ あり → skip=true
            │         → 以降の全ステップ no-op
            │         → outputs: skipped=true, existing-pr-number=#N
            │         → job summary に "Skipped ... open PR #N already exists"
            └─ なし → skip=false
                      → 従来どおり branch → Claude → commit/push → PR 作成
```

## 判定ロジック（核心）

`guard` ステップ（`shell: bash`、`env.GH_TOKEN: ${{ inputs.github-token || github.token }}`
を既存 `create-pr` ステップと揃えて使用）は以下を行う:

1. `dir` を sanitize: `/` を `-` に置換（branch ステップと同一の変換）。
2. open PR を列挙:
   - `gh pr list --state open --base <base-branch> --limit 200 --json number,headRefName`
3. **standalone の `jq`**（`gh ... | jq`）で headRefName を正規表現マッチ:
   - パターン: `^fix-drift-<sanitized-dir>-[0-9]{8}-[0-9]{6}$`
   - `gh pr list --jq` ではなく独立した `jq` を使うことで、同じ判定式を
     単体テスト（後述）でサンプル JSON に対して再利用できる。
4. マッチする PR があれば最初の番号を `existing-pr-number` とし、`skip=true`。
   - `$GITHUB_STEP_SUMMARY` にスキップ理由（既存 PR 番号付き）を出力。
5. マッチがなければ `skip=false`。

### 取り違え防止の根拠

ブランチ名のタイムスタンプは `%Y%m%d-%H%M%S`（= 8桁数字 + `-` + 6桁数字）で、
必ず**数字始まり**。よってパターン末尾の `-[0-9]{8}-[0-9]{6}$` により、

- dir `prod/foo` のブランチ `fix-drift-prod-foo-20260611-120000` は
  dir `prod/foo/bar` のパターン `^fix-drift-prod-foo-bar-[0-9]{8}-[0-9]{6}$` に**一致しない**
  （`foo-` の後に `bar` ではなく数字が来るため）。
- 逆方向も同様に一致しない（`prod-foo` のパターンは `foo-` の後に8桁数字を要求するが、
  `prod/foo/bar` のブランチは `foo-bar-...` で数字始まりでない）。

### 結合点（要メンテナンス）

`branch` ステップのブランチ命名（`date +%Y%m%d-%H%M%S`）と `guard` の正規表現は
**対になっている**。どちらかを変更したら他方も追従する必要があるため、両ステップに
相互参照コメントを入れる。

## エラーハンドリング / エッジケース

- **`gh pr list` 失敗時**: `guard` ステップを失敗させる（fail-fast）。重複作成も無言スキップも
  せず問題を表面化させる。翌 cron で再試行され、既存の `failure()` Slack 通知でも拾われる。
- **マージ済み PR のブランチ残存**: open のみで判定するため、マージ後に同 dir で新たな drift が
  出れば別タイムスタンプの新ブランチで作成され、push 衝突は起きない。
- **トークン権限**: PR 列挙には `pull-requests: read` が必要。
  `quickstart-drift-check.yaml` は既に `pull-requests: write` を付与済みで、
  `inputs.github-token || github.token` により同一リポジトリでは動作する。
- **`gh pr list` のページング**: デフォルト上限は 30 件。drift-fix PR が埋もれないよう
  `--limit 200` を指定する（必要に応じて調整可能とコメント）。

## 既知の制約（ドキュメント明記）

- **sanitize 衝突**: dir `prod/foo`（slash）と dir `prod-foo`（literal dash）は同一の
  sanitized 文字列 `prod-foo` になり、理論上取り違える。実運用ではほぼ発生しないため許容する。
- **Slack 通知文言の不一致（スコープ外）**: `notify-drift` は `drift-fix-claude` と独立に
  実行されるため、スキップ時も Slack には「Claude is on the way to creating a PR...」と
  表示され続ける（実際には既存 PR があるためスキップ）。今回は冪等性のみがスコープのため
  通知文言は変更しない。

## テスト戦略

複合（composite）YAML アクション全体の単体テストは困難なため、**最もリスクが高い
ブランチ一致判定ロジック**を切り出して検証する。

1. **判定ロジックの単体テスト**（GitHub 実環境不要、TDD 可能）:
   - 判定（sanitize + 正規表現マッチ）を小さな bash スクリプトまたは jq 式として表現し、
     サンプルの open-PR ブランチ一覧を入力に、期待する match / no-match をアサートする。
   - ケース:
     - 同一 dir・タイムスタンプ違いのブランチ → match
     - `prod/foo` と `prod/foo/bar` の相互非マッチ
     - 無関係ブランチ（`feature-x`, `renovate/...`）→ no-match
     - PR が 0 件 → no-match（skip=false）
2. **ワークフローレベルの手動検証**（手順を文書化）:
   - drift-check を2回連続実行し、
     (1) 初回は PR 作成、
     (2) 2回目はスキップ（job summary に "Skipped ... open PR #N already exists"）
     を確認する。

## 影響範囲

- 変更: `drift-fix-claude/action.yaml`（guard ステップ追加、各ステップに `if` 付与、outputs 追加）
- 追加: 判定ロジックの単体テスト用スクリプト/フィクスチャ
- 無変更: `quickstart-drift-check.yaml`, `notify-drift/action.yaml`, `plan/action.yaml` ほか
