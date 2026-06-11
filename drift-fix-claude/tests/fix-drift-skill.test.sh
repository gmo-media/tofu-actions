#!/usr/bin/env bash
# Unit tests for the fix-drift skill packaging (repo-root
# .claude/skills/fix-drift/SKILL.md). Guards the COUPLING between the
# /fix-drift invocation in action.yaml and the skill's `arguments:`
# declaration. Pure bash, no GitHub access required.
# Run: bash drift-fix-claude/tests/fix-drift-skill.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$SCRIPT_DIR/../../.claude/skills/fix-drift/SKILL.md"
ACTION="$SCRIPT_DIR/../action.yaml"

pass=0
fail=0

# check <name> <condition-exit-code> [detail]
check() {
  local name="$1" ok="$2" detail="${3:-}"
  if [ "$ok" -eq 0 ]; then
    echo "ok   - $name"
    pass=$((pass + 1))
  else
    echo "FAIL - $name${detail:+: $detail}"
    fail=$((fail + 1))
  fi
}

[ -f "$SKILL" ]
check "SKILL.md exists" $?

[ -f "$ACTION" ]
check "action.yaml exists" $?

# --- Skill side: extract the declared arguments -------------------------------
ARGS_LINE=$(grep -m1 '^arguments:' "$SKILL" | sed 's/^arguments:[[:space:]]*//')
[ -n "$ARGS_LINE" ]
check "SKILL.md declares arguments" $?

# Every declared argument must be referenced as $name in the skill body
for arg in $ARGS_LINE; do
  grep -q -- "\$$arg" "$SKILL"
  check "SKILL.md body references \$$arg" $?
done

# Model auto-invocation is off: the skill only runs via the action's explicit call
grep -q '^disable-model-invocation: true' "$SKILL"
check "SKILL.md disables model auto-invocation" $?

# --- Action side: the /fix-drift call must pass the same number of arguments --
INVOCATION=$(grep -m1 -o 'prompt: /fix-drift.*' "$ACTION")
[ -n "$INVOCATION" ]
check "action.yaml invokes /fix-drift via the prompt input" $? "no /fix-drift invocation found"

DECLARED_COUNT=$(echo "$ARGS_LINE" | wc -w | tr -d ' ')
# Collapse each ${{ ... }} expression into a single token, then subtract 2
# for the leading "prompt:" and "/fix-drift" tokens themselves
NORMALIZED=$(echo "$INVOCATION" | sed -E 's/\$\{\{[^}]*\}\}/EXPR/g')
PASSED_COUNT=$(( $(echo "$NORMALIZED" | wc -w | tr -d ' ') - 2 ))
[ "$DECLARED_COUNT" -eq "$PASSED_COUNT" ]
check "argument count matches (declared=$DECLARED_COUNT, passed=$PASSED_COUNT)" $?

# --add-dir must point claude at the action repo root, or the skill is never loaded
grep -qF -- '--add-dir "${{ github.action_path }}/.."' "$ACTION"
check "action.yaml loads skills via --add-dir from the action repo root" $?

echo "---"
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
