#!/usr/bin/env bash
# The audit's guards against injected instructions (#1119): one repository per
# run, and git calls that run none of the audited repository's programs.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root/scripts/floor-check.py"
work="$(mktemp -d)" || { echo "audit-guard: could not make a temp folder" >&2; exit 1; }
trap 'rm -rf "$work"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; }

echo "-- every git call passes the fixed flags"
# floor-check.py: one helper makes them; no other line starts git.
if [ "$(grep -cE "[[(][[:space:]]*['\"]git['\"]" "$checker")" = 1 ] && ! grep -q 'shell=True' "$checker" && grep -qE '^GIT_SAFE = \("-c", "core\.fsmonitor=false", "-c", "core\.hooksPath=/dev/null"\)$' "$checker" \
   && grep -q 'env\["GIT_CONFIG_NOSYSTEM"\] = "1"' "$checker" && grep -q '"GIT_NO_LAZY_FETCH": "1"' "$checker"; then ok "floor-check.py: git runs only through git(), with GIT_SAFE and GIT_CONFIG_NOSYSTEM=1"
else bad "floor-check.py: a git call outside git(), or its flags changed"; grep -nE "[[(][[:space:]]*['\"]git['\"]|shell=True" "$checker" | sed 's/^/        /'; fi
# The one call that keeps the system level says why, in the helper.
if [ "$(grep -c 'system_config=True' "$checker")" = 1 ]; then ok "floor-check.py: one call keeps the system config (FC-G07, which reads every level's credential helpers)"
else bad "floor-check.py: system_config=True is not on exactly one call"; fi
gs="$root/scripts/guide-state.sh"
# A git command: at a line's start, after a separator, `$(`, or a keyword.
bare="$(sed 's/[[:space:]]#.*//' "$gs" | grep -nE '(^|[;&|(]|\$\()[[:space:]]*((!|if|then|elif|while|until|do)[[:space:]]+)*git[[:space:]]' \
  | grep -v 'git_safe() { GIT_CONFIG_NOSYSTEM=1 GIT_NO_LAZY_FETCH=1 git -c core.fsmonitor=false -c core.hooksPath=/dev/null "\$@"; }')"
if [ -z "$bare" ] && [ "$(grep -c 'git_safe -C' "$gs")" -ge 1 ]; then ok "guide-state.sh: git runs only through git_safe, with the flags and GIT_CONFIG_NOSYSTEM=1"
else bad "guide-state.sh: a git call outside git_safe"; printf '%s\n' "$bare" | sed 's/^/        /'; fi
# floor-report.py, which the skill pipes the checker into, reads the checkout too.
rep="$root/scripts/floor-report.py"
if [ "$(grep -cE "[[(][[:space:]]*['\"]git['\"]" "$rep")" = 1 ] && grep -qF '["git", "-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "-C"' "$rep" \
   && grep -q '"GIT_CONFIG_NOSYSTEM": "1", "GIT_NO_LAZY_FETCH": "1"' "$rep"; then ok "floor-report.py: git runs only through git(), with the flags and GIT_CONFIG_NOSYSTEM=1"
else bad "floor-report.py: a git call outside git(), or its flags changed"; grep -nE "[[(][[:space:]]*['\"]git['\"]" "$rep" | sed 's/^/        /'; fi
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
rm -f "$work/marker"
# The skill's whole pipe: the checker's JSON into floor-report.py, with --repo so
# the reporter decides on its note (git status). Its cache goes to the work folder.
(cd "$repo" && python3 "$checker" --root . --repo o/r --no-network --sandbox --plugins --credentials --format json 2>/dev/null \
  | XDG_CACHE_HOME="$work/cache" python3 "$rep" --root . >"$work/report" 2>&1); rc_r=$?
if [ "$rc_r" -le 1 ] && [ -s "$work/report" ] && [ ! -e "$work/marker" ]; then ok "the skill's pipe, checker into floor-report.py with --repo, ran (exit $rc_r) and no fsmonitor program"
else bad "the skill's pipe crashed (exit $rc_r) or ran the repository's fsmonitor program"; sed 's/^/        /' "$work/report" | head -5; fi

echo "-- filter drivers the checkout configures: nothing runs them (#1278)"
# A clean filter, a process filter, one from an included file and one whose
# name holds a `=`, each applied to a tracked file changed at the same size.
frepo="$work/frepo"; mkdir -p "$frepo"; git -C "$frepo" init -q
cat > "$work/filter" <<EOF
#!/bin/sh
echo ran >> "$work/marker"
cat
EOF
chmod +x "$work/filter"
for f in a b c d; do echo "$f$f" > "$frepo/$f"; done
git -C "$frepo" add a b c d; git -C "$frepo" -c user.name=t -c user.email=t@t commit -q -m init
printf 'a filter=fa\nb filter=fb\nc filter=fc\nd filter=x=y\n' > "$frepo/.git/info/attributes"
git -C "$frepo" config filter.fa.clean "$work/filter"
git -C "$frepo" config filter.fa.required true
git -C "$frepo" config filter.fb.process "$work/filter"
printf '[filter "fc"]\n\tclean = %s\n' "$work/filter" > "$work/included.cfg"
git -C "$frepo" config include.path "$work/included.cfg"
git -C "$frepo" config 'filter.x=y.clean' "$work/filter"
touch_all() { local t; for t in a b c d; do echo "${t}Z" > "$frepo/$t"; done; }
# Each filter on its own, to show each fixture line runs a program unprotected.
for f in a b c d; do
  touch_all; rm -f "$work/marker"
  GIT_CONFIG_NOSYSTEM=1 git -c core.fsmonitor=false -c core.hooksPath=/dev/null -C "$frepo" status --porcelain -- "$f" >/dev/null 2>&1
  if [ -s "$work/marker" ]; then ok "the fixture works: with only the #1119 flags, git status runs the filter on $f"
  else bad "the filter on $f does not run under a plain status: the cases below would prove nothing for it"; fi
done
touch_all; rm -f "$work/marker"
if python3 - "$checker" "$frepo" <<'PY'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("fc", sys.argv[1]); fc = importlib.util.module_from_spec(spec)
sys.argv, repo = ["fc"], sys.argv[2]; spec.loader.exec_module(fc)
sys.exit(fc.git(Path(repo), "status", "--porcelain", capture_output=True).returncode)
PY
then
  if [ ! -e "$work/marker" ]; then ok "floor-check.py's git() runs that status and no filter program"
  else bad "floor-check.py's git() ran a filter program"; fi
else bad "floor-check.py's git() could not run git status"; fi
touch_all; rm -f "$work/marker"
if python3 - "$rep" "$frepo" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("fr", sys.argv[1]); fr = importlib.util.module_from_spec(spec)
sys.argv, repo = ["fr"], sys.argv[2]; spec.loader.exec_module(fr)
out = fr.git(repo, "status", "--porcelain")
sys.exit(0 if out and " a" in out else 1)   # it ran, and saw the change
PY
then
  if [ ! -e "$work/marker" ]; then ok "floor-report.py's git() runs that status, sees the change, and no filter program"
  else bad "floor-report.py's git() ran a filter program"; fi
else bad "floor-report.py's git() did not run git status, or saw no change"; fi
touch_all; rm -f "$work/marker"
(cd "$frepo" && python3 "$checker" --root . --repo o/r --no-network --sandbox --plugins --credentials --format json 2>/dev/null \
  | XDG_CACHE_HOME="$work/cache" python3 "$rep" --root . >"$work/report" 2>&1); rc_r=$?
if [ "$rc_r" -le 1 ] && [ -s "$work/report" ] && [ ! -e "$work/marker" ]; then ok "the skill's pipe ran (exit $rc_r) and no filter program"
else bad "the skill's pipe crashed (exit $rc_r) or ran a filter program"; sed 's/^/        /' "$work/report" | head -5; fi
# The person's own (global) and the machine's (system) filters stay: an LFS
# install is theirs. The pairs come after any the caller already set.
if python3 - "$checker" "$rep" <<'PY'
import importlib.util, sys
mods = []
for i, path in enumerate(sys.argv[1:3]):
    spec = importlib.util.spec_from_file_location(f"m{i}", path); m = importlib.util.module_from_spec(spec)
    sys.argv = ["m"]; spec.loader.exec_module(m); mods.append(m)
listing = b"global\0filter.lfs.clean\ngit-lfs clean -- %f\0system\0filter.s.clean\nx\0local\0filter.a=b.c.clean\nx\0worktree\0filter.w.process\nx\0"
fc, fr = mods
got = fc.filters_off(listing, {"GIT_CONFIG_COUNT": "2"})
keys = {got[k] for k in got if k.startswith("GIT_CONFIG_KEY_")}
assert got["GIT_CONFIG_COUNT"] == "10" and "GIT_CONFIG_KEY_2" in got and "GIT_CONFIG_KEY_1" not in got, got
assert {"filter.a=b.c.clean", "filter.a=b.c.process", "filter.w.clean", "filter.w.required"} <= keys, keys
assert not any(k.startswith(("filter.lfs.", "filter.s.")) for k in keys), keys
assert fc.filters_off(b"global\0filter.lfs.clean\nx\0", {}) == {}
assert fr.filters_off(listing).keys() == fc.filters_off(listing, {}).keys()
PY
then ok "only the checkout's filters are emptied (global and system kept), a name with = included, after the caller's own pairs"
else bad "filters_off"; fi

echo "-- a submodule's own config: the reporter's status does not enter it"
srepo="$work/srepo"; sub="$work/sub"; mkdir -p "$srepo" "$sub"
git -C "$sub" init -q; echo s > "$sub/f"; echo 'f filter=s' > "$sub/.gitattributes"
git -C "$sub" add f .gitattributes; git -C "$sub" -c user.name=t -c user.email=t@t commit -q -m init
git -C "$srepo" init -q; git -C "$srepo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$srepo" -c protocol.file.allow=always submodule add -q "$sub" sub >/dev/null 2>&1
git -C "$srepo" -c user.name=t -c user.email=t@t commit -q -m sub
git -C "$srepo/sub" config filter.s.clean "$work/filter"; echo t > "$srepo/sub/f"; rm -f "$work/marker"
GIT_CONFIG_NOSYSTEM=1 git -c core.fsmonitor=false -c core.hooksPath=/dev/null -C "$srepo" status --porcelain >/dev/null 2>&1
if [ -s "$work/marker" ]; then ok "the fixture works: the parent's plain status runs the submodule's filter"
else bad "the submodule fixture runs nothing: the case below would prove nothing"; fi
echo u > "$srepo/sub/f"; rm -f "$work/marker"
(cd "$srepo" && python3 "$checker" --root . --repo o/r --no-network --format json 2>/dev/null \
  | XDG_CACHE_HOME="$work/cache" python3 "$rep" --root . >"$work/report" 2>&1); rc_r=$?
if [ "$rc_r" -le 1 ] && [ -s "$work/report" ] && [ ! -e "$work/marker" ]; then ok "the skill's pipe ran (exit $rc_r) and not the submodule's filter"
else bad "the skill's pipe crashed (exit $rc_r) or ran the submodule's filter"; fi
# guide-state.sh's git calls are rev-parse only, which reads no file content.
# shellcheck disable=SC2016  # the pattern matches the script's literal text
if [ "$(grep -v '^git_safe()' "$gs" | grep -oE 'git_safe[[:space:]]+(-C[[:space:]]+"[^"]*"[[:space:]]+)?[a-z-]+' | awk '{print $NF}' | sort -u)" = rev-parse ]; then ok "guide-state.sh: every git call is rev-parse, which runs no filter"
else bad "guide-state.sh makes a git call other than rev-parse: give git_safe the filter protection"; grep -n 'git_safe -C' "$gs" | sed 's/^/        /'; fi

echo "-- a promisor remote the checkout names: status fetches nothing (#1278)"
# A rename-detecting status needs a deleted blob; the checkout says a promisor
# remote holds it, and that remote's URL is a program (ext::).
prepo="$work/prepo"; mkdir -p "$prepo"; git -C "$prepo" init -q
seq 1 200 > "$prepo/A"; git -C "$prepo" add A; git -C "$prepo" -c user.name=t -c user.email=t@t commit -q -m init
blob="$(git -C "$prepo" rev-parse HEAD:A)"
git -C "$prepo" rm -q A; { seq 1 199; echo x; } > "$prepo/B"; git -C "$prepo" add B
rm -f "$prepo/.git/objects/${blob:0:2}/${blob:2}"
git -C "$prepo" config core.repositoryformatversion 1; git -C "$prepo" config extensions.partialClone origin
git -C "$prepo" config remote.origin.promisor true; git -C "$prepo" config protocol.ext.allow always
git -C "$prepo" config remote.origin.url "ext::sh -c touch% $work/marker"
rm -f "$work/marker"
GIT_CONFIG_NOSYSTEM=1 git -c core.fsmonitor=false -c core.hooksPath=/dev/null -C "$prepo" status --porcelain >/dev/null 2>&1
if [ -e "$work/marker" ]; then ok "the fixture works: with only the #1119 flags, git status runs the promisor remote's program"
else bad "the promisor fixture runs nothing: the cases below would prove nothing"; fi
rm -f "$work/marker"
python3 - "$checker" "$prepo" >/dev/null 2>&1 <<'PY'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("fc", sys.argv[1]); fc = importlib.util.module_from_spec(spec)
sys.argv, repo = ["fc"], sys.argv[2]; spec.loader.exec_module(fc)
fc.git(Path(repo), "status", "--porcelain", capture_output=True)
PY
if [ ! -e "$work/marker" ]; then ok "floor-check.py's git() runs that status and no promisor program"
else bad "floor-check.py's git() ran the promisor remote's program"; fi
rm -f "$work/marker"
(cd "$prepo" && python3 "$checker" --root . --repo o/r --no-network --format json 2>/dev/null \
  | XDG_CACHE_HOME="$work/cache" python3 "$rep" --root . >"$work/report" 2>&1); rc_r=$?
if [ "$rc_r" -le 1 ] && [ -s "$work/report" ] && [ ! -e "$work/marker" ]; then ok "the skill's pipe ran (exit $rc_r) and no promisor program"
else bad "the skill's pipe crashed (exit $rc_r) or ran the promisor remote's program"; fi
rm -f "$work/marker"
git_safe -C "$prepo" status --porcelain >/dev/null 2>&1
if [ ! -e "$work/marker" ]; then ok "guide-state.sh's git_safe, on that status, runs no promisor program"
else bad "guide-state.sh's git_safe ran the promisor remote's program"; fi

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
