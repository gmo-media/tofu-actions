#!/usr/bin/env bash
# Unit tests for the shared verification plan runner (scripts/run-verify-plan.sh).
# Uses a stub tf binary; no GitHub access or real terraform/tofu required.
# Run: bash drift-fix-claude/tests/run-verify-plan.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/../scripts/run-verify-plan.sh"

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

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/dir"

# Stub tf binary: records its args and working directory, prints to stdout and
# stderr, exits with the code given in $STUB_EXIT.
make_stub() {
  cat > "$1" <<'STUB'
#!/usr/bin/env bash
echo "$@" > "${STUB_ARGS_FILE:?}"
pwd >> "${STUB_ARGS_FILE:?}"
echo "stub stdout"
echo "stub stderr" >&2
exit "${STUB_EXIT:?}"
STUB
  chmod +x "$1"
}

make_stub "$WORK/terraform"
make_stub "$WORK/faketofu"

# plan の exit 0 がそのまま返る
STUB_ARGS_FILE="$WORK/args" STUB_EXIT=0 DIR="$WORK/dir" TF_BINARY="$WORK/terraform" \
  bash "$RUNNER" "$WORK/out.txt"
check "exit 0 passes through" $?

# スタブが $DIR 内で実行される（cwd の検証）
grep -qF "$WORK/dir" "$WORK/args"
check "plan runs inside DIR" $?

# stdout と stderr の両方がキャプチャされる
grep -q "stub stdout" "$WORK/out.txt" && grep -q "stub stderr" "$WORK/out.txt"
check "stdout and stderr are captured" $?

# plan の exit 2（changes あり）がそのまま返る
STUB_ARGS_FILE="$WORK/args" STUB_EXIT=2 DIR="$WORK/dir" TF_BINARY="$WORK/terraform" \
  bash "$RUNNER" "$WORK/out.txt"
[ "$?" -eq 2 ]
check "exit 2 passes through" $?

# plan の exit 1（エラー）がそのまま返る
STUB_ARGS_FILE="$WORK/args" STUB_EXIT=1 DIR="$WORK/dir" TF_BINARY="$WORK/terraform" \
  bash "$RUNNER" "$WORK/out.txt"
[ "$?" -eq 1 ]
check "exit 1 passes through" $?

# terraform（名前に tofu を含まない）には -concise を付けない
STUB_ARGS_FILE="$WORK/args" STUB_EXIT=0 DIR="$WORK/dir" TF_BINARY="$WORK/terraform" \
  bash "$RUNNER" "$WORK/out.txt"
! grep -q -- "-concise" "$WORK/args"
check "terraform does not get -concise" $?

# 共通の plan フラグが常に渡る（terraform）
grep -q -- "-no-color" "$WORK/args" \
  && grep -q -- "-detailed-exitcode" "$WORK/args" \
  && grep -q -- "-lock-timeout=300s" "$WORK/args"
check "plan flags are passed (terraform)" $?

# tofu には -concise を付ける
STUB_ARGS_FILE="$WORK/args" STUB_EXIT=0 DIR="$WORK/dir" TF_BINARY="$WORK/faketofu" \
  bash "$RUNNER" "$WORK/out.txt"
grep -q -- "-concise" "$WORK/args"
check "tofu gets -concise" $?

# 共通の plan フラグが常に渡る（tofu）
grep -q -- "-no-color" "$WORK/args" \
  && grep -q -- "-detailed-exitcode" "$WORK/args" \
  && grep -q -- "-lock-timeout=300s" "$WORK/args"
check "plan flags are passed (tofu)" $?

echo "---"
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
