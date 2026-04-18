---
description: Cut a release — gather context, update VERSION / CHANGELOG / README, commit, tag.
argument-hint: <version> (e.g. 0.1.1)
---

Cut release **$ARGUMENTS**. Do not push — the final push stays user-initiated.

## 1. Gather context (read-only)
- Current `VERSION` — confirm $ARGUMENTS > current.
- Previous tag: `git describe --tags --abbrev=0 2>/dev/null || echo "(none)"`
- Commits since last tag: `git log --pretty=format:'%s (%h)' <prev-tag>..HEAD` (use full history if no previous tag).
- Scan `README.md` "Roadmap / TODO" section and note items the commit summary suggests are now done. Do **not** strike them automatically — list candidates for the user to confirm in step 4.

## 2. Verify the build
Run `cd NotchyPrompter && ./build.sh`. If it fails, stop and show only the last ~30 lines of error output.

## 3. Propose the diff (do not apply yet)
Produce a diff that:
- Bumps `VERSION` to `$ARGUMENTS`.
- In `CHANGELOG.md`: renames `## [Unreleased]` → `## [$ARGUMENTS] — <today in YYYY-MM-DD>`; adds a fresh empty `## [Unreleased]` above it; updates link refs at the bottom. If the `[Unreleased]` section is empty, seed it from the commit summary (step 1) grouped as **Added / Changed / Fixed** — flag that the user should edit.
- In `README.md`: strike roadmap items the user confirms as done.

## 4. Confirm
Show the full diff. Ask the user to confirm **and** to review the seeded CHANGELOG wording before any write.

## 5. Apply + commit + tag
- Write the files.
- `git add VERSION CHANGELOG.md README.md`
- `git commit -m "Release v$ARGUMENTS"`
- `git tag v$ARGUMENTS`

## 6. Remind (do not push)
Tell the user: push with `git push origin main --tags` when ready. Do not push automatically.

Signing / notarisation is separate — use `/sign-notarize`.
