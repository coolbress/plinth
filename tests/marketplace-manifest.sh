#!/usr/bin/env bash
# Manifest invariants that `claude plugin validate` does not check: the pins,
# the dependency set, the catalog, and the skill frontmatter that makes
# "user only" and "read only" real instead of prose.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$root" <<'PY'
import json, pathlib, re, sys

root = pathlib.Path(sys.argv[1])
market = json.loads((root / ".claude-plugin/marketplace.json").read_text())
plugin = json.loads((root / ".claude-plugin/plugin.json").read_text())
fails = 0

def check(cond, msg):
    global fails
    print(("  PASS  " if cond else "  FAIL  ") + msg)
    fails += 0 if cond else 1

entries = {p["name"]: p for p in market["plugins"]}
check("claude-plugins-official" in market.get("allowCrossMarketplaceDependenciesOn", []),
      "allowCrossMarketplaceDependenciesOn lists claude-plugins-official (without it install fails: cross-marketplace)")
check("userConfig" not in plugin, "plugin.json has no userConfig")
check(entries["plinth"]["source"] == "./", "plinth entry mounts the repository root")
check("version" not in entries["plinth"], "plinth entry carries no version; plugin.json is the single source")

deps = plugin["dependencies"]
names = [d["name"] if isinstance(d, dict) else d for d in deps]
check(names == ["mattpocock-skills", "frontend-design", "last30days", "ponytail-skills"],
      f"dependencies are exactly the default four: {names}")
matt = deps[0]
# No "version" range here: Claude Code resolves a range against {name}--v* tags on the
# dependency's own repository, mattpocock/skills has none, and install then fails with
# no-matching-tag (measured 2026-09-04). tests/install-smoke.sh checks the tested range instead.
check(isinstance(matt, dict) and matt.get("marketplace") == "claude-plugins-official" and "version" not in matt,
      "mattpocock-skills is resolved cross-marketplace, without a version range (see comment)")
check("ponytail" in entries and "ponytail" not in names, "ponytail is in the catalog and not a dependency")
for n in ("impeccable", "taste-skill", "i-have-adhd", "playbook", "review"):
    check(n not in entries, f"no marketplace entry named {n}")

pinned = {n: p["source"].get("sha") for n, p in entries.items() if isinstance(p["source"], dict)}
for n, sha in pinned.items():
    check(bool(re.fullmatch(r"[0-9a-f]{40}", sha or "")), f"{n} is pinned to a full commit SHA")
notice = (root / "NOTICE").read_text()
check(all(sha in notice for sha in pinned.values()), "NOTICE records every pinned SHA")

ponytail_skills = entries["ponytail-skills"]
check(ponytail_skills.get("strict") is False and len(ponytail_skills.get("skills", [])) == 6, "ponytail-skills: strict false, six skills listed")
check(ponytail_skills["source"]["path"] == "skills", "ponytail-skills mounts skills/ only; hooks stay outside")
check(entries["ponytail"]["source"]["sha"] == ponytail_skills["source"]["sha"], "ponytail and ponytail-skills pin the same commit")

skills = sorted(d.name for d in (root / "skills").iterdir() if d.is_dir())
check(skills == ["arsenal", "floor-check", "new-project"], f"plinth skills are arsenal, floor-check, new-project: {skills}")

def frontmatter(name):
    text = (root / "skills" / name / "SKILL.md").read_text()
    return text.split("---", 2)[1]

fm = frontmatter("new-project")
check("disable-model-invocation: true" in fm, "new-project: user-invoked only (it creates and deletes repositories)")
fm = frontmatter("floor-check")
line = re.search(r"^disallowed-tools:(.*)$", fm, re.M)
check(line is not None and all(t in line.group(1) for t in ("Edit", "Write", "NotebookEdit")),
      "floor-check: Edit, Write and NotebookEdit are actually removed (Bash stays; the skill needs gh)")
check(re.search(r"^allowed-tools:", fm, re.M) is None, "floor-check: allowed-tools is not mistaken for a lock (it unlocks)")
fm = frontmatter("arsenal")
check("disable-model-invocation" not in fm, "arsenal: the model may open the catalog on its own")
body = (root / "skills/arsenal/SKILL.md").read_text()
check(all(f"`{n}`" in body for n in names + ["ponytail"]),
      "arsenal lists the default four and the catalog entry")

print(f"-- {fails} failed")
sys.exit(1 if fails else 0)
PY
