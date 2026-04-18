---
description: Diagnose TCC / Screen Recording permission state.
---

Diagnose whether NotchyPrompter has the permissions it needs.

Run and report concisely:
1. Is the `.app` bundle present? `ls -la NotchyPrompter/NotchyPrompter.app/Contents/MacOS/NotchyPrompter`
2. Current signature: `codesign -dv --verbose=2 NotchyPrompter/NotchyPrompter.app 2>&1 | head -20`
3. Is it running? `pgrep -lf NotchyPrompter`
4. Recent TCC-related log messages from the app: `log show --predicate 'process == "NotchyPrompter"' --last 5m 2>/dev/null | grep -iE "tcc|permission|declined|screen recording" | tail -20` (may need the user to re-run with `sudo` if output is empty).

Then summarise: is the signature stable (ad-hoc signatures change every build → TCC resets), and what the user should do next (re-grant in System Settings → Privacy & Security → Screen Recording, then relaunch).
