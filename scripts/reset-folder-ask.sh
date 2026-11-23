#!/usr/bin/env bash
# Quit GridBack, clear the saved folder question, and reset the system answers.
# The question can be offered again the next time GridBack opens.
set -euo pipefail

bundle_id="com.jimmythefallony.GridBack"

osascript -e 'tell application "GridBack" to quit' >/dev/null 2>&1 || true

for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  if ! pgrep -x GridBack >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

if pgrep -x GridBack >/dev/null 2>&1; then
  killall GridBack >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if ! pgrep -x GridBack >/dev/null 2>&1; then
      break
    fi
    sleep 0.25
  done
fi

if pgrep -x GridBack >/dev/null 2>&1; then
  echo "GridBack is still running. Quit it from the menu bar, then run this again." >&2
  exit 1
fi

for service in \
  SystemPolicyDownloadsFolder \
  SystemPolicyDesktopFolder \
  SystemPolicyDocumentsFolder \
  SystemPolicyRemovableVolumes
do
  tccutil reset "$service" "$bundle_id" || true
done

state="$HOME/Library/Application Support/GridBack/state.json"
if [[ -f "$state" ]]; then
  python3 - "$state" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path) as handle:
    saved = json.load(handle)
saved["askedLocations"] = []
saved["grantedLocations"] = []
with open(path, "w") as handle:
    json.dump(saved, handle, indent=2)
    handle.write("\n")
PY
fi

echo "Folder ask reset. Open GridBack to see the question again."
