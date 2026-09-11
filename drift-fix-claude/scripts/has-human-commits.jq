# Decide whether a drift-fix PR branch has commits from anyone other than
# the github-actions bot.
#
# This is the single source of truth for the "human commits" check used by
# the guard step in ../action.yaml: once a human has committed to the PR
# branch (review fixes, manual work on a draft PR, "Update branch" merge
# commits), ownership moves to the human and the bot must not re-run the
# fix on that branch.
#
# The bot email is passed in via --arg bot_email from the single source of
# truth in bot-identity.sh (the same value commit-and-push.sh stamps on the
# bot's commits); the invocation in guard-existing-pr.sh wires it through.
# Referencing an undefined $bot_email makes jq fail loudly, so a caller that
# forgets the --arg cannot silently misclassify the bot's own commits.
#
# An author counts as the bot when its email is the github-actions[bot]
# noreply address or its resolved login is "github-actions". Anything else
# (including authors GitHub could not resolve to a user: empty login)
# counts as human, so unknown authors fail safe toward skipping.
#
# Input : output of `gh pr view <num> --json commits` (an object with a
#         "commits" array; extra keys such as headRefName are ignored).
# Arg   : --arg bot_email <github-actions bot noreply email>
# Output: "true" if any commit has a non-bot author, else "false".
[ .commits[].authors[]
  | select(
      (.email != $bot_email)
      and (.login != "github-actions")
    )
]
| length > 0
