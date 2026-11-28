#!/usr/bin/env bash
# The audit's guards against injected instructions (#1119): one repository per
# run, and git calls that run none of the audited repository's programs.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root/scripts/floor-check.py"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

echo "-- every git call passes the fixed flags"
# floor-check.py: one helper makes them; no other line starts git.
if [ "$(grep -cE "[[(][[:space:]]*['\"]git['\"]" "$checker")" = 1 ] && ! grep -q 'shell=True' "$checker" && grep -qE '^GIT_SAFE = \("-c", "core\.fsmonitor=false", "-c", "core\.hooksPath=/dev/null"\)$' "$checker" \
   && grep -q '"GIT_CONFIG_NOSYSTEM": "1"' "$checker"; then ok "floor-check.py: git runs only through git(), with GIT_SAFE and GIT_CONFIG_NOSYSTEM=1"
else bad "floor-check.py: a git call outside git(), or its flags changed"; grep -nE "[[(][[:space:]]*['\"]git['\"]|shell=True" "$checker" | sed 's/^/        /'; fi
# The one call that keeps the system level says why, in the helper.
if [ "$(grep -c 'system_config=True' "$checker")" = 1 ]; then ok "floor-check.py: one call keeps the system config (FC-G07, which reads every level's credential helpers)"
else bad "floor-check.py: system_config=True is not on exactly one call"; fi
gs="$root/scripts/guide-state.sh"
# A git command: at a line's start, after a separator, `$(`, or a keyword.
bare="$(sed 's/[[:space:]]#.*//' "$gs" | grep -nE '(^|[;&|(]|\$\()[[:space:]]*((!|if|then|elif|while|until|do)[[:space:]]+)*git[[:space:]]' \
  | grep -v 'git_safe() { GIT_CONFIG_NOSYSTEM=1 git -c core.fsmonitor=false -c core.hooksPath=/dev/null "\$@"; }')"
if [ -z "$bare" ] && [ "$(grep -c 'git_safe -C' "$gs")" -ge 1 ]; then ok "guide-state.sh: git runs only through git_safe, with the flags and GIT_CONFIG_NOSYSTEM=1"
else bad "guide-state.sh: a git call outside git_safe"; printf '%s\n' "$bare" | sed 's/^/        /'; fi
if ! grep -qE '\["git"|subprocess\.run\(\["git' "$root/scripts/records-check.py"; then ok "records-check.py: makes no git call"
else bad "records-check.py: makes a git call without the flags"; fi

echo "-- a .git/config whose fsmonitor writes a marker: nothing runs it"
repo="$work/repo"; mkdir -p "$repo"; git -C "$repo" init -q; git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
cat > "$work/fsmonitor" <<EOF
#!/bin/sh
echo ran >> "$work/marker"
EOF
chmod +x "$work/fsmonitor"
git -C "$repo" config core.fsmonitor "$work/fsmonitor"
# The fixture is real: an ordinary git status runs the program.
git -C "$repo" status >/dev/null 2>&1
if [ -s "$work/marker" ]; then ok "the fixture works: a plain git status runs its fsmonitor"
else bad "the fixture does not run its fsmonitor: the cases below would prove nothing"; fi
rm -f "$work/marker"
# The flags are what stops it: the same status with them runs nothing.
GIT_CONFIG_NOSYSTEM=1 git -c core.fsmonitor=false -c core.hooksPath=/dev/null -C "$repo" status >/dev/null 2>&1
if [ ! -e "$work/marker" ]; then ok "the same git status with the fixed flags runs no fsmonitor program"
else bad "the fixed flags do not stop the fsmonitor program"; fi
rm -f "$work/marker"
# The helpers themselves, on that same status: floor-check.py's git() and
# guide-state.sh's git_safe, read out of their files.
if python3 - "$checker" "$repo" <<'PY'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("fc", sys.argv[1]); fc = importlib.util.module_from_spec(spec)
sys.argv, repo = ["fc"], sys.argv[2]; spec.loader.exec_module(fc)
sys.exit(fc.git(Path(repo), "status", capture_output=True).returncode)
PY
then
  if [ ! -e "$work/marker" ]; then ok "floor-check.py's git() runs that status and no fsmonitor program"
  else bad "floor-check.py's git() ran the fsmonitor program"; fi
else bad "floor-check.py's git() could not run git status"; fi
rm -f "$work/marker"
eval "$(grep -E '^git_safe\(\) \{' "$gs")"
if git_safe -C "$repo" status >/dev/null 2>&1 && [ ! -e "$work/marker" ]; then ok "guide-state.sh's git_safe runs that status and no fsmonitor program"
else bad "guide-state.sh's git_safe ran the fsmonitor program, or did not run"; fi
rm -f "$work/marker"
# And whole runs, which must have run (exit 0 or 1), not crashed early.
python3 "$checker" --root "$repo" --no-network --sandbox --plugins --credentials >/dev/null 2>&1; rc=$?
"$root/scripts/guide-state.sh" "$repo" >/dev/null 2>&1; rc_g=$?
if [ "$rc" -le 1 ] && [ "$rc_g" -le 1 ] && [ ! -e "$work/marker" ]; then ok "a full floor-check run and a guide-state.sh run ran (exit $rc, $rc_g) and no fsmonitor program"
else bad "a full run crashed (exit $rc, $rc_g) or ran the repository's fsmonitor program"; fi

echo "-- one repository per run"
if python3 - "$checker" <<'PY'

import importlib.util, sys
spec = importlib.util.spec_from_file_location("fc", sys.argv[1]); fc = importlib.util.module_from_spec(spec)
sys.argv = ["fc"]; spec.loader.exec_module(fc)
fc.audited = "o/r"
pin = fc.new_project_pin()
for path in ["repos/o/r/issues", "repos/O/R", "repos/o/.github/contents/x", f"repos/{fc.PLINTH_REPO}/tags", f"repos/{pin[0]}/contents/copier.yml"]:
    fc.guard_repository(path)
fc.guard_repository("projects/o%2Fr/labels", "projects/")
for path, prefix in [("repos/x/y/issues", "repos/"), ("repos/o/other", "repos/"), ("repos/x/.github", "repos/"),
                     ("projects/x%2Fy", "projects/")]:
    try:
        fc.guard_repository(path, prefix)
    except fc.ForeignRepository:
        continue
    print(f"        not stopped: {path}"); sys.exit(1)
# Through api() itself, before any fixture or network is read.
try:
    fc.api("repos/x/y/issues", False)
except fc.ForeignRepository:
    pass
else:
    sys.exit(1)
PY
then ok "an API call naming another repository stops the run; the audited one, its owner's .github, plinth and the template pass"
else bad "the repository guard"; fi
# Without --repo only plinth and the template are allowed.
if python3 - "$checker" <<'PY'

import importlib.util, sys
spec = importlib.util.spec_from_file_location("fc", sys.argv[1]); fc = importlib.util.module_from_spec(spec)
sys.argv = ["fc"]; spec.loader.exec_module(fc)
fc.audited = None
fc.guard_repository(f"repos/{fc.PLINTH_REPO}/tags")
try:
    fc.guard_repository("repos/o/r")
except fc.ForeignRepository:
    sys.exit(0)
sys.exit(1)
PY
then ok "without --repo, a request for any other repository stops the run"
else bad "without --repo, the guard"; fi

echo "-- a secret finding never prints the value"
for f in "$root/.github/workflows/python-ci.yml" "$root/gitlab/python-ci.yml"; do
  calls="$(sed 's/[[:space:]]#.*//' "$f" | grep -E 'gitleaks (git|dir|detect) ')"
  if [ -n "$calls" ] && ! grep -v -- '--redact' <<<"$calls" | grep -q .; then ok "$(basename "$(dirname "$f")")/$(basename "$f"): every gitleaks scan passes --redact"
  else bad "$f: a gitleaks scan without --redact"; printf '%s\n' "$calls" | sed 's/^/        /'; fi
done

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
