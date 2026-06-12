#!/usr/bin/env bash
# Commit and push the drift fix (also for unverified fixes, so they can be
# handed off to a human as a draft PR).
#
# Env: DIR, BRANCH_NAME
set -eo pipefail

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

# git status --porcelain also catches newly created files,
# unlike git diff (same detection as verify-drift-resolved.sh)
if [ -z "$(git status --porcelain)" ]; then
  echo "No changes to commit"
  exit 0
fi

git add -A

# COUPLING (keep in sync): never add a Co-Authored-By trailer to this
# message. GitHub resolves co-authors as commit authors, so
# has-human-commits.jq would classify the bot's own commits as human and
# permanently disable the guard's update mode for the PR.
COMMIT_MSG="fix: Auto-fix infrastructure drift in $DIR

This commit automatically fixes infrastructure drift detected in $DIR.
The changes update the Terraform/OpenTofu configuration to match the current
real-world infrastructure state.

Automated by Claude Code drift fixer"

git commit -m "$COMMIT_MSG"
git push origin "$BRANCH_NAME"
echo "Changes committed and pushed to branch $BRANCH_NAME"
