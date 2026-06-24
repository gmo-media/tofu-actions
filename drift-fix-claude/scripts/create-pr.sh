#!/usr/bin/env bash
# Create the drift-fix pull request, or update the existing one when the
# guard re-ran the fix on its branch (MODE=update). Unverified fixes
# (VERDICT=draft-pr) become/stay a draft PR with a warning so a human can
# finish the fix; the idempotency guard still sees the open PR and keeps
# later cron runs from re-running Claude while the PR stays valid.
#
# Env:    GH_TOKEN, DIR, TF_BINARY, BASE_BRANCH, BRANCH_NAME, VERDICT,
#         MODE, EXISTING_PR_NUMBER (only when MODE=update),
#         VERIFY_PLAN_TXT (set by verify-drift-resolved.sh via GITHUB_ENV)
# Reads:  "$VERIFY_PLAN_TXT" (written by verify-drift-resolved.sh)
# Writes: pr-url / summary to GITHUB_OUTPUT
set -euo pipefail

: "${DIR:?DIR is required}"
: "${TF_BINARY:?TF_BINARY is required}"
: "${BASE_BRANCH:?BASE_BRANCH is required}"
: "${BRANCH_NAME:?BRANCH_NAME is required}"
: "${VERDICT:?VERDICT is required}"
: "${MODE:?MODE is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"
: "${VERIFY_PLAN_TXT:?VERIFY_PLAN_TXT is required (set by verify-drift-resolved.sh via GITHUB_ENV)}"

# Check if changes were pushed. In update mode the PR branch always exists
# on origin, so this never triggers there; pushes are guaranteed by the
# verdict gate (pr / draft-pr implies a working-tree diff was committed).
if ! git rev-parse --verify "origin/$BRANCH_NAME" >/dev/null 2>&1; then
  echo "No changes were pushed, skipping PR creation"
  exit 0
fi

BODY_FILE=/tmp/pr-body.md
: > "$BODY_FILE"
DRAFT_FLAG=()

if [ "$VERDICT" = "draft-pr" ]; then
  TITLE="⚠️ インフラドリフト自動修正 $DIR（未検証）"
  DRAFT_FLAG=(--draft)
  VERIFIED_LINE="- ⚠️ 未検証: \`$TF_BINARY plan\` でまだ変更が表示されます（上記参照）"
  {
    echo "## ⚠️ 検証失敗"
    echo
    echo "自動修正後も、\`$TF_BINARY plan\` で変更が残っています。"
    echo "マージ前に人間が対応を完了させる必要があります。"
    echo "残りのプラン出力（40000文字に切り詰め。完全な出力はワークフロージョブサマリーにあります）:"
    echo
    # Indented code block: unlike a ``` fence, plan output that
    # itself contains backticks cannot break out and render as
    # markdown -- but only while EVERY emitted line stays indented.
    # head -c cuts on a byte boundary, so it can leave a final partial
    # line with no trailing newline; awk treats that fragment as a
    # record and print appends a newline, so the last line is still
    # indented and terminated (sed would leave it unterminated).
    head -c 40000 "$VERIFY_PLAN_TXT" | awk '{ print "    " $0 }'
    echo
    echo
  } >> "$BODY_FILE"
else
  TITLE="🔧 インフラドリフト自動修正 $DIR"
  VERIFIED_LINE="- 検証済み: 修正後に \`$TF_BINARY plan\` で「変更なし」が表示されました"
fi

# Path must match step 4 in .claude/skills/fix-drift/SKILL.md
CLAUDE_BODY_FILE=/tmp/pr-body-claude.md

cat >> "$BODY_FILE" <<EOF
## 🤖 ドリフト自動修正

このPRは \`$DIR\` のインフラドリフトを自動修正する試みです。

EOF

if [ -s "$CLAUDE_BODY_FILE" ]; then
  cat "$CLAUDE_BODY_FILE" >> "$BODY_FILE"
  echo >> "$BODY_FILE"
else
  cat >> "$BODY_FILE" <<EOF
### 何が起きたのか？
ドリフトチェック中にインフラドリフトが検出されました。実際のインフラの状態が
Terraform/OpenTofu 設定ファイルで定義された状態と異なっています。

### このPRの内容
- 現在の実インフラの状態に合わせて .tf 設定ファイルを更新
- 最小限の非破壊的な変更のみを実施
EOF
fi

cat >> "$BODY_FILE" <<EOF

### 検証状態
$VERIFIED_LINE

### レビューチェックリスト
- [ ] 変更がインフラの状態を正しく反映しているか確認
- [ ] ドリフトした値のみが更新されているか確認
- [ ] 不要なデフォルト値が追加されていないか確認
- [ ] 変更が最小限かつ非破壊的であることを確認

---
*このPRはドリフト修正ワークフローによって Claude Code を使用して自動生成されました。*
EOF

if [ "$MODE" = "update" ]; then
  : "${EXISTING_PR_NUMBER:?EXISTING_PR_NUMBER is required when MODE=update}"

  # Sync the PR's look to the latest verification result: title, body and
  # draft/ready state always reflect the current verdict.
  gh pr edit "$EXISTING_PR_NUMBER" --title "$TITLE" --body-file "$BODY_FILE"

  _pr_view=$(gh pr view "$EXISTING_PR_NUMBER" --json isDraft,url)
  IS_DRAFT=$(echo "$_pr_view" | jq -r '.isDraft')
  PR_URL=$(echo "$_pr_view" | jq -r '.url')
  if [ "$VERDICT" = "pr" ] && [ "$IS_DRAFT" = "true" ]; then
    gh pr ready "$EXISTING_PR_NUMBER"
  elif [ "$VERDICT" = "draft-pr" ] && [ "$IS_DRAFT" = "false" ]; then
    gh pr ready --undo "$EXISTING_PR_NUMBER"
  fi

  if [ "$VERDICT" = "pr" ]; then
    RESULT_LINE="修正が検証済みです: \`$TF_BINARY plan\` で「変更なし」が表示されています。"
  else
    RESULT_LINE="修正はまだ未検証です: \`$TF_BINARY plan\` で残りの変更が表示されています（PRの説明を参照）。"
  fi
  gh pr comment "$EXISTING_PR_NUMBER" --body "🤖 このブランチ上で前回の自動修正以降に \`$DIR\` で新たなドリフトが検出されたため（インフラが再び変更されました）、自動修正を再実行しました。$RESULT_LINE"

  echo "Pull request updated: $PR_URL"
else
  PR_URL=$(gh pr create \
      --title "$TITLE" \
      --base "$BASE_BRANCH" \
      --head "$BRANCH_NAME" \
      --body-file "$BODY_FILE" \
      "${DRAFT_FLAG[@]}")

  echo "Pull request created: $PR_URL"
fi
echo "pr-url=$PR_URL" >> "$GITHUB_OUTPUT"
if [ "$VERDICT" = "draft-pr" ]; then
  echo "summary=Claude opened a draft drift-fix PR for \`$DIR\` (verification failed — needs a human): $PR_URL" >> "$GITHUB_OUTPUT"
else
  echo "summary=Claude opened a verified drift-fix PR for \`$DIR\`: $PR_URL" >> "$GITHUB_OUTPUT"
fi
