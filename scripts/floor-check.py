#!/usr/bin/env python3
"""Floor check: does a repository still have what the door gave it, and does
its wall still stand? Read-only. Exit 1 on any FAIL.

Run by `ci / floor-check` in python-ci.yml, and by the floor-check skill once
that skill is implemented, from this same file so the two can never disagree.
Standard library only. Set FLOOR_CHECK_API_DIR to a directory of JSON files
laid out like api.github.com paths to run the network checks against fixtures.

    floor-check.py --root . --project . --repo owner/name --ruleset ruleset.json
                   [--expect-checks "ci / a, ci / b"] [--archetype backend] [--no-network]

Repository-level items are read from --root (the checkout), project-level
items from --project (the working directory of python-ci). Items a repository
may inherit from the owner's `.github` repository (issue forms, SECURITY.md)
are accepted from there. The wall is read from the live rules API and
compared with what the ruleset the door applies expects; a wall that got
weaker (a required check dropped, a bypass actor added, a merge method
widened) is a FAIL, not a warning.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

# Archetypes whose floor includes a container image and a `.env.example`.
# Must agree with the `_exclude` conditions in the template's copier.yml;
# tests/archetype-single-source.sh checks that.
CONDITIONAL_ARCHETYPES = ("backend", "data-ml")

SKIP_DIRS = {".git", ".venv", "node_modules", ".plinth-ci", ".smoke", "dist"}

fails = 0


def result(kind: str, msg: str) -> None:
    global fails
    print(f"  {kind:5} {msg}")
    if kind == "FAIL":
        fails += 1


def ok(cond: bool, good: str, bad: str) -> bool:
    result("PASS" if cond else "FAIL", good if cond else bad)
    return cond


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


# ── network ──────────────────────────────────────────────────────────────


ABSENT = object()   # 404: the resource does not exist
ERROR = object()    # anything else went wrong: do not conclude


def api(path: str, network: bool):
    """GET api.github.com/<path>. Returns the JSON, ABSENT on 404, ERROR when
    offline or on any other failure. FLOOR_CHECK_API_DIR serves fixtures."""
    fixture_dir = os.environ.get("FLOOR_CHECK_API_DIR")
    if fixture_dir:
        f = Path(fixture_dir) / (path + ".json")
        return json.loads(read(f)) if f.is_file() else ABSENT
    if not network:
        return ERROR
    req = urllib.request.Request(f"https://api.github.com/{path}")
    req.add_header("Accept", "application/vnd.github+json")
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:  # noqa: S310
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        return ABSENT if e.code == 404 else ERROR
    except (urllib.error.URLError, TimeoutError, ValueError):
        return ERROR


def inherited_file(owner: str | None, path: str, network: bool):
    """A file from the owner's .github repository: its text, ABSENT or ERROR."""
    if owner is None:
        return ERROR
    data = api(f"repos/{owner}/.github/contents/{path}", network)
    if data in (ABSENT, ERROR) or not isinstance(data, dict):
        return data if data in (ABSENT, ERROR) else ERROR
    import base64
    return base64.b64decode(data.get("content", "")).decode("utf-8", errors="replace")


# ── repository-level floor ────────────────────────────────────────────────


def check_files(root: Path, owner: str | None, network: bool) -> None:
    for name in ("LICENSE", "README.md", "CHANGELOG.md", "AGENTS.md"):
        p = root / name
        ok(p.is_file() and p.stat().st_size > 0, f"{name} present", f"{name} missing or empty")

    # CONTRIBUTING: present is not adequate. A third of the ones in the wild
    # are stubs with no build/test command and no way to land a change.
    c = root / "CONTRIBUTING.md"
    if ok(c.is_file(), "CONTRIBUTING.md present", "CONTRIBUTING.md missing"):
        text = read(c)
        ok(re.search(r"uv run pytest|uv sync|pytest|npm test|make test|tests?/\S+\.(sh|py)", text, re.I) is not None,
           "CONTRIBUTING.md says how to build and test",
           "CONTRIBUTING.md has no build or test command")
        ok(re.search(r"pull request|\bPR\b|fork|merge", text, re.I) is not None,
           "CONTRIBUTING.md says how to land a change",
           "CONTRIBUTING.md has no pull request flow")
        body = [ln for ln in text.splitlines() if ln.strip()]
        ok(len(body) >= 10, f"CONTRIBUTING.md is not a stub ({len(body)} lines)",
           f"CONTRIBUTING.md looks like a stub ({len(body)} lines)")

    if (root / "SECURITY.md").is_file():
        result("PASS", "SECURITY.md present")
    else:
        got = inherited_file(owner, "SECURITY.md", network)
        if got is ERROR:
            result("INFO", "SECURITY.md not local; inheritance not verified (offline or API error)")
        else:
            ok(got is not ABSENT, "SECURITY.md inherited from the owner's .github repository",
               "SECURITY.md neither local nor in the owner's .github repository")

    forms = root / ".github" / "ISSUE_TEMPLATE"
    if forms.is_dir():
        files = {p.name: read(p) for p in sorted(forms.glob("*.yml"))}
        check_issue_forms(files, ("bug.yml", "feature.yml", "task.yml"), "local")
    else:
        listing = api(f"repos/{owner}/.github/contents/.github/ISSUE_TEMPLATE", network) if owner else ERROR
        if listing is ERROR or (listing is not ABSENT and not isinstance(listing, list)):
            result("INFO", "issue forms not local; inheritance not verified (offline or API error)")
        elif listing is ABSENT:
            result("FAIL", "issue forms neither local nor in the owner's .github repository")
        else:
            files = {}
            for entry in listing:
                if entry.get("name", "").endswith(".yml"):
                    text = inherited_file(owner, f".github/ISSUE_TEMPLATE/{entry['name']}", network)
                    files[entry["name"]] = text if isinstance(text, str) else ""
            # The shared .github repository carries bug and feature; task is the
            # template's own add-on and lives in the instance.
            check_issue_forms(files, ("bug.yml", "feature.yml"), "inherited")

    ok((root / ".github" / "dependabot.yml").is_file(), ".github/dependabot.yml present",
       ".github/dependabot.yml missing: pins age silently")

    check_gitattributes(root)
    check_agent_settings(root)
    check_doc_links(root)


def check_issue_forms(files: dict[str, str], expected: tuple[str, ...], where: str) -> None:
    missing = [f for f in expected if f not in files]
    ok(not missing, f"issue forms {', '.join(e[:-4] for e in expected)} present ({where})",
       f"issue forms missing ({where}): {missing}")
    alias_trap = re.compile(r"^\s*[\w-]+:\s+[*&]")
    for name, text in sorted(files.items()):
        if name == "config.yml":
            continue
        keys = [k for k in ("name:", "description:", "body:") if not re.search(rf"^{k}", text, re.M)]
        ok(not keys, f"{name} has name, description, body", f"{name} lacks {keys}")
        # A value starting with `*` or `&` is read as a YAML alias and breaks the whole form.
        trap = [n for n, ln in enumerate(text.splitlines(), 1) if alias_trap.match(ln)]
        ok(not trap, f"{name} has no unquoted YAML alias", f"{name} line {trap}: value starts with * or &")
        labelled = re.search(r"^labels:\s*\[.+\]", text, re.M) or re.search(r"^labels:\s*\n\s+- ", text, re.M)
        ok(labelled is not None, f"{name} labels its issues", f"{name} has no labels: those issues never sort in a list")


def check_gitattributes(root: Path) -> None:
    p = root / ".gitattributes"
    if not ok(p.is_file(), ".gitattributes present", ".gitattributes missing"):
        return
    rules: list[tuple[str, list[str]]] = []
    for line in read(p).splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            pattern, *attrs = line.split()
            rules.append((pattern, attrs))
    ok(any(pat == "*" and "text=auto" in attrs for pat, attrs in rules),
       ".gitattributes normalises line endings (* text=auto)",
       ".gitattributes does not normalise line endings")
    if any(root.rglob("uv.lock")):
        ok(any(pat == "uv.lock" and "linguist-generated" in attrs for pat, attrs in rules),
           ".gitattributes folds uv.lock in diffs (linguist-generated)",
           "uv.lock is not marked linguist-generated: review reads machine-written lines")
    # diff=/merge=/filter= drivers need each user's local git config; a committed
    # rule that only works with local setup makes people think it is working.
    builtin = {
        "merge": {"", "true", "false", "binary", "text", "union"},
        "diff": {"", "true", "false", "ada", "bash", "bibtex", "cpp", "csharp", "css", "dts", "elixir",
                 "fortran", "fountain", "golang", "html", "java", "kotlin", "markdown", "matlab", "objc",
                 "pascal", "perl", "php", "python", "ruby", "rust", "scheme", "tex"},
        "filter": {"", "true", "false"},
    }
    local_only = [f"{pat}: {a}" for pat, attrs in rules for a in attrs
                  if a.partition("=")[0] in builtin and a.partition("=")[2] not in builtin[a.partition("=")[0]]]
    ok(not local_only, ".gitattributes has no rule that needs local git config",
       f".gitattributes rules need local git config: {local_only}")


def check_agent_settings(root: Path) -> None:
    p = root / ".claude" / "settings.json"
    if not ok(p.is_file(), ".claude/settings.json present", ".claude/settings.json missing"):
        return
    try:
        deny = json.loads(read(p)).get("permissions", {}).get("deny", [])
    except json.JSONDecodeError:
        result("FAIL", ".claude/settings.json is not valid JSON")
        return
    wants = {
        "force push": lambda d: d.startswith("Bash(git push --force") or d.startswith("Bash(git push -f"),
        "rm -rf": lambda d: d.startswith("Bash(rm -rf"),
        "gh auth token": lambda d: d.startswith("Bash(gh auth token"),
        ".env reads": lambda d: d.startswith("Read(./.env"),
        "gh config reads": lambda d: d.startswith("Read(~/.config/gh"),
    }
    for what, match in wants.items():
        ok(any(match(d) for d in deny), f".claude/settings.json denies {what}",
           f".claude/settings.json does not deny {what}")


def check_doc_links(root: Path) -> None:
    link = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
    fenced = re.compile(r"```.*?```", re.S)
    inline = re.compile(r"`[^`\n]*`")
    docs = [p for p in root.rglob("*.md") if not (set(p.relative_to(root).parts) & SKIP_DIRS)]
    if not docs:
        result("FAIL", "no markdown document found at all")
        return
    broken: dict[str, list[str]] = {}
    for doc in docs:
        text = inline.sub("", fenced.sub("", read(doc)))
        for target in link.findall(text):
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            path = (doc.parent / target.split("#", 1)[0]).resolve()
            if root.resolve() not in path.parents and path != root.resolve():
                continue  # outside the repository: a GitHub-interpreted URL, not a file
            if not path.exists():
                broken.setdefault(doc.relative_to(root).as_posix(), []).append(target)
    ok(not broken, f"relative links in {len(docs)} markdown files resolve",
       f"links to files that do not exist: {broken}")


# ── project-level floor ───────────────────────────────────────────────────


def archetype_of(project: Path, given: str | None) -> str | None:
    if given:
        return given
    answers = project / ".copier-answers.yml"
    if answers.is_file():
        m = re.search(r"^archetype:\s*(\S+)", read(answers), re.M)
        if m:
            return m.group(1).strip("'\"")
    return None


def package_name(project: Path) -> str | None:
    if not (project / "pyproject.toml").is_file():
        return None
    m = re.search(r'^name\s*=\s*"([^"]+)"', read(project / "pyproject.toml"), re.M)
    return m.group(1).replace("-", "_") if m else None


def check_project(project: Path, archetype: str | None) -> None:
    ok((project / "pyproject.toml").is_file(), "pyproject.toml present", "pyproject.toml missing")
    ok((project / "uv.lock").is_file(), "uv.lock committed", "uv.lock missing: CI runs `uv sync --locked`")

    if archetype is None:
        result("INFO", "no archetype (no .copier-answers.yml, no --archetype); conditional items skipped")
        return
    if archetype not in CONDITIONAL_ARCHETYPES:
        result("INFO", f"archetype {archetype}: no container image or .env.example required")
        return
    result("INFO", f"archetype {archetype}: container image and .env.example required")
    check_dockerfile(project)
    check_env_example(project)


def check_dockerfile(project: Path) -> None:
    d = project / "Dockerfile"
    if not ok(d.is_file(), "Dockerfile present", "Dockerfile missing"):
        return
    text = read(d)
    froms = [re.sub(r"^--\S+\s+", "", f).split() for f in re.findall(r"^FROM\s+(.+)$", text, re.M)]
    aliases = {parts[2] for parts in froms if len(parts) >= 3 and parts[1].upper() == "AS"}
    bases = [parts[0] for parts in froms if parts and parts[0] not in aliases and parts[0] != "scratch"]
    unpinned = [b for b in bases if "@sha256:" not in b]
    ok(bool(froms) and not unpinned, "every base image is pinned by digest",
       f"base images not pinned by digest: {unpinned or 'no FROM at all'}")
    users = re.findall(r"^USER\s+(\S+)", text, re.M)
    ok(bool(users) and users[-1].split(":")[0] not in {"root", "0"}, "the image does not run as root",
       "the image runs as root (no USER, or the last USER is root)")
    ok("uv sync --locked" in text, "the image installs from the lockfile (uv sync --locked)",
       "the image does not use `uv sync --locked`: it can drift from the repository")
    pkg = package_name(project)
    cmd = re.search(r"^CMD\s+\[(.+)\]", text, re.M)
    parts = [p.strip().strip('"') for p in cmd.group(1).split(",")] if cmd else []
    entry = project / "src" / (pkg or "") / "__main__.py"
    ok(parts[:2] == ["python", "-m"] and len(parts) > 2 and parts[2] == pkg and entry.is_file(),
       f"CMD runs python -m {pkg} and src/{pkg}/__main__.py exists",
       f"CMD {parts or 'missing'} does not run an existing module python -m {pkg}")
    di = project / ".dockerignore"
    if ok(di.is_file(), ".dockerignore present", ".dockerignore missing"):
        missing = [m for m in (".git", ".env", ".venv") if m not in read(di)]
        ok(not missing, ".dockerignore keeps .git, .env, .venv out of the image",
           f".dockerignore lacks {missing}: they ship inside the image")


def check_env_example(project: Path) -> None:
    e = project / ".env.example"
    if not ok(e.is_file(), ".env.example present", ".env.example missing"):
        return
    pattern = re.compile(r"""os\.(?:environ\s*\[\s*|environ\.get\s*\(\s*|getenv\s*\(\s*)['"]([A-Z_][A-Z0-9_]*)['"]""")
    used = {m for f in (project / "src").rglob("*.py") for m in pattern.findall(read(f))} if (project / "src").is_dir() else set()
    documented = set(re.findall(r"^\s*#?\s*([A-Z_][A-Z0-9_]*)\s*=", read(e), re.M))
    missing = sorted(used - documented)
    ok(not missing, ".env.example documents every variable the code reads",
       f".env.example is missing variables the code reads: {missing}")


# ── the wall ──────────────────────────────────────────────────────────────


def check_wall(repo: str, expected: list[str], merge_methods: set[str], network: bool) -> None:
    if not network and not os.environ.get("FLOOR_CHECK_API_DIR"):
        result("INFO", "wall not checked (offline)")
        return
    meta = api(f"repos/{repo}", network)
    if meta in (ABSENT, ERROR) or not isinstance(meta, dict):
        result("FAIL" if meta is ABSENT else "INFO", f"could not read repos/{repo}")
        return
    branch = meta.get("default_branch", "main")
    rules = api(f"repos/{repo}/rules/branches/{branch}", network)
    if rules is ERROR:
        result("INFO", f"could not read the rules of {branch} (API error)")
        return
    if rules is ABSENT or not rules:
        result("FAIL", f"no rules govern {branch}: the wall is down")
        return
    by_type = {r["type"]: r for r in rules}
    for t in ("deletion", "non_fast_forward", "pull_request", "required_status_checks"):
        ok(t in by_type, f"{branch}: {t} rule active", f"{branch}: {t} rule missing")

    pr = by_type.get("pull_request", {}).get("parameters", {})
    methods = set(pr.get("allowed_merge_methods", []))
    ok(bool(methods) and methods <= merge_methods,
       f"{branch}: merge methods within {sorted(merge_methods)}",
       f"{branch}: merge methods widened to {sorted(methods) or 'unknown'}")

    rsc = by_type.get("required_status_checks", {}).get("parameters", {})
    ok(rsc.get("strict_required_status_checks_policy") is True,
       f"{branch}: required checks are strict (branch must be current)",
       f"{branch}: required checks are not strict")
    have = {c["context"] for c in rsc.get("required_status_checks", [])}
    missing = [c for c in expected if c not in have]
    ok(not missing, f"{branch}: all {len(expected)} expected checks are required",
       f"{branch}: required checks dropped: {missing}")

    # CodeQL is part of the floor whatever the ruleset names: the door requires
    # it through a code_scanning rule (blocks with a reason, and on the alerts
    # themselves); repositories created before workflows#109 require the
    # `CodeQL` check name instead. Either holds the wall; neither does not.
    tools = by_type.get("code_scanning", {}).get("parameters", {}).get("code_scanning_tools", [])
    by_rule = any(t.get("tool") == "CodeQL" for t in tools)
    by_name = "CodeQL" in have
    ok(by_rule or by_name,
       f"{branch}: CodeQL enforced ({'rule' if by_rule else 'check name'})",
       f"{branch}: CodeQL not enforced: no code_scanning rule for CodeQL and no CodeQL check name")

    ids = {r.get("ruleset_id") for r in rules if r.get("ruleset_source_type") == "Repository"}
    for rid in sorted(i for i in ids if i):
        rs = api(f"repos/{repo}/rulesets/{rid}", network)
        actors = rs.get("bypass_actors") if isinstance(rs, dict) else None
        if actors is None:
            # Only visible with repository-administration read, which the
            # Actions token never has. The skill, run by the owner, sees it.
            result("INFO", f"ruleset {rid}: bypass actors not visible with this token (an admin-read token sees them)")
        else:
            ok(actors == [], f"ruleset {rid}: no bypass actors", f"ruleset {rid}: bypass actors present: {actors}")


# ── main ──────────────────────────────────────────────────────────────────


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=".", help="repository checkout")
    ap.add_argument("--project", default=".", help="project root, relative to --root")
    ap.add_argument("--repo", help="owner/name on GitHub; enables inheritance and wall checks")
    ap.add_argument("--ruleset", help="ruleset.json the door applies; its contexts are the expected checks")
    ap.add_argument("--expect-checks", help="required check names, comma separated; overrides --ruleset")
    ap.add_argument("--archetype", help="override the archetype in .copier-answers.yml")
    ap.add_argument("--no-network", action="store_true", help="skip everything that needs api.github.com")
    ap.add_argument("--print-conditional-archetypes", action="store_true", help=argparse.SUPPRESS)
    a = ap.parse_args()

    if a.print_conditional_archetypes:
        print(" ".join(CONDITIONAL_ARCHETYPES))
        return 0

    root = Path(a.root).resolve()
    project = (root / a.project).resolve()
    network = not a.no_network
    owner = a.repo.split("/")[0] if a.repo else None

    print(f"floor check: root={root} project={project.relative_to(root) if project != root else '.'}")
    check_files(root, owner, network)
    check_project(project, archetype_of(project, a.archetype))

    if a.repo:
        expected: list[str] = []
        merge_methods = {"squash"}
        if a.ruleset:
            data = json.loads(read(Path(a.ruleset)))
            expected = [c["context"] for r in data["rules"] if r["type"] == "required_status_checks"
                        for c in r["parameters"]["required_status_checks"]]
            merge_methods = {m for r in data["rules"] if r["type"] == "pull_request"
                             for m in r["parameters"].get("allowed_merge_methods", [])} or merge_methods
        if a.expect_checks:
            expected = [c.strip() for c in a.expect_checks.split(",") if c.strip()]
        result("INFO", f"wall expectation: checks {expected}, merge methods {sorted(merge_methods)}")
        check_wall(a.repo, expected, merge_methods, network)
    else:
        result("INFO", "no --repo: wall not checked")

    print(f"-- {fails} failed")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
