#!/usr/bin/env bash
# Single source of truth for the github-actions bot's git identity in the
# drift-fix flow. Sourced (not executed) by the scripts that need it.
#
# Two consumers must agree on BOT_EMAIL or the guard breaks:
#   - commit-and-push.sh stamps the bot's drift-fix commits with this email.
#   - has-human-commits.jq (invoked by guard-existing-pr.sh) excludes this
#     same email when deciding whether a human has taken over the PR branch.
# If the two diverged, the bot's own commits would read as human and the
# guard's update mode would be permanently disabled for every PR. Defining
# the literal here once removes that risk: guard-existing-pr.sh passes
# BOT_EMAIL into the jq via --arg, so a consumer that forgets to pass it
# fails loudly ("$bot_email is not defined") rather than silently diverging.
# shellcheck disable=SC2034  # consumed by sourcing scripts, not this file
BOT_NAME="github-actions[bot]"
# shellcheck disable=SC2034  # consumed by sourcing scripts, not this file
BOT_EMAIL="41898282+github-actions[bot]@users.noreply.github.com"
