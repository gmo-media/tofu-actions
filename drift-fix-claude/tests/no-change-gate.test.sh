#!/usr/bin/env bash
# Unit tests for the no-change gate verdict mapping (scripts/no-change-gate.sh).
# Pure bash, no GitHub access required.
# Run: bash drift-fix-claude/tests/no-change-gate.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/../scripts/no-change-gate.sh"

pass=0
fail=0

# assert <name> <plan-exit-code> <has-diff> <expected-verdict>
assert() {
  local name="$1" code="$2" has_diff="$3" expected="$4" actual
  actual="$(bash "$GATE" "$code" "$has_diff")"
  if [ "$actual" = "$expected" ]; then
    echo "ok   - $name"
    pass=$((pass + 1))
  else
    echo "FAIL - $name: expected [$expected], got [$actual]"
    fail=$((fail + 1))
  fi
}

# assert_usage_error <name> <args...>
assert_usage_error() {
  local name="$1"; shift
  if bash "$GATE" "$@" >/dev/null 2>&1; then
    echo "FAIL - $name: expected non-zero exit"
    fail=$((fail + 1))
  else
    echo "ok   - $name"
    pass=$((pass + 1))
  fi
}

# plan が No changes & Claude の変更あり -> 通常 PR
assert "no changes + diff -> pr" 0 true "pr"
# plan が No changes & 変更なし -> drift 自然解消（PR 不要で正常終了）
assert "no changes + no diff -> resolved" 0 false "resolved"
# 差分残存 & 変更あり -> ドラフト PR で人間に引き継ぐ
assert "remaining drift + diff -> draft-pr" 2 true "draft-pr"
# 差分残存 & 変更なし -> コミットが作れないので fail
assert "remaining drift + no diff -> fail" 2 false "fail"
# plan 自体のエラー -> fail（fail-fast）
assert "plan error + diff -> fail" 1 true "fail"
assert "plan error + no diff -> fail" 1 false "fail"
# 予期しない exit code（コマンド不在の 127 等）-> fail
assert "unexpected exit code -> fail" 127 true "fail"
# 引数不正は判定せず usage エラー（非ゼロ終了）
assert_usage_error "invalid HAS_DIFF is a usage error" 0 maybe
assert_usage_error "missing args is a usage error" 0

echo "---"
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
