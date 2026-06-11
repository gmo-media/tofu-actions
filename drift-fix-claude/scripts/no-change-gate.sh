#!/usr/bin/env bash
# Decide the no-change-gate verdict from the verification plan result.
#
# Usage: no-change-gate.sh PLAN_EXIT_CODE HAS_DIFF
#   PLAN_EXIT_CODE: exit code of `<tf-binary> plan -detailed-exitcode`
#                   (0 = no changes, 2 = changes present, 1 = error)
#   HAS_DIFF:       "true" if the working tree has local changes
#                   (git status --porcelain non-empty), else "false"
#
# Prints exactly one verdict to stdout:
#   pr        - drift fixed and changes exist -> create a normal PR
#   resolved  - nothing edited and no drift left -> already resolved, no PR
#   draft-pr  - changes exist but drift remains -> hand off as a draft PR
#   fail      - nothing to hand off (no edits with drift left, plan error,
#               or an unexpected exit code)
#
# Pure mapping with no side effects; exits non-zero only on invalid usage.
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 PLAN_EXIT_CODE HAS_DIFF" >&2
  exit 64
fi

PLAN_EXIT_CODE="$1"
HAS_DIFF="$2"

case "$HAS_DIFF" in
  true|false) ;;
  *)
    echo "HAS_DIFF must be 'true' or 'false', got: $HAS_DIFF" >&2
    exit 64
    ;;
esac

case "$PLAN_EXIT_CODE:$HAS_DIFF" in
  0:true)  echo "pr" ;;
  0:false) echo "resolved" ;;
  2:true)  echo "draft-pr" ;;
  *)       echo "fail" ;;
esac
