---
description: Kill running app, rebuild, relaunch.
---

Kill any running NotchyPrompter, rebuild via `./build.sh`, then relaunch.

Steps:
1. `pkill -f NotchyPrompter || true`
2. `cd NotchyPrompter && ./build.sh` — if build fails, show only the last ~30 lines of error output and stop.
3. `open NotchyPrompter/NotchyPrompter.app`
4. Warn the user that Screen Recording TCC grant may need to be re-authorised (ad-hoc signature changes each build).
