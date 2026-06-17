#!/usr/bin/env bash
# Commit and push the drift fix (also for unverified fixes, so they can be
# handed off to a human as a draft PR).
#
# Env: DIR, BRANCH_NAME, GH_TOKEN
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bot-identity.sh
. "$SCRIPT_DIR/bot-identity.sh"

# Required inputs: under set -u an unset BRANCH_NAME would otherwise turn the
# final `git push origin "$BRANCH_NAME"` into a bare `git push origin`.
: "${DIR:?DIR is required}"
: "${BRANCH_NAME:?BRANCH_NAME is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"

git config user.name "$BOT_NAME"
git config user.email "$BOT_EMAIL"

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

# actions/checkout (run inside configure@v5) persists the default GITHUB_TOKEN
# as an http.extraheader, and that is the identity `git push` would otherwise
# use. Events created by the default GITHUB_TOKEN cannot trigger downstream
# workflows (GitHub's recursion guard), so re-point the credential to GH_TOKEN
# (inputs.github-token): when that is an App token or PAT, the push — and the
# resulting pull_request: synchronize event on an existing PR — can trigger
# workflows. The extraheader takes precedence over credentials embedded in the
# remote URL, so it must be replaced rather than supplemented. When GH_TOKEN is
# the default token this is a harmless no-op (same identity).
server="${GITHUB_SERVER_URL:-https://github.com}"
git config --local --unset-all "http.${server}/.extraheader" || true
auth_header="$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 | tr -d '\n')"
git config --local "http.${server}/.extraheader" "Authorization: Basic ${auth_header}"

git push origin "$BRANCH_NAME"
echo "Changes committed and pushed to branch $BRANCH_NAME"
