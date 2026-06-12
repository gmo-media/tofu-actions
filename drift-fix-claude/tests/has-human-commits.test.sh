#!/usr/bin/env bash
# Unit tests for the human-commit detection filter (scripts/has-human-commits.jq).
# Pure jq + bash, no GitHub access required.
# Run: bash drift-fix-claude/tests/has-human-commits.test.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="$SCRIPT_DIR/../scripts/has-human-commits.jq"

pass=0
fail=0

BOT_EMAIL="41898282+github-actions[bot]@users.noreply.github.com"

# assert <name> <pr-json> <expected-output>
assert() {
  local name="$1" json="$2" expected="$3" actual
  actual="$(printf '%s' "$json" | jq -r -f "$FILTER")"
  if [ "$actual" = "$expected" ]; then
    echo "ok   - $name"
    pass=$((pass + 1))
  else
    echo "FAIL - $name: expected [$expected], got [$actual]"
    fail=$((fail + 1))
  fi
}

# bot コミットのみ -> false
assert "bot-only commits -> false" \
  '{"commits":[{"authors":[{"email":"'"$BOT_EMAIL"'","login":"github-actions","name":"github-actions[bot]"}]}]}' \
  "false"

# bot コミット + 人間コミット -> true
assert "bot and human commits -> true" \
  '{"commits":[
     {"authors":[{"email":"'"$BOT_EMAIL"'","login":"github-actions","name":"github-actions[bot]"}]},
     {"authors":[{"email":"dev@example.com","login":"some-dev","name":"Some Dev"}]}
   ]}' \
  "true"

# 人間コミットのみ -> true
assert "human-only commits -> true" \
  '{"commits":[{"authors":[{"email":"dev@example.com","login":"some-dev","name":"Some Dev"}]}]}' \
  "true"

# GitHub がユーザー解決できない author（login 空）-> 安全側で true
assert "unresolved author (empty login) -> true" \
  '{"commits":[{"authors":[{"email":"unknown@example.com","login":"","name":"Unknown"}]}]}' \
  "true"

# email だけ bot に一致（login 空）-> bot 扱いで false
assert "bot email with empty login -> false" \
  '{"commits":[{"authors":[{"email":"'"$BOT_EMAIL"'","login":"","name":"github-actions[bot]"}]}]}' \
  "false"

# co-author に人間が含まれる -> true
assert "human co-author -> true" \
  '{"commits":[{"authors":[
     {"email":"'"$BOT_EMAIL"'","login":"github-actions","name":"github-actions[bot]"},
     {"email":"dev@example.com","login":"some-dev","name":"Some Dev"}
   ]}]}' \
  "true"

# コミットが空 -> false
assert "empty commits -> false" '{"commits":[]}' "false"

# 余分なキー（headRefName 等）が混ざっても無視される
assert "extra keys are ignored" \
  '{"headRefName":"fix-drift-prod-foo-20260101-000000","commits":[{"authors":[{"email":"'"$BOT_EMAIL"'","login":"github-actions","name":"github-actions[bot]"}]}]}' \
  "false"

echo "---"
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
