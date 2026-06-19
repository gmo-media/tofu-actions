#!/usr/bin/env bash
# Run `<tf-binary> plan` for drift verification and capture its output.
# Shared by guard-existing-pr.sh (stale-PR detection) and
# verify-drift-resolved.sh (no-change gate) so both use identical plan
# conditions.
#
# Usage: run-verify-plan.sh OUT_FILE
# Env:   DIR, TF_BINARY
# Exit:  the plan's exit code, passed through unmodified
#        (0 = no changes, 2 = changes present, 1 = error)
set -euo pipefail

OUT_FILE="${1:?usage: run-verify-plan.sh OUT_FILE}"
: "${DIR:?DIR is required}"
: "${TF_BINARY:?TF_BINARY is required}"

# tofu supports -concise to drop the refresh noise; terraform does not
CONCISE_FLAG=""
case "$TF_BINARY" in
  *tofu*) CONCISE_FLAG="-concise" ;;
esac

set +e
# -no-color: the output is embedded in the PR body / job summary.
# 2>&1: plan errors go to stderr; capture them so the fail branch and
# the draft PR body are not empty on exit code 1.
(cd "$DIR" && "$TF_BINARY" plan -no-color -lock-timeout=300s $CONCISE_FLAG -detailed-exitcode) > "$OUT_FILE" 2>&1
exit $?
