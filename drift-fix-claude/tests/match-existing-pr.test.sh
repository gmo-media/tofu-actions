#!/usr/bin/env bash
# Unit tests for the drift-fix idempotency match filter (scripts/match-existing-pr.jq).
# Pure jq + bash, no GitHub access required.
# Run: bash drift-fix-claude/tests/match-existing-pr.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="$SCRIPT_DIR/../scripts/match-existing-pr.jq"

pass=0
fail=0

# assert <name> <dir> <pr-json> <expected-output>
assert() {
  local name="$1" dir="$2" json="$3" expected="$4" actual
  actual="$(printf '%s' "$json" | jq -r --arg dir "$dir" -f "$FILTER")"
  if [ "$actual" = "$expected" ]; then
    echo "ok   - $name"
    pass=$((pass + 1))
  else
    echo "FAIL - $name: expected [$expected], got [$actual]"
    fail=$((fail + 1))
  fi
}

# 同一 dir・タイムスタンプ違い -> match（最初の PR 番号を返す）
assert "same dir, different timestamps" "prod/foo" \
  '[{"number":11,"headRefName":"fix-drift-prod-foo-20260101-000000"},{"number":12,"headRefName":"fix-drift-prod-foo-20260611-235959"}]' \
  "11"

# prod/foo は prod/foo/bar のブランチに一致してはならない
assert "prod/foo does not match prod/foo/bar branch" "prod/foo" \
  '[{"number":21,"headRefName":"fix-drift-prod-foo-bar-20260611-120000"}]' \
  ""

# prod/foo/bar は prod/foo のブランチに一致してはならない
assert "prod/foo/bar does not match prod/foo branch" "prod/foo/bar" \
  '[{"number":31,"headRefName":"fix-drift-prod-foo-20260611-120000"}]' \
  ""

# 無関係ブランチ -> no match
assert "unrelated branches do not match" "prod/foo" \
  '[{"number":41,"headRefName":"feature-x"},{"number":42,"headRefName":"renovate/configure"}]' \
  ""

# open PR が0件 -> no match（skip=false 相当）
assert "empty PR list -> no match" "prod/foo" '[]' ""

echo "---"
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
