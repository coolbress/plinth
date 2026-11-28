#!/usr/bin/env bash
# What scripts/floor-check.py prints stays byte for byte while its checks move
# to ids and states (#1103). Every `python3 "$checker" ...` that
# tests/floor-check-cases.sh makes is recorded: its arguments, exit code,
# stdout and --verdicts file, the CI form (--actions-token --verdicts) among
# them, and each run that asked for no --verdicts file again with one; the
# records, with the fixtures' temporary paths written as $WORK and
# this checkout as $ROOT, are compared with
# tests/fixtures/floor-check-golden/cases.txt. A run the cases test makes
# another way (a copy of the checker, another interpreter) is not recorded.
#
# The same records carry the ids and states the checker emitted, read
# against its REGISTRY: every emitted id is registered, and every state a
# registered id declares is reached by some fixture or listed in the entry's
# `unreached` with why. The list of what no fixture reaches is printed; it
# is not a claim that the rest is covered beyond the fixtures.
#
#   tests/floor-check-golden.sh           compare
#   tests/floor-check-golden.sh --write   rewrite the golden file (a change of output is reviewed in its diff)
#
# It runs the whole cases test once (a few minutes); the cases' own verdicts
# are that test's to judge, not this one's.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root/scripts/floor-check.py"
golden="$root/tests/fixtures/floor-check-golden/cases.txt"
write=0; [ "${1:-}" = "--write" ] && write=1
py="$(command -v python3)" || { echo "  FAIL  no python3"; exit 1; }
"$py" -c 'import sys; sys.exit(sys.version_info < (3, 11))' \
  || { echo "  FAIL  needs python3 3.11 or later, as the runner has; got $("$py" --version 2>&1)"; exit 1; }

work="$(mktemp -d "${TMPDIR:-/tmp}/floor-golden.XXXXXX")" || { echo "floor-check-golden: could not make a temp folder" >&2; exit 1; }; trap 'rm -rf "$work"' EXIT
work="$(cd "$work" && pwd -P)"
mkdir -p "$work/bin" "$work/records" "$work/tmp"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS  $1"; }
bad() { fail=$((fail+1)); echo "  FAIL  $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/        /'; return 0; }

# Offline, the checker reads a GitLab include only with a PyYAML in its own
# python3, and without one prints a SKIP naming that interpreter's path: the
# output would depend on the machine (the runner's python3 has PyYAML, a
# Homebrew one has none). So it is always recorded with PyYAML: when this
# python3 has none, the GitLab floor-check job's own PyYAML, pinned by hash,
# binary wheels only, goes into a venv under $work, as the checker installs
# it with the network, and that venv's python is the one used. The output
# without PyYAML is tests/floor-check-cases.sh's to judge, on a machine that
# has none.
if ! "$py" -c 'import yaml' 2>/dev/null; then
  "$py" - "$checker" > "$work/req.txt" <<'PY' || { echo "  FAIL  the GitLab job's pinned PyYAML could not be read"; exit 1; }
import importlib.util, sys
spec = importlib.util.spec_from_file_location("floor_check", sys.argv[1])
fc = importlib.util.module_from_spec(spec); spec.loader.exec_module(fc)
req = fc.gitlab_job_block("REQ")
sys.exit(req is None or sys.stdout.write(req) < 0)
PY
  "$py" -m venv "$work/yaml" && "$work/yaml/bin/python" -m pip install --quiet --disable-pip-version-check \
      --require-hashes --only-binary :all: --no-deps -r "$work/req.txt" \
    || { echo "  FAIL  $py has no PyYAML and the GitLab job's pinned PyYAML did not install (it needs the network)"; exit 1; }
  py="$work/yaml/bin/python"
fi

# The python3 the cases test finds first: `python3 <checker> ...` goes to the
# recorder, everything else to the real interpreter. The paths are written
# in, so a case run under `env -i` is recorded too.
cat > "$work/bin/python3" <<SH
#!/bin/sh
if [ "\${1:-}" = "$checker" ]; then
  shift; exec "$py" "$root/tests/lib/floor-check-record.py" "$work/records" "$checker" "\$@"
fi
exec "$py" "\$@"
SH
chmod +x "$work/bin/python3"

PATH="$work/bin:$PATH" TMPDIR="$work/tmp" "$root/tests/floor-check-cases.sh" > "$work/cases.log" 2>&1
echo "  ($(tail -1 "$work/cases.log") in tests/floor-check-cases.sh, judged there)"

"$py" - "$work/records" "$root" "$HOME" > "$work/cases.txt" <<'PY'
import json, re, sys
from pathlib import Path
records, root, home = sys.argv[1:]
# A directory mktemp made (tmp.XXXXXXXXXX under $TMPDIR, /tmp or macOS's
# /var/folders/.../T, which it uses whatever $TMPDIR says), with every
# directory above it, written as it was passed or as resolved.
work = re.compile(r"(?:/[^/\s'\"=:]+)*/tmp\.[A-Za-z0-9]{6,}")
# A not yet confirmed line cut at 300 characters inside a temporary path is cut
# at another place on another machine, whose path is longer or shorter: from
# that path on, the cut is written as one placeholder.
cut = re.compile(r"^(not yet confirmed: .*?)/\S*tmp\..*?\.\.\.(; run /plinth:floor-check where it can read this: \S+)$",
                 re.MULTILINE)
def norm(s: str) -> str:
    s = cut.sub(r"\1<a temporary path, then cut>\2", s)
    s = work.sub("$WORK", s)
    return s.replace(root, "$ROOT").replace(home, "$HOME")
out = []
for f in sorted(Path(records).glob("*.json")):
    r = json.loads(f.read_text(encoding="utf-8"))
    out.append(f"=== {norm(' '.join(r['args']))}\n--- exit {r['exit']}\n--- stdout\n{norm(r['stdout'])}")
    if r["verdicts"] is not None:
        out.append(f"--- verdicts\n{norm(r['verdicts'])}")
    if r.get("second"):
        out.append(f"--- again with --verdicts: exit {r['second']['exit']}\n{norm(r['second']['verdicts'])}")
sys.stdout.write("".join(s if s.endswith("\n") else s + "\n" for s in out))
PY
n="$(grep -c '^=== ' "$work/cases.txt")"
ci_form="$(grep -E '^=== ' "$work/cases.txt" | grep -c -- '--actions-token.*--verdicts\|--verdicts.*--actions-token')"
want="$(grep -c '^=== ' "$golden" 2>/dev/null || echo 0)"
if [ "$n" -gt 100 ] && [ "$n" -ge "$want" ] && [ "$ci_form" -gt 0 ]; then ok "$n checker runs recorded, $ci_form of them in the CI form (--actions-token --verdicts)"
else bad "$n checker runs recorded, $want in the golden file ($ci_form in the CI form): the cases test did not run as it should" "$(tail -20 "$work/cases.log")"; fi

# The runs whose root has no .plinth-adoption.yml (#1112) are in the
# comparison below: they stay byte for byte the golden ones through every
# ticket that reads that file.
bare="$("$py" -c 'import json, sys
from pathlib import Path
print(sum(not json.loads(f.read_text(encoding="utf-8")).get("adoption", True) for f in Path(sys.argv[1]).glob("*.json")))' "$work/records")"
if [ "${bare:-0}" -gt 0 ]; then ok "$bare recorded runs read a root with no .plinth-adoption.yml, and are compared below"
else bad "no recorded run reads a root without .plinth-adoption.yml: nothing holds the output without one"; fi

if [ "$write" = 1 ]; then
  mkdir -p "$(dirname "$golden")"; cp "$work/cases.txt" "$golden"; echo "  wrote $golden"
elif d="$(diff "$golden" "$work/cases.txt")"; then ok "stdout, exit code and --verdicts file of every recorded run are byte for byte the golden ones"
else bad "the output differs from tests/fixtures/floor-check-golden/cases.txt (a change of words is reviewed: rerun with --write)" "$(head -60 <<<"$d")"; fi

# The ids against the registry.
"$py" - "$checker" "$work/records" > "$work/ids.txt" <<'PY'
import importlib.util, json, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("floor_check", sys.argv[1])
fc = importlib.util.module_from_spec(spec); spec.loader.exec_module(fc)
reg = fc.REGISTRY
reached: dict[str, set[str]] = {}
for f in Path(sys.argv[2]).glob("*.json"):
    for line in json.loads(f.read_text(encoding="utf-8"))["emitted"]:
        i, state = line.split("\t", 1)[0].split(" ", 1)
        if i == "crashed":
            print(f"crashed after {state}: {f.name}")
            continue
        reached.setdefault(i, set()).add(state)
for i in sorted(set(reached) - set(reg)):
    print(f"unregistered {i} {' '.join(sorted(reached[i]))}")
for i, e in sorted(reg.items()):
    for s in e["states"]:
        why = e.get("unreached", {}).get(s)
        if s in reached.get(i, set()):
            if why:
                print(f"stale {i} {s}")
        elif why:
            print(f"unreached {i} {s}: {why}")
        else:
            print(f"missing {i} {s}")
    # `kept`: a FAIL or WARN .plinth-adoption.yml keeps (#1112), which only a keepable entry may be.
    for s in sorted(reached.get(i, set()) - set(e["states"]) - ({"kept"} if e["keepable"] else set())):
        print(f"undeclared {i} {s}")
print(f"registered {len(reg)}")
PY
if [ "$?" != 0 ] || ! grep -q '^registered ' "$work/ids.txt"; then bad "the ids were not read against REGISTRY" "$(cat "$work/ids.txt")"
else
c="$(grep '^crashed ' "$work/ids.txt")"
if [ -z "$c" ]; then ok "no recorded run raised"; else bad "a recorded run raised (named by the last id it emitted)" "$c"; fi
u="$(grep '^unregistered ' "$work/ids.txt")"
if [ -z "$u" ]; then ok "every id the checker emitted is registered"; else bad "ids emitted but not in REGISTRY" "$u"; fi
m="$(grep -E '^(missing|undeclared|stale) ' "$work/ids.txt")"
if [ -z "$m" ]; then ok "every registered id reaches each state it declares in some fixture, or its entry says why not"
else bad "registered states no fixture reaches and no entry explains, states emitted but not declared, or an unreached reason a fixture now contradicts" "$m"; fi
echo "  $(sed -n 's/^registered //p' "$work/ids.txt") ids registered; what no fixture reaches:"
grep '^unreached ' "$work/ids.txt" | sed 's/^unreached /        /'
grep -q '^unreached ' "$work/ids.txt" || echo "        (nothing listed)"
# Every check has its id (#1103): no FC-UNASSIGNED is left, and no call
# prints a verdict but emit() and verdict(). A result() or ok() that came
# back would print a line no registry entry stands for.
stray="$(grep -nE 'FC-UNASSIGNED|(^|[^_a-zA-Z.])(result|ok)\(' "$checker")"
if [ -z "$stray" ]; then ok "no FC-UNASSIGNED left, and nothing prints a verdict but emit() and verdict() (grep)"
else bad "a verdict printed without an id, or FC-UNASSIGNED, in scripts/floor-check.py" "$stray"; fi
fi

# --format json (#1105): each recorded run, made again with it, prints one
# document that scripts/floor-check.schema.json validates, holding the same
# ids and states in the same order as the text run emitted, its counts and
# exit code those of the text run.
mkdir -p "$work/json"
"$py" - "$work/records" "$work/json" > "$work/json.txt" <<'PY'
import json, sys
from pathlib import Path
records, out = Path(sys.argv[1]), Path(sys.argv[2])
n = usage = 0
seen = {"unknown": 0, "review": 0, "not_evaluated": 0}
for f in sorted(records.glob("*.json")):
    r = json.loads(f.read_text(encoding="utf-8"))
    if r.get("json") is None:
        continue
    args = " ".join(r["args"])
    # A usage error (exit 2, nothing printed) is one with --format json too: no document.
    if r["exit"] == 2 and not r["stdout"]:
        if r["json"]["exit"] != 2 or r["json"]["stdout"]:
            print(f"differs: {args}: a usage error as text, exit {r['json']['exit']} with --format json")
        usage += 1
        continue
    n += 1
    (out / f.name).write_text(r["json"]["stdout"], encoding="utf-8")
    try:
        doc = json.loads(r["json"]["stdout"])
    except ValueError:
        continue   # the validator names it
    emitted = [tuple(line.split("\t", 1)[0].split(" ", 1)) for line in r["emitted"]
               if not line.startswith("crashed ")]
    # A finding .plinth-adoption.yml keeps (#1112) is an info carrying `kept`
    # in the document, and `kept` in the trace.
    got = [(x.get("id"), "kept" if x.get("kept") else x.get("state")) for x in doc.get("results", [])]
    for s in ("unknown", "review"):
        seen[s] += any(x.get("state") == s for x in doc.get("results", []))
    seen["not_evaluated"] += bool(doc.get("not_evaluated"))
    if got != emitted:
        print(f"differs: {args}: the text run emitted {len(emitted)} results, the JSON holds {len(got)}"
              + next((f"; first difference at {i}: {a} against {b}" for i, (a, b) in enumerate(zip(emitted, got)) if a != b), ""))
    if r["json"]["exit"] != r["exit"] or doc.get("exit") != r["exit"]:
        print(f"differs: {args}: exit {r['exit']} as text, {r['json']['exit']} with --format json, {doc.get('exit')} in the document")
    counts = {s: sum(x == s or (s == "info" and x == "kept") for _, x in emitted) for s in {x for _, x in emitted} - {"kept"}}
    if any(doc.get("summary", {}).get(s) != c for s, c in counts.items()):
        print(f"differs: {args}: the summary's counts are not the results'")
print(f"documents {n}")
print(f"usage {usage}")
print("holding " + ", ".join(f"{k} {v}" for k, v in seen.items()))
PY
nj="$(sed -n 's/^documents //p' "$work/json.txt")"
if [ "${nj:-0}" -gt 100 ]; then
  if v="$("$py" "$root/tests/lib/json-schema-check.py" "$root/scripts/floor-check.schema.json" "$work/json"/*.json)"
  then ok "$nj runs again with --format json: every document is valid against scripts/floor-check.schema.json ($(sed -n 's/^usage //p' "$work/json.txt") usage errors print none, as without it)"
  else bad "a --format json document is not valid against scripts/floor-check.schema.json" "$(head -20 <<<"$v")"; fi
  d="$(grep '^differs: ' "$work/json.txt")"
  if [ -z "$d" ]; then ok "each document holds the text run's ids and states in order, its counts and its exit code"
  else bad "a --format json document says another run than the text" "$(head -20 <<<"$d")"; fi
  # The schema's rules for an unknown's reason and a review's reader hold
  # nothing unless some document has one.
  h="$(sed -n 's/^holding //p' "$work/json.txt")"
  if ! grep -qE '(^|, )[a-z_]+ 0(,|$)' <<<"$h"; then ok "documents with an unknown, with a review, and with checks not evaluated are among them ($h)"
  else bad "no document has one of an unknown, a review, or a not-evaluated list: the schema's rules for it were not exercised ($h)"; fi
else bad "only ${nj:-0} runs made again with --format json: the recorder did not run as it should"; fi
# A --verdicts file that cannot be written ends the run: stdout is still one
# document, the crashed one, not a whole run followed by it.
mkdir -p "$work/bare"
"$py" "$checker" --root "$work/bare" --no-network --format json --verdicts "$work/no-such-dir/verdicts" \
  > "$work/crash.json" 2>/dev/null
c="$("$py" -c 'import json, sys; d = json.load(open(sys.argv[1])); print((d.get("crashed") or {}).get("error"), d.get("exit"))' "$work/crash.json" 2>&1)"
if [ "$c" = "FileNotFoundError 1" ] && "$py" "$root/tests/lib/json-schema-check.py" "$root/scripts/floor-check.schema.json" "$work/crash.json" >/dev/null
then ok "a --verdicts file that cannot be written: one valid document, crashed, exit 1"
else bad "a --verdicts file that cannot be written does not print one crashed document" "$c"; fi

# The two pipelines that run the checker in consumers' CI do not move with
# this work: their floor-check jobs are held to the copy beside the golden.
"$py" - "$root" "$work" <<'PY'
import re, sys
from pathlib import Path
root, work = Path(sys.argv[1]), Path(sys.argv[2])
def job(path: Path, head: str) -> str:
    lines = path.read_text(encoding="utf-8").split("\n")
    start = lines.index(head)
    indent = len(head) - len(head.lstrip())
    end = next((i for i in range(start + 1, len(lines))
                if lines[i].strip() and not lines[i].lstrip().startswith("#")
                and len(lines[i]) - len(lines[i].lstrip()) <= indent), len(lines))
    return "\n".join(lines[start:end]).rstrip() + "\n"
(work / "jobs.txt").write_text(
    "# .github/workflows/python-ci.yml\n" + job(root / ".github/workflows/python-ci.yml", "  floor-check:")
    + "# gitlab/python-ci.yml\n" + job(root / "gitlab/python-ci.yml", "floor-check:"), encoding="utf-8")
PY
jobs="$root/tests/fixtures/floor-check-golden/ci-jobs.txt"
if [ "$write" = 1 ]; then cp "$work/jobs.txt" "$jobs"; echo "  wrote $jobs"
elif d="$(diff "$jobs" "$work/jobs.txt")"; then ok "python-ci.yml's and gitlab/python-ci.yml's floor-check jobs are the ones the golden output was recorded for"
else bad "a floor-check job in python-ci.yml or gitlab/python-ci.yml changed: the golden output no longer stands for what consumers' CI runs" "$(head -40 <<<"$d")"; fi

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
