#!/bin/bash
# Fills the empty workspace with the template render scripts/eval-suite-probe.sh
# made (it writes the path in place of @FIXTURE@), as a beginner's clone has it:
# committed, with the lockfile's packages synced.
set -eu
cp -R "@FIXTURE@/." .
uv sync -q --frozen
git init -q -b main
git add -A
git -c user.name=trial -c user.email=trial@example.invalid -c commit.gpgsign=false commit -qm initial
