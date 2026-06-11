#!/usr/bin/env bash
# Create and check out the branch that will carry the drift fix.
#
# Env:    DIR
# Writes: name to GITHUB_OUTPUT
set -eo pipefail

# COUPLING (keep in sync): this branch name is matched by the guard via
# match-existing-pr.jq. Changing the format here requires updating that
# filter (and its tests) accordingly.
BRANCH_NAME="fix-drift-$(echo "$DIR" | tr '/' '-')-$(date +%Y%m%d-%H%M%S)"
git checkout -b "$BRANCH_NAME"
echo "name=$BRANCH_NAME" >> "$GITHUB_OUTPUT"
