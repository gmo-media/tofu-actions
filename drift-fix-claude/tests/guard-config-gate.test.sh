#!/usr/bin/env bash
# Unit tests for the auto-fix configuration gate in guard-existing-pr.sh:
# the Vertex AI (WIF) inputs are optional, and when either is missing the
# guard must skip the whole fix (so drift-check-only callers are safe)
# without ever calling gh. Pure bash; gh is stubbed via PATH.
# Run: bash drift-fix-claude/tests/guard-config-gate.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$SCRIPT_DIR/../scripts/guard-existing-pr.sh"

pass=0
fail=0

check() {
  local name="$1" ok="$2"
  if [ "$ok" -eq 0 ]; then
    echo "ok   - $name"
    pass=$((pass + 1))
  else
    echo "FAIL - $name"
    fail=$((fail + 1))
  fi
}

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# Stub gh: records that it was called, returns an empty PR list
mkdir -p "$WORKDIR/bin"
cat > "$WORKDIR/bin/gh" <<EOF
#!/usr/bin/env bash
touch "$WORKDIR/gh-called"
echo "[]"
EOF
chmod +x "$WORKDIR/bin/gh"

# run_guard <workload-identity-provider> <service-account>
run_guard() {
  rm -f "$WORKDIR/output" "$WORKDIR/summary" "$WORKDIR/gh-called"
  : > "$WORKDIR/output"
  : > "$WORKDIR/summary"
  PATH="$WORKDIR/bin:$PATH" \
    WORKLOAD_IDENTITY_PROVIDER="$1" \
    SERVICE_ACCOUNT="$2" \
    DIR=env/test \
    BASE_BRANCH=main \
    GH_TOKEN=dummy \
    TF_BINARY=tofu \
    GITHUB_OUTPUT="$WORKDIR/output" \
    GITHUB_STEP_SUMMARY="$WORKDIR/summary" \
    bash "$GUARD" > /dev/null 2>&1
}

# --- Both inputs missing -> skip without touching gh ---------------------------
run_guard "" ""
check "no WIF inputs: guard exits 0" $?
grep -qx "skip=true" "$WORKDIR/output"
check "no WIF inputs: writes skip=true" $?
grep -q "not configured" "$WORKDIR/summary"
check "no WIF inputs: summary explains the skip" $?
[ ! -f "$WORKDIR/gh-called" ]
check "no WIF inputs: gh is never called" $?

# --- Only one of the two inputs set -> still skip ------------------------------
run_guard "projects/123/locations/global/workloadIdentityPools/p/providers/x" ""
check "service-account missing: guard exits 0" $?
grep -qx "skip=true" "$WORKDIR/output"
check "service-account missing: writes skip=true" $?

run_guard "" "sa@example.iam.gserviceaccount.com"
check "workload-identity-provider missing: guard exits 0" $?
grep -qx "skip=true" "$WORKDIR/output"
check "workload-identity-provider missing: writes skip=true" $?

# --- Both inputs set -> gate passes, normal flow continues ---------------------
run_guard "projects/123/locations/global/workloadIdentityPools/p/providers/x" \
  "sa@example.iam.gserviceaccount.com"
check "both WIF inputs set: guard exits 0" $?
grep -qx "skip=false" "$WORKDIR/output"
check "both WIF inputs set: writes skip=false" $?
grep -qx "mode=create" "$WORKDIR/output"
check "both WIF inputs set: writes mode=create" $?
[ -f "$WORKDIR/gh-called" ]
check "both WIF inputs set: gh is consulted" $?

echo "---"
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
