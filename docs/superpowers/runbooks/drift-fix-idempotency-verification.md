# Runbook: drift-fix-claude 冪等化の手動検証

- 関連 spec: [../specs/2026-06-11-drift-fix-idempotency-design.md](../specs/2026-06-11-drift-fix-idempotency-design.md)
- 関連 plan: [../plans/2026-06-11-drift-fix-idempotency.md](../plans/2026-06-11-drift-fix-idempotency.md)

## 目的

同一 dir・未解消の drift に対して、`drift-fix-claude` が重複 PR を作らない（冪等である）ことを実環境で確認する。

## 前提

- 対象リポジトリで drift-check ワークフロー（`quickstart-drift-check.yaml` を呼び出すもの）が動作していること。
- 自動修正に必要なシークレット（`anthropic-api-key` または `claude-code-oauth-token`、および PR 作成用 `github-token`）が設定済みであること。
- いずれかの dir に未解消の drift が存在する（または意図的に作れる）こと。

## 単体テスト（前段の自動確認）

```bash
bash drift-fix-claude/tests/match-existing-pr.test.sh
```

`passed: 5, failed: 0` を確認する。CI では `shell-tests` ジョブで自動実行される。

## ワークフローレベルの手動検証

1. drift-check を実行する（cron 待ち、または手動トリガー）。
   - 期待: 対象 dir に対し `drift-fix-claude` が走り、`fix-drift-<dir>-<timestamp>` ブランチで PR が1件作成される。
   - その実行ログで `guard` ステップが `skip=false` になっていること。
2. 作成された PR を**マージせず open のまま**にし、drift も未解消のまま、drift-check をもう一度実行する。
   - 期待: 同 dir の `drift-fix-claude` 実行で `guard` がスキップを判定し、Claude 実行・commit・PR 作成のステップがすべて skip される。
   - Job summary に `Skipped drift fix for \`<dir>\`: open PR #<N> already exists.` が出力されること。
   - **新しい PR が作成されないこと**（PR は1件のままであること）。
3. （任意）1 の PR をマージまたはクローズしてから drift-check を再実行すると、open PR が無いため再び PR が作成される（別タイムスタンプのブランチ）ことを確認する。

## 既知の制約（spec より）

- Slack 通知（`notify-drift`）は `drift-fix-claude` と独立に走るため、スキップ時も "Claude is on the way to creating a PR..." と表示され続ける（今回スコープ外）。
- dir `prod/foo`（slash）と dir `prod-foo`（literal dash）は同一の sanitized 文字列になり理論上取り違えるが、実運用ではほぼ発生しないため許容する。
