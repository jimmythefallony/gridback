#!/usr/bin/env bash
# Fails if the app or Core sources can open a network connection.
# If update checks are ever added, update this allowlist and the
# "Nothing leaves your Mac" copy in the same PR.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

# Lines that contain one of these snippets are not a network connection.
allow=(
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd"
  "x-apple.systempreferences:"
)

pattern='import Network|URLSession|WebKit|URLRequest|https://|http://'
failed=0

while IFS= read -r line; do
  allowed=0
  for snippet in "${allow[@]}"; do
    if [[ "$line" == *"$snippet"* ]]; then
      allowed=1
      break
    fi
  done
  if [[ "$allowed" -eq 0 ]]; then
    printf '%s\n' "$line" >&2
    failed=1
  fi
done < <(grep -R -n -E -e "$pattern" \
  --include='*.swift' --include='*.plist' \
  "$root/Sources/GridBackCore" "$root/GridBackApp" || true)

if [[ "$failed" -ne 0 ]]; then
  echo "Network use is not allowed in the app or Core sources." >&2
  exit 1
fi
