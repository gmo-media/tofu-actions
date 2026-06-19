#!/usr/bin/env bash
# Decide the no-change-gate verdict from the verification plan result.
#
# Usage: no-change-gate.sh PLAN_EXIT_CODE HAS_DIFF HAS_REPLACE
#   PLAN_EXIT_CODE: exit code of `<tf-binary> plan -detailed-exitcode`
#                   (0 = no changes, 2 = changes present, 1 = error)
#   HAS_DIFF:       "true" if the working tree has local changes
#                   (git status --porcelain non-empty), else "false"
#   HAS_REPLACE:    "true" if the plan output contains a resource
#                   replacement (-/+ or +/- "must be replaced"), else "false"
#
# Prints exactly one verdict to stdout:
#   pr           - drift fixed and changes exist -> create a normal PR
#   resolved     - nothing edited and no drift left -> already resolved, no PR
#   draft-pr     - changes exist but drift remains -> hand off as a draft PR
#                  (create-only / destroy-only changes are tolerated here)
#   replace-fail - the remaining plan would destroy AND recreate a resource
#                  -> never hand off a PR that replaces resources
#   fail         - nothing to hand off (no edits with drift left, plan error,
#                  an unexpected exit code, or inconsistent inputs)
#
# Pure mapping with no side effects; exits non-zero only on invalid usage.
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "usage: $0 PLAN_EXIT_CODE HAS_DIFF HAS_REPLACE" >&2
  exit 64
fi

PLAN_EXIT_CODE="$1"
HAS_DIFF="$2"
HAS_REPLACE="$3"

for flag in "HAS_DIFF=$HAS_DIFF" "HAS_REPLACE=$HAS_REPLACE"; do
  case "${flag#*=}" in
    true|false) ;;
    *)
      echo "${flag%%=*} must be 'true' or 'false', got: ${flag#*=}" >&2
      exit 64
      ;;
  esac
done

# "No changes" output (exit 0) cannot contain a replacement; that
# combination means the inputs are inconsistent -> fall through to fail.
case "$PLAN_EXIT_CODE:$HAS_DIFF:$HAS_REPLACE" in
  0:true:false)  echo "pr" ;;
  0:false:false) echo "resolved" ;;
  2:true:true)   echo "replace-fail" ;;
  2:true:false)  echo "draft-pr" ;;
  *)             echo "fail" ;;
esac
