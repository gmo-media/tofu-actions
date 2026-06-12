# Decide whether a drift-fix PR branch has commits from anyone other than
# the github-actions bot.
#
# This is the single source of truth for the "human commits" check used by
# the guard step in ../action.yaml: once a human has committed to the PR
# branch (review fixes, manual work on a draft PR, "Update branch" merge
# commits), ownership moves to the human and the bot must not re-run the
# fix on that branch. Exercised directly by ../tests/has-human-commits.test.sh.
#
# COUPLING (keep in sync): the bot email below must match the git user.email
# configured in commit-and-push.sh.
#
# An author counts as the bot when its email is the github-actions[bot]
# noreply address or its resolved login is "github-actions". Anything else
# (including authors GitHub could not resolve to a user: empty login)
# counts as human, so unknown authors fail safe toward skipping.
#
# Input : output of `gh pr view <num> --json commits` (an object with a
#         "commits" array; extra keys such as headRefName are ignored).
# Output: "true" if any commit has a non-bot author, else "false".
[ .commits[].authors[]
  | select(
      (.email != "41898282+github-actions[bot]@users.noreply.github.com")
      and (.login != "github-actions")
    )
]
| length > 0
