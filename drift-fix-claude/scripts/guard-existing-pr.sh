#!/usr/bin/env bash
# Decide whether to skip, create or update the drift fix for this dir.
#
# - Vertex AI inputs not configured         -> skip (auto-fix is optional;
#   (WIF pair or anthropic-vertex-project-id)  drift-check-only callers pass
#                                              through without a fix attempt)
# - No open drift-fix PR for this dir       -> mode=create (normal flow)
# - Open PR with human (non-bot) commits    -> skip (ownership moved to a human)
# - Open PR whose branch still plans clean  -> skip (the PR still resolves
#                                              the drift; repeated cron runs
#                                              must not pile up duplicates)
# - Open PR whose branch shows plan changes -> mode=update (new drift since
#   the PR was created, e.g. further manual changes in the cloud console;
#   re-run the fix on that branch and update the PR in place). The branch
#   is left checked out for the downstream steps, and its fresh plan output
#   is written to /tmp/plan.txt as Claude's input (the action's `plan` input
#   reflects the base branch, not this PR branch).
#
# The PR match logic lives in match-existing-pr.jq, the human-commit check
# in has-human-commits.jq, and the plan execution in run-verify-plan.sh
# (all shared with their unit tests under ../tests/).
#
# Env:    DIR, BASE_BRANCH, GH_TOKEN, TF_BINARY,
#         WORKLOAD_IDENTITY_PROVIDER, SERVICE_ACCOUNT,
#         ANTHROPIC_VERTEX_PROJECT_ID
# Writes: skip / mode / branch / existing-pr-number to GITHUB_OUTPUT,
#         summary line to GITHUB_STEP_SUMMARY, on mode=update the fresh
#         plan output to /tmp/plan.txt
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Auto-fix is optional: without the WIF pair the Claude step cannot
# authenticate, and without anthropic-vertex-project-id it authenticates but
# then fails. Require all three and skip the whole fix before doing any work.
if [ -z "${WORKLOAD_IDENTITY_PROVIDER:-}" ] || [ -z "${SERVICE_ACCOUNT:-}" ] || [ -z "${ANTHROPIC_VERTEX_PROJECT_ID:-}" ]; then
  echo "skip=true" >> "$GITHUB_OUTPUT"
  echo "Skipped drift fix for \`$DIR\`: automatic drift fix is not configured (workload-identity-provider / service-account / anthropic-vertex-project-id not all provided)." >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi

# --limit 200: default is 30; raise it so drift-fix PRs are not buried.
PRS=$(gh pr list \
  --state open \
  --base "$BASE_BRANCH" \
  --limit 200 \
  --json number,headRefName)

EXISTING_PR=$(printf '%s' "$PRS" \
  | jq -r --arg dir "$DIR" -f "$SCRIPT_DIR/match-existing-pr.jq")

if [ -z "$EXISTING_PR" ]; then
  {
    echo "skip=false"
    echo "mode=create"
  } >> "$GITHUB_OUTPUT"
  exit 0
fi

PR_INFO=$(gh pr view "$EXISTING_PR" --json commits,headRefName)

# A human committed to the PR branch -> the PR is theirs now; never re-run
# the fix on it (this is also the opt-out from repeated re-runs on drafts).
HAS_HUMAN=$(printf '%s' "$PR_INFO" | jq -r -f "$SCRIPT_DIR/has-human-commits.jq")
if [ "$HAS_HUMAN" = "true" ]; then
  {
    echo "skip=true"
    echo "existing-pr-number=$EXISTING_PR"
  } >> "$GITHUB_OUTPUT"
  echo "Skipped drift fix for \`$DIR\`: open PR #$EXISTING_PR has human commits." >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi

# Stale check: re-run plan on the PR branch. "No changes" means the PR
# still resolves the drift; anything else means new drift appeared after
# the PR was created.
EXISTING_BRANCH=$(printf '%s' "$PR_INFO" | jq -r .headRefName)
ORIGINAL_REF=$(git rev-parse --abbrev-ref HEAD)
if [ "$ORIGINAL_REF" = "HEAD" ]; then
  ORIGINAL_REF=$(git rev-parse HEAD)
fi
git fetch origin "$EXISTING_BRANCH"
git checkout -B "$EXISTING_BRANCH" FETCH_HEAD

set +e
"$SCRIPT_DIR/run-verify-plan.sh" /tmp/guard-plan.txt
PLAN_EXIT_CODE=$?
set -e

case "$PLAN_EXIT_CODE" in
  0)
    # Restore the original checkout so caller steps after this action do
    # not see an unexpected HEAD.
    git checkout "$ORIGINAL_REF"
    {
      echo "skip=true"
      echo "existing-pr-number=$EXISTING_PR"
    } >> "$GITHUB_OUTPUT"
    echo "Skipped drift fix for \`$DIR\`: open PR #$EXISTING_PR still resolves the drift." >> "$GITHUB_STEP_SUMMARY"
    ;;
  2)
    cp /tmp/guard-plan.txt /tmp/plan.txt
    {
      echo "skip=false"
      echo "mode=update"
      echo "branch=$EXISTING_BRANCH"
      echo "existing-pr-number=$EXISTING_PR"
    } >> "$GITHUB_OUTPUT"
    echo "Open PR #$EXISTING_PR no longer resolves the drift in \`$DIR\` (new drift since it was created); re-running the fix on its branch." >> "$GITHUB_STEP_SUMMARY"
    ;;
  *)
    # No checkout restore here: this step fails the job, so no later
    # steps observe the unexpected HEAD.
    echo "Verification plan on PR #$EXISTING_PR branch \`$EXISTING_BRANCH\` failed (exit code $PLAN_EXIT_CODE)." | tee -a "$GITHUB_STEP_SUMMARY"
    cat /tmp/guard-plan.txt
    exit 1
    ;;
esac
