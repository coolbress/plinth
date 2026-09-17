#!/usr/bin/env bash
# markdownlint over every markdown file, at the one version `ci / docs` runs:
# the workflow calls this file, so the pin below is the only one. The first run
# downloads the package (network); later runs use npx's cache. Rules and
# ignores live in .markdownlint-cli2.jsonc.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="0.23.2"

command -v npx >/dev/null || { echo "  FAIL  npx not found: markdownlint needs Node.js (https://nodejs.org)"; exit 1; }
cd "$root" || exit 1
if ! npx --yes "markdownlint-cli2@$version" "**/*.md"; then
  echo "  FAIL  markdownlint-cli2 $version"; exit 1
fi
echo "  PASS  markdownlint-cli2 $version"
