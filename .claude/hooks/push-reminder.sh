#!/usr/bin/env bash
# Advisory reminder before `git push`. Does NOT block.
# Wired as PreToolUse on Bash.

cmd=$(jq -r '.tool_input.command // empty')
[[ -z "$cmd" ]] && exit 0

# Match `git push` as a whole token (start of line, or after ;, &&, |, whitespace)
if echo "$cmd" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+push\b'; then
  cat >&2 <<'EOF'
── Push reminder ─────────────────────────────────────────────
If this is a release push (main or tag):
  • VERSION bumped?
  • CHANGELOG [Unreleased] promoted with today's date?
  • README / CHANGELOG TODOs reconciled?
  • ./build.sh succeeds?
  → Run /release <version> first if any of the above is no.
If feature branch / WIP: ignore this and proceed.
──────────────────────────────────────────────────────────────
EOF
fi

exit 0
