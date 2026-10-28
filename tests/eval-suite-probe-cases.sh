#!/usr/bin/env bash
# The #665 probe with made-up output, so no model is called: the verdicts of
# scripts/eval-suite-probe.py on traces where each blocker is gone, holds, or
# cannot be told, and scripts/eval-suite-probe.sh with a stubbed `claude` and
# `uvx`: it refuses the person's own configuration, stops when logged out,
# passes --no-publish and --max-cost-usd, and deletes the sandbox directories
# plugin eval keeps (only those) and its own copy of plinth.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/eval-suite-probe-cases.XXXXXX")"
tmp="$(cd "$tmp" && pwd -P)"
trap '[ -n "${KEEP:-}" ] || { chmod -R u+rwx "$tmp" 2>/dev/null; rm -rf "$tmp"; }' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | tail -15 | sed 's/^/        | /'; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "${3:-}"; fi; }

# One arm's trace, in the shape plugin eval writes (stream-json). Options as
# key=value: plinth=1 (init lists plinth), style=, marker=1 (the reply quotes
# it), extra= (a second Bash command), checks= (name:exit,...; a name left out
# never prints), said= (text the agent adds; x: the session stopped before
# any answer); _ in a value is a space.
cat > "$tmp/trace.py" <<'PY'
import json, sys
out, *opts = sys.argv[1:]
o = {k: v.replace("_", " ") for k, v in (a.split("=", 1) for a in opts)}
marker = "Probe marker: plinth-probe-0123456789abcdef"
plugins = [{"name": "cc-plugin-agents-md", "path": "builtin"}]
skills = ["verify", "debug"]
if o.get("plinth") == "1":
    plugins.append({"name": "plinth", "path": "/x/plinth"})
    skills += ["plinth:arsenal", "plinth:floor-check"]
ev = [{"type": "system", "subtype": "init", "plugins": plugins, "skills": skills,
       "output_style": o.get("style", "Beginner or non-engineer"), "claude_code_version": "9.9.9"}]
if o.get("said") != "x":
    ev.append({"type": "assistant", "message": {"content": [{"type": "text", "text": marker if o.get("marker") == "1" else "MARKER: NONE"}]}})
cmds = ["bash probe-checks.sh"] + ([o["extra"]] if o.get("extra") else [])
for c in cmds:
    ev.append({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Bash", "input": {"command": c}}]}})
checks = o.get("checks", "git-status:0,git-log:0,uv-pytest:0,uv-ruff:0")
lines = [f"PROBE {n} exit={x} last=ok" for n, x in (c.split(":") for c in checks.split(",") if c)]
ev.append({"type": "user", "message": {"content": [{"type": "tool_result", "content": [{"type": "text", "text": "\n".join(lines)}]}]}})
ev.append({"type": "assistant", "message": {"content": [{"type": "text", "text": o.get("said", "done")}]}})
ev.append({"type": "result", "total_cost_usd": 0.04})
with open(out, "w") as f:
    f.write("\n".join(json.dumps(e) for e in ev) + "\n")
PY
records() { # <dir> <with options> <without options>; "none" leaves that arm's trace out
  mkdir -p "$1"
  printf '{"marker": "Probe marker: plinth-probe-0123456789abcdef", "output_style": "Beginner or non-engineer"}\n' > "$1/probe.json"
  printf '{"claudeVersion": "9.9.9", "costUsd": 0.08}\n' > "$1/result.json"
  # shellcheck disable=SC2086  # the options are words on purpose
  [ "$2" = none ] || python3 -I "$tmp/trace.py" "$1/with-trace.jsonl" $2
  # shellcheck disable=SC2086
  [ "$3" = none ] || python3 -I "$tmp/trace.py" "$1/without-trace.jsonl" $3
}
judge() { python3 -I "$root/scripts/eval-suite-probe.py" "$1" > "$1/v.txt" 2>&1; echo $? > "$1/rc"; }
v() { cat "$1/v.txt"; }

n=0
case_() { # <name> <with options> <without options> <expected rc> <grep -E for the output>...
  local name="$1" w="$2" wo="$3" want="$4" d
  shift 4
  n=$((n+1)); d="$tmp/j$n"
  records "$d" "$w" "$wo"; judge "$d"
  local okk=1 p
  [ "$(cat "$d/rc")" = "$want" ] || okk=""
  for p in "$@"; do grep -qE "$p" "$d/v.txt" || okk=""; done
  if [ -n "$okk" ]; then ok "$name"; else bad "$name" "rc=$(cat "$d/rc") want=$want"$'\n'"$(v "$d")"; fi
}

all="plinth=1 marker=1"
base="marker=1"
case_ "all three gone: exit 0, with the version" "$all" "$base" 0 \
  '^Claude Code 9\.9\.9$' '^\(a\) gone: .*plinth:arsenal' '^\(b\) gone' '^\(c\) gone'
case_ "(a) holds when the with-arm's init lists no plinth skill" "marker=1" "$base" 1 '^\(a\) held: .*no plinth skill' '^\(b\) gone' '^\(c\) gone'
case_ "(a) is unclear when the without-arm lists plinth too" "$all" "plinth=1 marker=1" 2 '^\(a\) unclear: .*without-arm lists plinth'
case_ "(a) and (b) are unclear when the with-arm left no trace" none "$base" 2 '^\(a\) unclear: .*no init' '^\(b\) unclear' '^\(c\) unclear: .*with-arm: no trace'
case_ "(b) holds when the marker is not in one arm's reply" "$all" "" 1 '^\(b\) held: .*without-arm: AGENTS\.md' '^\(a\) gone'
case_ "(b) is unclear when an arm stopped before answering, and the init shows the right style" "$all" "said=x checks=" 2 '^\(b\) unclear: .*without-arm: the reply has neither'
case_ "(b) holds when an arm has the default output style, marker or not" "$all" "marker=1 style=default" 1 "^\(b\) held: .*without-arm: output style is 'default'"
case_ "(b) is unclear when the marker is quoted but the session also ran cat AGENTS.md" "$all plinth=1" "$base extra=cat_AGENTS.md" 2 '^\(b\) unclear: .*without-arm: .*may have read'
case_ "(c) holds when uv run pytest exits 2, whatever the reply says" "$all" "$base checks=git-status:0,git-log:0,uv-pytest:2,uv-ruff:0 said=PROBE_uv-pytest_exit=0_last=ok" 1 '^\(c\) held: .*without-arm: uv-pytest exit 2'
case_ "(c) holds when git exits 72 in both arms" "$all checks=git-status:72,git-log:72,uv-pytest:0,uv-ruff:0" "$base checks=git-status:72,git-log:0,uv-pytest:0,uv-ruff:0" 1 '^\(c\) held: .*with-arm: git-status exit 72 \(ok\); with-arm: git-log exit 72 \(ok\); without-arm: git-status exit 72'
case_ "(c) is unclear when a check line never printed, and the agent's own PROBE text does not count" "$all" "$base checks=git-status:0,git-log:0,uv-pytest:0 said=PROBE_uv-ruff_exit=0_last=ok" 2 '^\(c\) unclear: .*without-arm: uv-ruff never printed'
case_ "a held blocker outranks an unclear one: exit 1" "marker=1" none 1 '^\(a\) held' '^\(c\) unclear'
d="$tmp/jspace"; records "$d" "$all" "$base"
python3 -I - "$d/without-trace.jsonl" <<'PY'
import json, sys
ev = [json.loads(l) for l in open(sys.argv[1])]
ev.insert(2, {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Read", "input": {"file_path": "AGENTS.md"}}]}})
open(sys.argv[1], "w").write("\n".join(json.dumps(e) for e in ev) + "\n")
PY
judge "$d"
check "(b) is unclear when a Read of AGENTS.md comes before the quoted marker" '[ "$(cat "$d/rc")" = 2 ] && grep -q "^(b) unclear" "$d/v.txt"' "$(v "$d")"

# --- the runner, with stubs ----------------------------------------------
mkdir -p "$tmp/bin" "$tmp/home/.claude" "$tmp/cfg" "$tmp/t"
log="$tmp/stub.log"; : > "$log"
cat > "$tmp/bin/uvx" <<'EOF'
#!/usr/bin/env bash
dest="${*: -1}"
echo "uvx args=$*" >> "$EVAL_STUB_LOG"
mkdir -p "$dest/.claude"
echo "# rules" > "$dest/AGENTS.md"; ln -s AGENTS.md "$dest/CLAUDE.md"
echo '{"outputStyle": "Beginner or non-engineer"}' > "$dest/.claude/settings.json"
EOF
cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
case "${1:-}" in
  --version) echo "0.0.0 (stub claude)"; exit 0 ;;
  auth) [ "${2:-}" = status ] && [ -z "${EVAL_STUB_LOGGED_OUT:-}" ] && exit 0; exit 1 ;;
  plugin) [ "${2:-}" = eval ] || exit 1 ;;
  *) exit 1 ;;
esac
echo "eval cfg=$CLAUDE_CONFIG_DIR args=$*" >> "$EVAL_STUB_LOG"
plugin="$3" json=""
while [ $# -gt 0 ]; do case "$1" in --json) json="$2"; shift ;; esac; shift; done
fixture="$(sed -nE 's|^cp -R "(.*)/\." \.$|\1|p' "$plugin/probe-evals/probe/scaffold.sh")"
marker="$(grep '^Probe marker:' "$fixture/AGENTS.md")"
cases=""
for arm in with without; do
  k="$(mktemp -d "$TMPDIR/e-XXXXXX")"
  mkdir -p "$k/out" "$k/sealed"
  p=""; [ "$arm" = with ] && [ -f "$plugin/.claude-plugin/plugin.json" ] && p=',{"name":"plinth"}'
  s=""; [ -n "$p" ] && s=',"plinth:arsenal"'
  {
    printf '{"type":"system","subtype":"init","plugins":[{"name":"builtin"}%s],"skills":["verify"%s],"output_style":"Beginner or non-engineer"}\n' "$p" "$s"
    printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"},{"type":"tool_use","name":"Bash","input":{"command":"bash probe-checks.sh"}}]}}\n' "$marker"
    printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"PROBE git-status exit=0 last=a\\nPROBE git-log exit=0 last=b\\nPROBE uv-pytest exit=0 last=c\\nPROBE uv-ruff exit=0 last=d"}]}}\n'
  } > "$k/out/trace.jsonl"
  chmod 000 "$k/sealed"; chmod 555 "$k"
  echo "⚠ kept $k: home/ and tmp/ in it were written by the plugin under test and are sealed" >&2
  cases="$cases${cases:+,}\"$arm\":[{\"tracePath\":\"$k/out/trace.jsonl\"}]"
done
echo "⚠ kept $EVAL_STUB_DECOY: a directory that is not plugin eval's" >&2
printf '{"claudeVersion":"0.0.0","costUsd":0.05,"cases":[{"arms":{%s}}]}\n' "$cases" > "$json"
EOF
chmod +x "$tmp/bin/"*
mkdir -p "$tmp/t/decoy"
probe() { # <args>...
  env -u CLAUDE_CONFIG_DIR HOME="$tmp/home" PATH="$tmp/bin:$PATH" TMPDIR="$tmp/t" \
    EVAL_STUB_LOG="$log" EVAL_STUB_DECOY="$tmp/t/decoy" \
    "$root/scripts/eval-suite-probe.sh" "$@" > "$tmp/out.txt" 2>&1
  echo $? > "$tmp/rc"
}
rc() { cat "$tmp/rc"; }
evals() { grep -c '^eval ' "$log"; }

probe --config-dir "$tmp/home/.claude" --out "$tmp/r1"
check "refuses ~/.claude as the configuration directory" '[ "$(rc)" = 2 ] && grep -q "your own configuration directory" "$tmp/out.txt" && [ "$(evals)" = 0 ]' "$(cat "$tmp/out.txt")"
probe --config-dir "$tmp" --out "$tmp/r2"
check "refuses a directory that holds the home directory" '[ "$(rc)" = 2 ] && grep -q "holds your home directory" "$tmp/out.txt" && [ "$(evals)" = 0 ]' "$(cat "$tmp/out.txt")"
probe --out "$tmp/r3"
check "needs --config-dir" '[ "$(rc)" = 2 ] && [ "$(evals)" = 0 ]' "$(cat "$tmp/out.txt")"
EVAL_STUB_LOGGED_OUT=1 probe --config-dir "$tmp/cfg" --out "$tmp/r4"
check "stops before any session when logged out, and says how to log in" \
  '[ "$(rc)" = 2 ] && grep -q "claude auth login" "$tmp/out.txt" && [ "$(evals)" = 0 ]' "$(cat "$tmp/out.txt")"
probe --config-dir "$tmp/cfg" --ceiling 0.5 --out "$tmp/r5"
check "a probe where all three are gone exits 0 and prints three gone lines" \
  '[ "$(rc)" = 0 ] && [ "$(grep -c "^([abc]) gone" "$tmp/out.txt")" = 3 ]' "$(cat "$tmp/out.txt")"
check "plugin eval runs once, on a copy of plinth, with --no-publish, --max-cost-usd 0.5 and the temporary configuration" \
  '[ "$(evals)" = 1 ] && grep -q "^eval cfg=$tmp/cfg args=plugin eval $tmp/t/plinth-probe-work\.[^ ]*/plugin .* --no-publish --max-cost-usd 0\.5 " "$log"' "$(cat "$log")"
check "the copy has plinth's real plugin.json, dependencies included" \
  'grep -q "^eval .*--case probe" "$log" && grep -q "\"dependencies\"" "$root/.claude-plugin/plugin.json"'
check "the two traces and the verdicts are kept in --out" \
  '[ -s "$tmp/r5/with-trace.jsonl" ] && [ -s "$tmp/r5/without-trace.jsonl" ] && [ -s "$tmp/r5/verdict.txt" ] && grep -qx "0.05" "$tmp/r5/cost.txt"'
check "the sandbox directories plugin eval kept are deleted, sealed parts included" \
  '[ -z "$(find "$tmp/t" -maxdepth 1 -name "e-*")" ]' "$(ls -la "$tmp/t")"
check "a kept directory not named e-* is left alone" '[ -d "$tmp/t/decoy" ] && grep -q "left $tmp/t/decoy" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"
check "the copy of plinth and the rendered workspace are deleted" \
  '[ -z "$(find "$tmp/t" -maxdepth 1 -name "plinth-probe-work.*")" ]' "$(ls -la "$tmp/t")"
check "the workspace's AGENTS.md got a marker the trace had to repeat" 'grep -qE "^Probe marker: plinth-probe-[0-9a-f]{16}$" <(python3 -I -c "import json,sys; print(json.load(open(sys.argv[1]))[\"marker\"])" "$tmp/r5/probe.json")'
probe --config-dir "$tmp/cfg" --out "$tmp/r5"
check "refuses an --out that already exists" '[ "$(rc)" = 2 ] && grep -q "already exists" "$tmp/out.txt"' "$(cat "$tmp/out.txt")"

echo "  $pass passed, $fail failed"
[ "$fail" = 0 ]
