---
description: Cut a release — bump VERSION, promote CHANGELOG, tag.
argument-hint: <version> (e.g. 0.1.1)
---

Cut release **$ARGUMENTS**.

Steps (ask for confirmation before the git tag):
1. Read current `VERSION` — confirm $ARGUMENTS > current.
2. Update `VERSION` to `$ARGUMENTS`.
3. In `CHANGELOG.md`:
   - Rename `## [Unreleased]` → `## [$ARGUMENTS] — <today's date in YYYY-MM-DD>`
   - Add an empty new `## [Unreleased]` section above it.
   - Update the link refs at the bottom.
4. Show the diff. Ask user to confirm before proceeding.
5. On confirmation: `git add VERSION CHANGELOG.md && git commit -m "Release v$ARGUMENTS"`
6. `git tag v$ARGUMENTS`
7. Remind user: push with `git push origin main --tags` (do **not** push automatically).

Do not sign / notarize here — use `/sign-notarize` separately.
