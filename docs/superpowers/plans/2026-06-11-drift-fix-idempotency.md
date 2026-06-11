# drift-fix-claude 冪等化（既存PRスキップ）Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ある dir に対して open 中の drift-fix PR が既に存在する場合、`drift-fix-claude` アクションが Claude 実行を含む以降の処理をスキップし、重複 PR を作らないようにする。

**Architecture:** `drift-fix-claude/action.yaml` の先頭に `guard` ステップを1つ追加し、既存の全ステップに `if: steps.guard.outputs.skip != 'true'` を付与してゲートする。判定ロジック（dir の sanitize + ブランチ名の正規表現マッチ）は単一の `jq` フィルタファイルに集約し、アクションのガードステップと bash 単体テストの**両方からそのフィルタを再利用**する（spec のテスト戦略に準拠）。呼び出し側ワークフローは無変更。

**Tech Stack:** GitHub Actions composite action (YAML), Bash, `jq` 1.7+, GitHub CLI (`gh`)

**Spec:** [docs/superpowers/specs/2026-06-11-drift-fix-idempotency-design.md](../specs/2026-06-11-drift-fix-idempotency-design.md)

---

## File Structure

判定式を1ファイルに閉じ込め、アクションとテストの単一の真実とする。

- **Create: `drift-fix-claude/scripts/match-existing-pr.jq`**
  判定式の単一の真実。raw な dir を `--arg dir` で受け取り、`gh pr list --json number,headRefName` の出力（PR 配列）を stdin で受け、この dir の drift-fix ブランチに一致する最初の open PR 番号を出力する（なければ無出力）。dir の sanitize（`/`→`-`）もこのフィルタ内で行うため、「sanitize + マッチ」を1単位でテストできる。
- **Create: `drift-fix-claude/tests/match-existing-pr.test.sh`**
  上記 jq フィルタの bash 単体テスト。GitHub 実環境不要・`jq` のみで完結。spec の全ケースを検証する。
- **Modify: `drift-fix-claude/action.yaml`**
  `guard` ステップを先頭に追加、既存7ステップ（config / branch / save plan / setup claude / fix drift / commit / create-pr）に `if` を付与、outputs に `skipped` と `existing-pr-number` を追加。`branch` ステップに jq フィルタとの結合点コメントを追加。
- **Modify: `.github/workflows/ci.yaml`**
  単体テストを実行する `shell-tests` ジョブを追加し、テストが CI で回るようにする。
- **Create: `docs/superpowers/runbooks/drift-fix-idempotency-verification.md`**
  spec が要求する「ワークフローレベルの手動検証」の手順書。

## 設計上の判断メモ（実装者向け）

- **判定は正規表現1本ではなく「prefix 一致 + タイムスタンプ正規表現」で実装する。** spec の `^fix-drift-<dir>-[0-9]{8}-[0-9]{6}$` と**結果は等価**だが、dir に正規表現メタ文字（特に `.`）が含まれても誤マッチしない点で堅牢。`prod/foo` と `prod/foo/bar` の相互非マッチも成立する（後述テストで担保）。
- **dir はガードステップで env 変数経由で渡す**（直接 `${{ }}` 展開しない）。スクリプトインジェクションを避ける安全側の実装。既存ステップの展開方法は今回スコープ外として変更しない。
- **`shell: bash` の既定**は `bash --noprofile --norc -eo pipefail {0}`。よって `gh pr list` 失敗時はガードステップが自動的に fail し、spec の fail-fast 要件を満たす（明示的な `set -e` は付けない＝既存ステップと同じ流儀）。
- **`$GITHUB_ACTION_PATH`** は composite action 実行時に GitHub が自動設定する環境変数で、`${{ github.action_path }}` と同値。同梱 jq を `with:` で配線せずに参照できる。

---

### Task 1: 判定式（jq フィルタ）を TDD で実装する

**Files:**
- Create: `drift-fix-claude/tests/match-existing-pr.test.sh`
- Create: `drift-fix-claude/scripts/match-existing-pr.jq`

- [ ] **Step 1: 失敗するテストを書く**

`drift-fix-claude/tests/match-existing-pr.test.sh` を新規作成:

```bash
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
```

- [ ] **Step 2: テストを実行して失敗を確認する**

Run: `bash drift-fix-claude/tests/match-existing-pr.test.sh`
Expected: FAIL（jq フィルタ未作成のため `jq: error: Could not open ...match-existing-pr.jq` で全ケース失敗 → 最終的に終了コード非0）

- [ ] **Step 3: jq フィルタを実装する**

`drift-fix-claude/scripts/match-existing-pr.jq` を新規作成:

```jq
# Identify whether an open drift-fix PR already exists for a given directory.
#
# This is the single source of truth for the idempotency match used by the
# "Skip if an open drift-fix PR already exists" guard step in ../action.yaml,
# and it is exercised directly by ../tests/match-existing-pr.test.sh.
#
# COUPLING (keep in sync): the branch name produced by the "Create fix branch"
# step in ../action.yaml is
#     fix-drift-<dir with "/" replaced by "-">-<YYYYMMDD>-<HHMMSS>
# If that naming changes, update the prefix / timestamp pattern below to match.
#
# Input : JSON array of { "number": <int>, "headRefName": <string> }
#         (the output of `gh pr list --state open --json number,headRefName`).
# Arg   : --arg dir "<inputs.dir>"  (the RAW directory; slashes are sanitized here).
# Output: the number of the first matching open PR, or nothing at all when none match.
#
# We match by a literal prefix plus a timestamp regex (instead of a single
# regex over the whole branch name) so that regex metacharacters in the
# directory cannot cause false matches; the result is equivalent to
# ^fix-drift-<sanitized-dir>-[0-9]{8}-[0-9]{6}$.
($dir | gsub("/"; "-")) as $sanitized
| ("fix-drift-" + $sanitized + "-") as $prefix
| ($prefix | length) as $plen
| [ .[]
    | select(
        (.headRefName | startswith($prefix))
        and (.headRefName[$plen:] | test("^[0-9]{8}-[0-9]{6}$"))
      )
    | .number
  ]
| first // empty
```

- [ ] **Step 4: テストを実行して成功を確認する**

Run: `bash drift-fix-claude/tests/match-existing-pr.test.sh`
Expected: PASS（`passed: 5, failed: 0`、終了コード0）

- [ ] **Step 5: コミット**

```bash
git add drift-fix-claude/scripts/match-existing-pr.jq drift-fix-claude/tests/match-existing-pr.test.sh
git commit -m "test: add drift-fix idempotency match filter with unit tests"
```

---

### Task 2: action.yaml に guard ステップを組み込む

**Files:**
- Modify: `drift-fix-claude/action.yaml`

- [ ] **Step 1: outputs に skipped / existing-pr-number を追加する**

`outputs:` ブロック（現状 `pr-url` と `branch-name`）を以下に置き換える:

```yaml
outputs:
  pr-url:
    description: URL of the created pull request (empty when skipped)
    value: ${{ steps.create-pr.outputs.pr-url }}
  branch-name:
    description: Name of the branch with fixes (empty when skipped)
    value: ${{ steps.branch.outputs.name }}
  skipped:
    description: "true if an open drift-fix PR already existed and the fix was skipped"
    value: ${{ steps.guard.outputs.skip }}
  existing-pr-number:
    description: Number of the existing open drift-fix PR when skipped (otherwise empty)
    value: ${{ steps.guard.outputs.existing-pr-number }}
```

- [ ] **Step 2: guard ステップを steps の先頭（`config` の前）に追加する**

`runs.steps` の最初の要素として以下を挿入する:

```yaml
    # Skip everything below (including the costly Claude run) when an open
    # drift-fix PR for this dir already exists, so repeated cron runs do not
    # pile up duplicate PRs for the same unresolved drift.
    # The match logic lives in scripts/match-existing-pr.jq (shared with the
    # unit test in tests/match-existing-pr.test.sh).
    - name: Skip if an open drift-fix PR already exists
      id: guard
      shell: bash
      env:
        GH_TOKEN: ${{ inputs.github-token || github.token }}
        DIR: ${{ inputs.dir }}
        BASE_BRANCH: ${{ inputs.base-branch }}
      run: |
        # --limit 200: default is 30; raise it so drift-fix PRs are not buried.
        PRS=$(gh pr list \
          --state open \
          --base "$BASE_BRANCH" \
          --limit 200 \
          --json number,headRefName)

        EXISTING_PR=$(printf '%s' "$PRS" \
          | jq -r --arg dir "$DIR" -f "$GITHUB_ACTION_PATH/scripts/match-existing-pr.jq")

        if [ -n "$EXISTING_PR" ]; then
          {
            echo "skip=true"
            echo "existing-pr-number=$EXISTING_PR"
          } >> "$GITHUB_OUTPUT"
          echo "Skipped drift fix for \`$DIR\`: open PR #$EXISTING_PR already exists." >> "$GITHUB_STEP_SUMMARY"
        else
          echo "skip=false" >> "$GITHUB_OUTPUT"
        fi
```

- [ ] **Step 3: 既存の全ステップに `if` ガードを付与する**

`config` / `branch` / `save plan` / `setup claude` / `fix drift` / `commit` / `create-pr` の各ステップに、次の行を（`uses:`/`name:` と同じインデントで）追加する:

```yaml
      if: ${{ steps.guard.outputs.skip != 'true' }}
```

具体的には:

1. `- id: config`（`uses: gmo-media/tofu-actions/read-config@v5`）→ `id: config` の直後の行に `if:` を追加。
2. `- name: Create fix branch`（`id: branch`）→ `name:` の直後に `if:` を追加。
3. `- name: Save plan to file` → `name:` の直後に `if:` を追加。
4. `- name: Setup Claude Code` → `name:` の直後に `if:` を追加。
5. `- name: Fix drift with Claude Code` → `name:` の直後に `if:` を追加。
6. `- name: Commit changes` → `name:` の直後に `if:` を追加。
7. `- name: Create Pull Request`（`id: create-pr`）→ `name:` の直後に `if:` を追加。

- [ ] **Step 4: branch ステップに結合点コメントを追加する**

`Create fix branch` ステップの `run:` 内、`BRANCH_NAME=...` 行の直前に次のコメントを追加する（jq 側の COUPLING コメントと対になる）:

```yaml
      run: |
        # COUPLING (keep in sync): this branch name is matched by the guard via
        # scripts/match-existing-pr.jq. Changing the format here requires
        # updating that filter (and its tests) accordingly.
        BRANCH_NAME="fix-drift-$(echo '${{ inputs.dir }}' | tr '/' '-')-$(date +%Y%m%d-%H%M%S)"
        git checkout -b "$BRANCH_NAME"
        echo "name=$BRANCH_NAME" >> $GITHUB_OUTPUT
```

- [ ] **Step 5: YAML が妥当であることを確認する**

Run: `ruby -ryaml -e "YAML.load_file('drift-fix-claude/action.yaml'); puts 'YAML OK'"`
Expected: `YAML OK`（例外なし）

（注: composite action の `action.yaml` は `actionlint` の対象外。構文チェックは上記の YAML パースで行う。`python3 -c "import yaml"` はこの環境では PyYAML 未導入のため使わない。）

さらに `guard` を含む全8ステップに `if`/`id` が正しく付いていることを目視確認する（guard 自身には `if` は付けない）:

Run: `grep -nE "id:|name:|if:|uses:" drift-fix-claude/action.yaml`
Expected: `config`/`branch`/`save plan`/`setup claude`/`fix drift`/`commit`/`create-pr` の7ステップそれぞれに `if: ${{ steps.guard.outputs.skip != 'true' }}` が並び、`guard` ステップには `if` が無いこと。

- [ ] **Step 6: コミット**

```bash
git add drift-fix-claude/action.yaml
git commit -m "feat(drift-fix-claude): skip when an open drift-fix PR already exists"
```

---

### Task 3: 単体テストを CI で実行する

**Files:**
- Modify: `.github/workflows/ci.yaml`

- [ ] **Step 1: shell-tests ジョブを追加する**

`.github/workflows/ci.yaml` の `jobs:` に、`js-build` と同じインデントレベルで次のジョブを追加する（末尾に追記でよい）:

```yaml
  shell-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@93cb6efe18208431cddfb8368fd83d5badbf9bfd # v5
      - name: Run drift-fix idempotency match tests
        run: bash drift-fix-claude/tests/match-existing-pr.test.sh
```

（`jq` は ubuntu-latest ランナーにプリインストール済みのため追加セットアップ不要。）

- [ ] **Step 2: ワークフローが妥当であることを確認する**

Run: `actionlint .github/workflows/ci.yaml`
Expected: 出力なし・終了コード0（ci.yaml はワークフローファイルなので actionlint で検証可能）

- [ ] **Step 3: テストがローカルでも通ることを再確認する**

Run: `bash drift-fix-claude/tests/match-existing-pr.test.sh`
Expected: `passed: 5, failed: 0`

- [ ] **Step 4: コミット**

```bash
git add .github/workflows/ci.yaml
git commit -m "ci: run drift-fix idempotency match tests"
```

---

### Task 4: 手動検証手順を文書化する

**Files:**
- Create: `docs/superpowers/runbooks/drift-fix-idempotency-verification.md`

- [ ] **Step 1: runbook を作成する**

`docs/superpowers/runbooks/drift-fix-idempotency-verification.md` を新規作成:

```markdown
# Runbook: drift-fix-claude 冪等化の手動検証

- 関連 spec: [../specs/2026-06-11-drift-fix-idempotency-design.md](../specs/2026-06-11-drift-fix-idempotency-design.md)
- 関連 plan: [../plans/2026-06-11-drift-fix-idempotency.md](../plans/2026-06-11-drift-fix-idempotency.md)

## 目的

同一 dir・未解消の drift に対して、`drift-fix-claude` が重複 PR を作らない（冪等である）ことを実環境で確認する。

## 前提

- 対象リポジトリで drift-check ワークフロー（`quickstart-drift-check.yaml` を呼び出すもの）が動作していること。
- 自動修正に必要なシークレット（`anthropic-api-key` または `claude-code-oauth-token`、および PR 作成用 `github-token`）が設定済みであること。
- いずれかの dir に未解消の drift が存在する（または意図的に作れる）こと。

## 単体テスト（前段の自動確認）

```bash
bash drift-fix-claude/tests/match-existing-pr.test.sh
```

`passed: 5, failed: 0` を確認する。CI では `shell-tests` ジョブで自動実行される。

## ワークフローレベルの手動検証

1. drift-check を実行する（cron 待ち、または手動トリガー）。
   - 期待: 対象 dir に対し `drift-fix-claude` が走り、`fix-drift-<dir>-<timestamp>` ブランチで PR が1件作成される。
   - その実行ログで `guard` ステップが `skip=false` になっていること。
2. 作成された PR を**マージせず open のまま**にし、drift も未解消のまま、drift-check をもう一度実行する。
   - 期待: 同 dir の `drift-fix-claude` 実行で `guard` がスキップを判定し、Claude 実行・commit・PR 作成のステップがすべて skip される。
   - Job summary に `Skipped drift fix for \`<dir>\`: open PR #<N> already exists.` が出力されること。
   - **新しい PR が作成されないこと**（PR は1件のままであること）。
3. （任意）1 の PR をマージまたはクローズしてから drift-check を再実行すると、open PR が無いため再び PR が作成される（別タイムスタンプのブランチ）ことを確認する。

## 既知の制約（spec より）

- Slack 通知（`notify-drift`）は `drift-fix-claude` と独立に走るため、スキップ時も "Claude is on the way to creating a PR..." と表示され続ける（今回スコープ外）。
- dir `prod/foo`（slash）と dir `prod-foo`（literal dash）は同一の sanitized 文字列になり理論上取り違えるが、実運用ではほぼ発生しないため許容する。
```

- [ ] **Step 2: コミット**

```bash
git add docs/superpowers/runbooks/drift-fix-idempotency-verification.md
git commit -m "docs: add manual verification runbook for drift-fix idempotency"
```

---

## 完了条件（Definition of Done）

- [ ] `bash drift-fix-claude/tests/match-existing-pr.test.sh` が `passed: 5, failed: 0` で通る。
- [ ] `drift-fix-claude/action.yaml` が妥当な YAML で、`guard` ステップが先頭にあり、既存7ステップに `if: ${{ steps.guard.outputs.skip != 'true' }}` が付いている。
- [ ] action の outputs に `skipped` と `existing-pr-number` が追加されている。
- [ ] `.github/workflows/ci.yaml` に `shell-tests` ジョブが追加され、テストを実行する。
- [ ] `branch` ステップと jq フィルタに相互参照（結合点）コメントがある。
- [ ] 手動検証 runbook が `docs/superpowers/runbooks/` に存在する。
- [ ] 呼び出し側ワークフロー（`quickstart-drift-check.yaml` など）・`notify-drift`・`plan` は無変更。

## スコープ外（spec に準拠・今回触らない）

- シークレット名不一致（`secrets.claude-api-key` vs 宣言 `anthropic-api-key`）の修正。
- Claude が plan を "No changes" にできなかった場合の No-change ゲート。
- PR のラベル付与 / assign。
- Slack 通知文言の変更。
- 既存ステップの `${{ }}` 直接展開を env 経由に書き換えること（新規 guard ステップのみ env 経由とする）。
