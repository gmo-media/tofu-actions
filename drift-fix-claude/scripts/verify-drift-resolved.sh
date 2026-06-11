#!/usr/bin/env bash
# No-change gate: deterministically verify Claude's fix by re-running plan
# and requiring "No changes". The verdict mapping lives in no-change-gate.sh
# (shared with tests/no-change-gate.test.sh).
#
# Env:    DIR, TF_BINARY
# Writes: verdict / fix-verified to GITHUB_OUTPUT, summary to
#         GITHUB_STEP_SUMMARY, plan output (stdout+stderr) to
#         /tmp/verify-plan.txt (reused by create-pr.sh for the draft PR body)
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# git status --porcelain also catches newly created .tf files,
# unlike git diff (assumes init artifacts like .terraform/ are
# gitignored in the consumer repo, same as commit-and-push.sh).
if [ -n "$(git status --porcelain)" ]; then
  HAS_DIFF=true
else
  HAS_DIFF=false
fi

# tofu supports -concise to drop the refresh noise; terraform does not
CONCISE_FLAG=""
case "$TF_BINARY" in
  *tofu*) CONCISE_FLAG="-concise" ;;
esac

set +e
# -no-color: the output is embedded in the PR body / job summary.
# 2>&1: plan errors go to stderr; capture them so the fail branch and
# the draft PR body are not empty on exit code 1.
(cd "$DIR" && "$TF_BINARY" plan -no-color -lock-timeout=300s $CONCISE_FLAG -detailed-exitcode) > /tmp/verify-plan.txt 2>&1
PLAN_EXIT_CODE=$?
set -e

VERDICT=$("$SCRIPT_DIR/no-change-gate.sh" "$PLAN_EXIT_CODE" "$HAS_DIFF")
{
  echo "verdict=$VERDICT"
  if [ "$VERDICT" = "pr" ]; then
    echo "fix-verified=true"
  elif [ "$VERDICT" = "draft-pr" ]; then
    echo "fix-verified=false"
  else
    echo "fix-verified="
  fi
} >> "$GITHUB_OUTPUT"

case "$VERDICT" in
  pr)
    echo "Verified: plan shows no changes after the fix in \`$DIR\`." >> "$GITHUB_STEP_SUMMARY"
    ;;
  resolved)
    echo "Drift in \`$DIR\` is already resolved; skipping PR creation." >> "$GITHUB_STEP_SUMMARY"
    ;;
  draft-pr)
    {
      echo "Verification failed: plan still shows changes after the fix in \`$DIR\`; creating a draft PR."
      echo
      # Indented code block: unlike a ``` fence, plan output that
      # itself contains backticks cannot break out and render as
      # markdown.
      sed 's/^/    /' /tmp/verify-plan.txt
    } >> "$GITHUB_STEP_SUMMARY"
    ;;
  *)
    if [ "$PLAN_EXIT_CODE" = "2" ]; then
      echo "Claude made no changes but drift remains in \`$DIR\`." | tee -a "$GITHUB_STEP_SUMMARY"
    else
      echo "Verification plan failed in \`$DIR\` (exit code $PLAN_EXIT_CODE)." | tee -a "$GITHUB_STEP_SUMMARY"
    fi
    cat /tmp/verify-plan.txt
    exit 1
    ;;
esac
