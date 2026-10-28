"""The #665 probe's verdicts: eval-suite-probe.py <records dir>.

<records dir> holds what scripts/eval-suite-probe.sh kept from one
`claude plugin eval` run of eval-suite/probe/: result.json, the two arms'
traces as with-trace.jsonl and without-trace.jsonl, and probe.json (the
marker planted in the workspace's AGENTS.md and the output style its
.claude/settings.json names). Prints the Claude Code version, then one line
per blocker #647 found: held, gone, or unclear, with why.

The rules, fixed before the first run:

- (a) plinth with its dependencies loads. gone: the with-arm's init lists a
  plugin named plinth and at least one `plinth:` skill, and the without-arm's
  lists neither. held: the with-arm's init lists no `plinth:` skill.
- (b) the workspace's guidance loads, in both arms. AGENTS.md (CLAUDE.md links
  to it) counts as loaded when the marker is in the agent's text and the
  session called no tool but the one probe command, so it cannot have read the
  file; .claude/ counts as loaded when the init's output style is the one the
  workspace's settings name. gone: both loaded in both arms. held: either one
  shown not loaded in either arm (the marker absent, another output style).
- (c) the sandbox runs git and uv. gone: probe-checks.sh's four lines (two git,
  two `uv run`) all exit 0 in both arms, read from the command's own output in
  the trace, not the agent's retelling. held: any of them exits non-zero.

Anything else is unclear: a missing trace or init, a session that read files,
a check line that never printed. Exit 0 when all three are gone, 1 when one
holds, 2 when one is unclear and none holds.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any

PROBE_COMMAND = "bash probe-checks.sh"
CHECKS = ("git-status", "git-log", "uv-pytest", "uv-ruff")
ARMS = ("with", "without")


def events(path: Path) -> list[dict[str, Any]] | None:
    if not path.is_file():
        return None
    out = []
    for line in path.read_text(errors="replace").splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        if isinstance(e, dict):
            out.append(e)
    return out


def blocks(evs: list[dict[str, Any]], role: str) -> list[dict[str, Any]]:
    """Content blocks of every message of this role."""
    out = []
    for e in evs:
        if e.get("type") != role:
            continue
        content = (e.get("message") or {}).get("content")
        if isinstance(content, str):
            out.append({"type": "text", "text": content})
        elif isinstance(content, list):
            out.extend(b for b in content if isinstance(b, dict))
    return out


def text_of(b: dict[str, Any]) -> str:
    c = b.get("content", b.get("text", ""))
    if isinstance(c, list):
        return "\n".join(str(x.get("text", "")) for x in c if isinstance(x, dict))
    return str(c)


def init_of(evs: list[dict[str, Any]]) -> dict[str, Any] | None:
    for e in evs:
        if e.get("type") == "system" and e.get("subtype") == "init":
            return e
    return None


def plinth_loaded(init: dict[str, Any]) -> bool:
    plugins = {p.get("name") for p in init.get("plugins") or [] if isinstance(p, dict)}
    skills = [s for s in init.get("skills") or [] if isinstance(s, str)]
    return "plinth" in plugins and any(s.startswith("plinth:") for s in skills)


def judge_a(arm: dict[str, list[dict[str, Any]] | None]) -> tuple[str, str]:
    w, wo = arm["with"], arm["without"]
    wi = init_of(w) if w is not None else None
    woi = init_of(wo) if wo is not None else None
    if wi is None:
        return "unclear", "no init event in the with-arm's trace"
    skills = [s for s in wi.get("skills") or [] if isinstance(s, str) and s.startswith("plinth:")]
    if not plinth_loaded(wi):
        names = sorted(p.get("name", "?") for p in wi.get("plugins") or [] if isinstance(p, dict))
        return "held", f"the with-arm's init lists no plinth skill (plugins: {', '.join(names) or 'none'})"
    if woi is None:
        return "unclear", "no init event in the without-arm's trace"
    if plinth_loaded(woi) or any(isinstance(s, str) and s.startswith("plinth:") for s in woi.get("skills") or []):
        return "unclear", "the without-arm lists plinth too, so the arms do not differ"
    return "gone", f"the with-arm's init lists plinth and {len(skills)} plinth skills: {', '.join(skills)}"


def only_probe_command(evs: list[dict[str, Any]]) -> bool:
    for b in blocks(evs, "assistant"):
        if b.get("type") != "tool_use":
            continue
        cmd = (b.get("input") or {}).get("command", "")
        if b.get("name") != "Bash" or cmd.strip() != PROBE_COMMAND:
            return False
    return True


def judge_b(arm: dict[str, list[dict[str, Any]] | None], probe: dict[str, Any]) -> tuple[str, str]:
    marker, style = probe["marker"], probe["output_style"]
    shown_not, unclear = [], []
    for name in ARMS:
        evs = arm[name]
        init = init_of(evs) if evs is not None else None
        if evs is None or init is None:
            unclear.append(f"{name}-arm: no trace or init")
            continue
        said = "\n".join(text_of(b) for b in blocks(evs, "assistant") if b.get("type") == "text")
        if marker not in said:
            shown_not.append(f"{name}-arm: AGENTS.md's marker is not in the reply")
        elif not only_probe_command(evs):
            unclear.append(f"{name}-arm: the marker is in the reply, but the session ran other tools, so it may have read AGENTS.md")
        got = init.get("output_style")
        if got != style:
            shown_not.append(f"{name}-arm: output style is {got!r}, not .claude/'s {style!r}")
    if shown_not:
        return "held", "; ".join(shown_not)
    if unclear:
        return "unclear", "; ".join(unclear)
    return "gone", "both arms quoted AGENTS.md's marker without reading a file and use .claude/'s output style"


def check_lines(evs: list[dict[str, Any]]) -> dict[str, tuple[int, str]]:
    found: dict[str, tuple[int, str]] = {}
    for b in blocks(evs, "user"):
        if b.get("type") != "tool_result":
            continue
        for m in re.finditer(r"^PROBE (\S+) exit=(\d+) last=(.*)$", text_of(b), re.MULTILINE):
            found.setdefault(m.group(1), (int(m.group(2)), m.group(3).strip()))
    return found


def judge_c(arm: dict[str, list[dict[str, Any]] | None]) -> tuple[str, str]:
    failed, missing = [], []
    for name in ARMS:
        evs = arm[name]
        if evs is None:
            missing.append(f"{name}-arm: no trace")
            continue
        got = check_lines(evs)
        for c in CHECKS:
            if c not in got:
                missing.append(f"{name}-arm: {c} never printed")
            elif got[c][0] != 0:
                failed.append(f"{name}-arm: {c} exit {got[c][0]} ({got[c][1][:120]})")
    if failed:
        return "held", "; ".join(failed)
    if missing:
        return "unclear", "; ".join(missing)
    return "gone", "git status, git log, uv run pytest and uv run ruff exited 0 in both arms"


def main() -> int:
    d = Path(sys.argv[1])
    probe = json.loads((d / "probe.json").read_text())
    try:
        version = json.loads((d / "result.json").read_text()).get("claudeVersion", "unknown")
    except (OSError, ValueError):
        version = "unknown (no result.json)"
    arm = {name: events(d / f"{name}-trace.jsonl") for name in ARMS}
    verdicts = {
        "a": judge_a(arm),
        "b": judge_b(arm, probe),
        "c": judge_c(arm),
    }
    print(f"Claude Code {version}")
    labels = {
        "a": "plinth with its dependencies loads in the with-arm",
        "b": "the workspace's AGENTS.md and .claude/ load in both arms",
        "c": "git and uv run work in the sandbox",
    }
    for k, (v, why) in verdicts.items():
        print(f"({k}) {v}: {labels[k]}. {why}")
    states = {v for v, _ in verdicts.values()}
    return 1 if "held" in states else 2 if "unclear" in states else 0


if __name__ == "__main__":
    sys.exit(main())
