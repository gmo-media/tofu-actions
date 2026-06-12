#!/usr/bin/env bash
# Create and check out the branch that will carry the drift fix, or reuse
# the existing PR branch when the guard decided to update it (MODE=update;
# the guard already checked that branch out).
#
# Env:    DIR, MODE, EXISTING_BRANCH (only when MODE=update)
# Writes: name to GITHUB_OUTPUT
set -eo pipefail

if [ "$MODE" = "update" ]; then
  echo "name=${EXISTING_BRANCH:?EXISTING_BRANCH is required when MODE=update}" >> "$GITHUB_OUTPUT"
  exit 0
fi

# COUPLING (keep in sync): this branch name is matched by the guard via
# match-existing-pr.jq. Changing the format here requires updating that
# filter (and its tests) accordingly.
BRANCH_NAME="fix-drift-$(echo "$DIR" | tr '/' '-')-$(date +%Y%m%d-%H%M%S)"
git checkout -b "$BRANCH_NAME"
echo "name=$BRANCH_NAME" >> "$GITHUB_OUTPUT"
