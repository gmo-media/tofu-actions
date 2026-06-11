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
