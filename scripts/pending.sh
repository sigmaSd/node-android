#!/usr/bin/env bash
# Prints, as a JSON array, the Node versions to build: the newest release of every major that has a
# patches/<major>/ folder, unless this repository already has a release for it. Run by the workflow daily;
# needs `gh` (GH_TOKEN, GH_REPO), `curl` and `jq`.
set -euo pipefail
cd "$(dirname "$0")/.."
index=$(curl -fsSL https://nodejs.org/dist/index.json)
pending=()
for dir in patches/*/; do
  major=$(basename "$dir")
  latest=$(jq -r --arg m "v$major." 'map(select(.version | startswith($m)))[0].version // empty' <<<"$index")
  [ -n "$latest" ] || continue
  gh release view "$latest" >/dev/null 2>&1 && continue
  pending+=("${latest#v}")
done
printf '%s\n' "${pending[@]+"${pending[@]}"}" | jq -Rcs 'split("\n") | map(select(. != ""))'
