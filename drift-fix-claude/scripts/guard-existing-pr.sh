#!/usr/bin/env bash
# Skip the drift fix when an open drift-fix PR for this dir already exists,
# so repeated cron runs do not pile up duplicate PRs for the same unresolved
# drift. The match logic lives in match-existing-pr.jq (shared with the unit
# test in tests/match-existing-pr.test.sh).
#
# Env:    DIR, BASE_BRANCH, GH_TOKEN
# Writes: skip / existing-pr-number to GITHUB_OUTPUT, summary line to
#         GITHUB_STEP_SUMMARY
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --limit 200: default is 30; raise it so drift-fix PRs are not buried.
PRS=$(gh pr list \
  --state open \
  --base "$BASE_BRANCH" \
  --limit 200 \
  --json number,headRefName)

EXISTING_PR=$(printf '%s' "$PRS" \
  | jq -r --arg dir "$DIR" -f "$SCRIPT_DIR/match-existing-pr.jq")

if [ -n "$EXISTING_PR" ]; then
  {
    echo "skip=true"
    echo "existing-pr-number=$EXISTING_PR"
  } >> "$GITHUB_OUTPUT"
  echo "Skipped drift fix for \`$DIR\`: open PR #$EXISTING_PR already exists." >> "$GITHUB_STEP_SUMMARY"
else
  echo "skip=false" >> "$GITHUB_OUTPUT"
fi
