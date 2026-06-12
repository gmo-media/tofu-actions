#!/usr/bin/env bash
# Consistency check between the `inputs:` declarations in action.yaml and
# the `${{ inputs.<name> }}` references in its step bodies. An undeclared
# reference silently evaluates to an empty string at runtime (GitHub only
# emits a warning), which is how a bad merge once shipped a broken Vertex
# configuration. Pure bash, no GitHub access required.
# Run: bash drift-fix-claude/tests/action-inputs.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# Declared inputs: two-space-indented keys between `inputs:` and `outputs:`
DECLARED=$(sed -n '/^inputs:/,/^outputs:/p' "$ACTION" | grep -o '^  [a-z-]*:' | tr -d ' :')
[ -n "$DECLARED" ]
check "action.yaml declares inputs" $?

# References: every `inputs.<name>` used anywhere in the file
REFERENCED=$(grep -o 'inputs\.[a-z-]*' "$ACTION" | sed 's/^inputs\.//' | sort -u)
[ -n "$REFERENCED" ]
check "action.yaml references inputs" $?

# Every referenced input must be declared
for ref in $REFERENCED; do
  echo "$DECLARED" | grep -qx "$ref"
  check "referenced input '$ref' is declared" $?
done

# Every declared input must be referenced (dead inputs hide wiring mistakes)
for dec in $DECLARED; do
  echo "$REFERENCED" | grep -qx "$dec"
  check "declared input '$dec' is referenced" $?
done

echo "---"
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
