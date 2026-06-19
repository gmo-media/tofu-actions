#!/usr/bin/env bash
# No-change gate: deterministically verify Claude's fix by re-running plan
# and requiring "No changes". A remaining plan that would destroy and
# recreate (-/+ or +/-) a resource is never handed off, even as a draft PR.
# The verdict mapping lives in no-change-gate.sh.
#
# Env:    DIR, TF_BINARY, MODE, GH_TOKEN and EXISTING_PR_NUMBER
#         (the last three only matter on the update + resolved path below)
# Writes: verdict / fix-verified / summary (resolved only) to GITHUB_OUTPUT,
#         summary to GITHUB_STEP_SUMMARY, plan output (stdout+stderr) to
#         VERIFY_PLAN_TXT (reused by create-pr.sh for the draft PR body)
set -euo pipefail

: "${DIR:?DIR is required}"
: "${TF_BINARY:?TF_BINARY is required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Derive a per-DIR filename so concurrent matrix jobs don't clobber each other.
PLAN_SLUG="$(echo "$DIR" | tr '/' '-' | tr -dc 'a-zA-Z0-9._-' | sed 's/^[-.]*//')"
VERIFY_PLAN_TXT="${RUNNER_TEMP:-/tmp}/verify-plan-${PLAN_SLUG}.txt"
# Export for create-pr.sh (runs as a subsequent step in the same job).
echo "VERIFY_PLAN_TXT=$VERIFY_PLAN_TXT" >> "$GITHUB_ENV"

# git status --porcelain also catches newly created .tf files,
# unlike git diff (assumes init artifacts like .terraform/ are
# gitignored in the consumer repo, same as commit-and-push.sh).
if [ -n "$(git status --porcelain)" ]; then
  HAS_DIFF=true
else
  HAS_DIFF=false
fi

# Plan execution (flags, output capture) is shared with the guard's
# stale-PR detection; see scripts/run-verify-plan.sh.
set +e
"$SCRIPT_DIR/run-verify-plan.sh" "$VERIFY_PLAN_TXT"
PLAN_EXIT_CODE=$?
set -e

# Replacement detection: "# <addr> must be replaced" header comments and
# -/+ / +/- resource action lines. Create-only or destroy-only changes do
# not match; only a destroy-and-recreate of the same resource does.
if grep -qE '^[[:space:]]*(# .* must be replaced$|[-+]/[-+] resource )' "$VERIFY_PLAN_TXT"; then
  HAS_REPLACE=true
else
  HAS_REPLACE=false
fi

VERDICT=$("$SCRIPT_DIR/no-change-gate.sh" "$PLAN_EXIT_CODE" "$HAS_DIFF" "$HAS_REPLACE")
{
  echo "verdict=$VERDICT"
  if [ "$VERDICT" = "pr" ] || [ "$VERDICT" = "resolved" ]; then
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
    if [ "${MODE:-create}" = "update" ]; then
      # Drift resolved between the guard's plan and this verify (transient, or
      # fixed in the console): the existing PR's branch still plans clean and
      # stays a valid fix awaiting merge. create-pr only runs for pr/draft-pr,
      # so report the open PR here instead of "no PR needed" (which would
      # contradict it).
      : "${EXISTING_PR_NUMBER:?EXISTING_PR_NUMBER is required when MODE=update}"
      gh pr comment "$EXISTING_PR_NUMBER" --body "🤖 New drift was detected in \`$DIR\` and the automated fix was re-run, but no further changes were needed — this PR's branch already plans clean. Leaving the PR open for review."
      PR_URL=$(gh pr view "$EXISTING_PR_NUMBER" --json url -q .url)
      echo "Drift in \`$DIR\` was re-checked on open PR #$EXISTING_PR_NUMBER; its branch already resolves it (no new changes needed)." >> "$GITHUB_STEP_SUMMARY"
      echo "summary=Drift in \`$DIR\` was re-checked; open PR #$EXISTING_PR_NUMBER already resolves it: $PR_URL" >> "$GITHUB_OUTPUT"
    else
      echo "Drift in \`$DIR\` is already resolved; skipping PR creation." >> "$GITHUB_STEP_SUMMARY"
      echo "summary=Drift in \`$DIR\` was already resolved; no PR needed." >> "$GITHUB_OUTPUT"
    fi
    ;;
  draft-pr)
    {
      echo "Verification failed: plan still shows changes after the fix in \`$DIR\`; creating a draft PR."
      echo
      # Indented code block: unlike a ``` fence, plan output that
      # itself contains backticks cannot break out and render as
      # markdown.
      sed 's/^/    /' "$VERIFY_PLAN_TXT"
    } >> "$GITHUB_STEP_SUMMARY"
    ;;
  replace-fail)
    {
      echo "Verification failed: the plan after the fix in \`$DIR\` would destroy and recreate (-/+) resources; refusing to hand off a PR."
      echo
      # Indented code block: unlike a ``` fence, plan output that
      # itself contains backticks cannot break out and render as
      # markdown.
      sed 's/^/    /' "$VERIFY_PLAN_TXT"
    } >> "$GITHUB_STEP_SUMMARY"
    echo "Plan would replace resources in \`$DIR\`; refusing to create a PR."
    cat "$VERIFY_PLAN_TXT"
    exit 1
    ;;
  *)
    if [ "$PLAN_EXIT_CODE" = "2" ]; then
      echo "Claude made no changes but drift remains in \`$DIR\`." | tee -a "$GITHUB_STEP_SUMMARY"
    else
      echo "Verification plan failed in \`$DIR\` (exit code $PLAN_EXIT_CODE)." | tee -a "$GITHUB_STEP_SUMMARY"
    fi
    cat "$VERIFY_PLAN_TXT"
    exit 1
    ;;
esac
