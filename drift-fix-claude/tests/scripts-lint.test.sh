#!/usr/bin/env bash
# Lint checks for drift-fix-claude/scripts/*.sh: the action executes them
# directly (run: "$GITHUB_ACTION_PATH/scripts/<name>.sh"), so each script
# must be executable, have a bash shebang, and parse cleanly.
# Pure bash, no GitHub access required.
# Run: bash drift-fix-claude/tests/scripts-lint.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/../scripts"
ACTION="$SCRIPT_DIR/../action.yaml"

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

for script in "$SCRIPTS_DIR"/*.sh; do
  name=$(basename "$script")

  [ -x "$script" ]
  check "$name is executable" $?

  head -1 "$script" | grep -q '^#!/usr/bin/env bash$'
  check "$name has a bash shebang" $?

  bash -n "$script"
  check "$name parses (bash -n)" $?
done

# Every script referenced from action.yaml must exist
for ref in $(grep -o 'scripts/[a-z-]*\.\(sh\|jq\)' "$ACTION" | sort -u); do
  [ -f "$SCRIPT_DIR/../$ref" ]
  check "referenced $ref exists" $?
done

echo "---"
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
