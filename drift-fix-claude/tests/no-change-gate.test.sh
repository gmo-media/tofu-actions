#!/usr/bin/env bash
# Unit tests for the no-change gate verdict mapping (scripts/no-change-gate.sh).
# Pure bash, no GitHub access required.
# Run: bash drift-fix-claude/tests/no-change-gate.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/../scripts/no-change-gate.sh"

pass=0
fail=0

# assert <name> <plan-exit-code> <has-diff> <has-replace> <expected-verdict>
assert() {
  local name="$1" code="$2" has_diff="$3" has_replace="$4" expected="$5" actual
  actual="$(bash "$GATE" "$code" "$has_diff" "$has_replace")"
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
assert "no changes + diff -> pr" 0 true false "pr"
# plan が No changes & 変更なし -> drift 自然解消（PR 不要で正常終了）
assert "no changes + no diff -> resolved" 0 false false "resolved"
# 差分残存 & 変更あり & replace なし -> ドラフト PR で人間に引き継ぐ
assert "remaining drift + diff -> draft-pr" 2 true false "draft-pr"
# 差分残存に replace（-/+）が含まれる -> 引き継がず replace-fail
# （create 単体・destroy 単体は draft-pr のまま許容、destroy+create の対は不可）
assert "remaining drift + diff + replace -> replace-fail" 2 true true "replace-fail"
# 差分残存 & 変更なし -> コミットが作れないので fail（replace の有無は無関係）
assert "remaining drift + no diff -> fail" 2 false false "fail"
assert "remaining drift + no diff + replace -> fail" 2 false true "fail"
# No changes なのに replace 検出は入力の矛盾 -> 安全側に fail
assert "no changes + replace is inconsistent -> fail" 0 true true "fail"
assert "no changes + no diff + replace is inconsistent -> fail" 0 false true "fail"
# plan 自体のエラー -> fail（fail-fast）
assert "plan error + diff -> fail" 1 true false "fail"
assert "plan error + no diff -> fail" 1 false false "fail"
# 予期しない exit code（コマンド不在の 127 等）-> fail
assert "unexpected exit code -> fail" 127 true false "fail"
# 引数不正は判定せず usage エラー（非ゼロ終了）
assert_usage_error "invalid HAS_DIFF is a usage error" 0 maybe false
assert_usage_error "invalid HAS_REPLACE is a usage error" 0 true maybe
assert_usage_error "missing args is a usage error" 0 true

echo "---"
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
