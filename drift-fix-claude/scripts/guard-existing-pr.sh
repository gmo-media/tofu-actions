#!/usr/bin/env bash
set -euo pipefail

# Decide whether to skip the drift fix for this dir.
#
# Skips when auto-fix is not configured (Vertex AI inputs missing).
# Otherwise always emits mode=create.
#
# Env:    DIR, WORKLOAD_IDENTITY_PROVIDER, SERVICE_ACCOUNT,
#         ANTHROPIC_VERTEX_PROJECT_ID
# Writes: skip / mode / summary to GITHUB_OUTPUT,
#         summary line to GITHUB_STEP_SUMMARY.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bot-identity.sh
. "$SCRIPT_DIR/bot-identity.sh"

DIR="${DIR:?DIR must be set}"

# Require all three Vertex AI inputs; skip the whole fix if any is absent.
# This is the "auto-fix is optional" gate: callers that don't supply Vertex AI
# credentials get a graceful skip rather than a hard failure.
if [ -z "${WORKLOAD_IDENTITY_PROVIDER:-}" ] || [ -z "${SERVICE_ACCOUNT:-}" ] || [ -z "${ANTHROPIC_VERTEX_PROJECT_ID:-}" ]; then
  {
    echo "skip=true"
    echo "summary=Drift detected in \`$DIR\`; automatic fix is not configured. Review and fix manually."
  } >> "$GITHUB_OUTPUT"
  echo "Skipped drift fix for \`$DIR\`: automatic drift fix is not configured (workload-identity-provider / service-account / anthropic-vertex-project-id not all provided)." >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi

{
  echo "skip=false"
  echo "mode=create"
} >> "$GITHUB_OUTPUT"
