#!/usr/bin/env python3
"""Floor check: does a repository still have what the door gave it, and does
its wall still stand? Read-only. Exit 1 on any FAIL.

Run by `ci / floor-check` in python-ci.yml and by the floor-check skill, from
this same file; token, network and inputs can still make their results differ.
An item the run could not read (offline, no --repo, an API error, a token that
does not see it) is a SKIP, counted in the summary and never a PASS: exit 0
says no FAIL in what was checked, and `N not verified` says what was not (#119).
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
widened, a CodeQL alert threshold lowered) is a FAIL, not a warning.

Three checks are static and WARN-only (#95): tracked dotenv files (names in
the index, not contents or history), action pins (`uses:` lines of
.github/workflows, not composite actions), JSON logs (a known setup in a
service archetype's src/, never what the process prints). What each reads and
does not read is in its docstring and in skills/floor-check/SKILL.md.

The caller is a FAIL item (#325): the `ci` job in .github/workflows/ci.yml
calls plinth's python-ci.yml at a full commit SHA, read with --repo from the
default branch through the API. `ci / floor-check` passes
--caller-from-checkout and reads the pull request's own ci.yml instead: a
pull request that keeps the call but weakens it fails before the merge, and
one that repairs a broken default branch can merge. A pull request that
removes the call removes `ci / floor-check` with it, so only a run from
outside the pull request's own workflows sees that, after the merge.

Push protection is WARN-only too (#303): on, off with the call that turns it
on, or a SKIP when the token does not get the repository's security settings.
`ci / floor-check` passes --actions-token, which makes that one SKIP an INFO:
the Actions token never gets them, and the skill, run by a person, does.
The summary line counts such INFOs on their own, `K left to
/plinth:floor-check`, printed only when K is above 0 (#436).

Two more WARN-only items read settings the same way (#747): the Actions
allowlist against the `uses:` lines of the local workflows (an action it
refuses ends its run in startup_failure), and private vulnerability
reporting, which SECURITY.md names (an INFO on a private repository, which
GitHub does not offer it).

With --merge-ruleset, one line says whether the merge is guidance or a
boundary for the login the run reads with (#569): its admin role on the
repository decides, with the merge ruleset. Under --actions-token it is not
decided (an INFO left to the skill): the Actions token is not the agent's login.

A private repository's wall is read against its licences (#351): the
code_scanning rule is expected only where GitHub Code Security is enabled on
it, push protection only where GitHub Secret Protection is. Off is an INFO
naming the gap and what stands in its place; a licence state the API does not
answer is a SKIP, or with --actions-token an INFO naming the run that judges
it. Every other item is expected as on a public repository.

One more is WARN-only and reads no network beyond one GitHub compare call and the reads named below
(#219): whether the template tag this repository was rendered from
(.copier-answers.yml's _commit) is behind the tag plinth is tested with
today (scripts/new-project.sh's template_ref, read from that file alone).
Behind prints the template's own changed files and a `copier update` line;
it never runs one. --print-update-command prints that line alone, for the
template-update skill (#232), which runs it. The line carries the plinth pin
the workflows call today (#219); when the target tag was tested with a newer
plinth commit, a second line carries that one, for a person to choose
(--plinth-pin tested), after three more reads: the tag's copier.yml,
plinth's tags and a compare of the two plinth commits (#511). Each line is
printed only while the target tag still names new-project.sh's template_sha,
the commit plinth was tested with, read with one more call: a moved tag is a
WARN with no line, and an unread one prints the line here but not from
--print-update-command, the line that runs (#519). On GitHub the line also
carries the owner's two answers, read as /plinth:new-project reads them
(the owner's .github: its visibility, three pull-request template paths,
the shared issue-template folder and each form in it, #726), true only
while the repository has none of its own; without --repo, or with a read
that fails, there is no line, here or from --print-update-command.

A GitLab checkout (--host gitlab, or `host: gitlab` in .copier-answers.yml)
is read as one (#543): glab's token and config reads in the agent settings,
.gitlab/ issue and merge request templates, and in place of the ci caller the
top-level include of .gitlab-ci.yml, judged by the rule of the GitLab
pipeline's own floor-check job, run from gitlab/python-ci.yml beside this
script so the two cannot drift. That rule needs PyYAML: without it here, the
job's own pin is installed by hash into a temporary venv (pypi.org), and with
--no-network the item is a SKIP. GitHub-only items (Dependabot, the workflows) are not read there.

--credentials also names a production database URL within the agent's reach
(#648): a PostgreSQL URL to a host that is not local, in this environment,
the repository's .env* files or the env of .claude/settings*.json. A WARN
names the place, never the value; nothing found is an INFO with its limit.
`ci / floor-check` does not pass --credentials, so its own service URLs are
never read.

A repository with package.json and no pyproject.toml where the project is
read (#681), on GitHub, is read as a JavaScript or TypeScript one: an INFO
line under the header says so, and each item that depends on Python
(pyproject.toml, uv.lock, the archetype's items, the ci job's call to
python-ci.yml, the required checks only that workflow runs) is an N/A line
saying why, counted on the summary line as `K do not apply`. Every other item
keeps its verdict. With a Python project one level down, the --project hint
stands instead. Bun's lockfile alone is an INFO: GitHub's dependency review
does not read it.
"""

from __future__ import annotations

import argparse
import base64
import copy
import fnmatch
import ipaddress
import json
import math
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import textwrap
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import cast

# Archetypes whose floor includes a container image and a `.env.example`.
# Must agree with the `_exclude` conditions in the template's copier.yml;
# tests/archetype-single-source.sh checks that.
CONDITIONAL_ARCHETYPES = ("backend", "data-ml", "web")
# A service archetype's ci.yml carries one check python-ci.yml does not: `image`,
# a plain job that builds and runs the container (#127). Not a line in
# ruleset.json: applied by hand, that file is the wall every archetype reports
# to. The door asks this file for the archetype's ruleset (--print-ruleset) and
# the expectation below adds the same name, so the two cannot disagree. It comes
# from the same app as the nine (their integration_id), not a second literal.
IMAGE_CHECK = "image"
# The checks python-ci.yml runs for the web archetype alone, with its `web`
# input (#614); the door's ruleset adds them for that archetype.
WEB_CHECKS = ("ci / migrations", "ci / deploy-check")
# The archetypes whose floor includes publishing on a version tag through
# plinth-template's .github/workflows/release.yml, on GitHub: a package to
# PyPI (#703), a backend's image to GHCR (#706), a data-ml project's model,
# metrics and card to a GitHub Release (#716). What each publishes, where,
# the template release that adds the file, and what the run pushes with in
# place of a stored secret.
PACKAGE_ARCHETYPES = ("cli", "library")
RELEASE_WORKFLOW = ".github/workflows/release.yml"
RELEASES = {
    "cli": ("this package to PyPI", "1.29.0", "Trusted Publishing needs none"),
    "library": ("this package to PyPI", "1.29.0", "Trusted Publishing needs none"),
    "backend": ("this image to GHCR", "1.30.0", "the run's own token pushes the image"),
    "data-ml": ("this model to a GitHub Release", "1.31.0", "the run's own token makes the release"),
}
# What a data-ml release must never upload: formats that run code when loaded.
PICKLE_SUFFIXES = (".pkl", ".pickle", ".joblib", ".pt")
# GitLab's name for the same job: `image` is a GitLab CI keyword (plinth-template v1.13.0).
GITLAB_IMAGE_JOB = "docker-image"
# The GitLab pipeline beside this script; its floor-check job holds the include rule (#543).
GITLAB_PIPELINE = Path(__file__).resolve().parent.parent / "gitlab" / "python-ci.yml"

# This repository's own identity, as consumer workflows pin it (#219): the
# `uses:` lines that call plinth's reusable workflows.
PLINTH_REPO = "coolbress/plinth"
# Template files the door renders unchanged (no .jinja): the short list #219's
# drift item shows a diff for, alongside the bare list of what else changed.
TEMPLATE_DRIFT_DIFF_FILES = ("AGENTS.md", "CONTRIBUTING.md", ".gitignore")

SKIP_DIRS = {".git", ".venv", "node_modules", ".plinth-ci", ".smoke", ".scratch", "dist"}
# What GitHub accepts under .github/ISSUE_TEMPLATE: forms in either YAML
# spelling, and the legacy Markdown templates it still renders. `config.yml`
# is the folder's configuration, not a form.
FORM_SUFFIXES = {".yml", ".yaml", ".md"}
CONFIG_NAMES = {"config.yml", "config.yaml"}

fails = 0
skips = 0
left = 0
# Items that depend on Python, on a JavaScript or TypeScript repository (#681).
na = 0
# One line per FAIL, SKIP and deferred INFO, in the three forms of
# docs/reference/required-checks.md, for --verdicts (#437).
verdicts: list[str] = []
LEFT_TO_SKILL = "; left to /plinth:floor-check"


def result(kind: str, msg: str, *, deferred: bool = False) -> None:
    """`deferred` marks an INFO for a read this run cannot make and a run with
    a login that administers the repository does (#436): outside the
    not-verified count (#303), counted on the summary line on its own."""
    global fails, skips, left, na
    print(f"  {kind:5} {msg}")
    if kind == "N/A":
        na += 1
    elif kind == "FAIL":
        fails += 1
        verdicts.append(f"fail: {msg}")
    elif kind == "SKIP":
        skips += 1
        # The SKIP's own text says why; what reads it differs per item (an
        # admin login, the network, a file the door writes), so the line says
        # only what is true of all of them.
        verdicts.append(f"not yet confirmed: {msg}; a run that can read it confirms it")
    if deferred:
        left += 1
        # The fixed ending is how `ci / floor-check` tells these from the
        # per-commit lines it annotates (#441).
        verdicts.append(f"not yet confirmed: {msg}{LEFT_TO_SKILL}")


def ok(cond: bool, good: str, bad: str) -> bool:
    result("PASS" if cond else "FAIL", good if cond else bad)
    return cond


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


# ── network ──────────────────────────────────────────────────────────────


ABSENT = object()   # 404: the resource does not exist
ERROR = object()    # anything else went wrong: do not conclude


def api(path: str, network: bool, paginate: bool = False):
    """GET api.github.com/<path>. Returns the JSON, ABSENT on 404, ERROR when
    offline or on any other failure. FLOOR_CHECK_API_DIR serves fixtures.

    Through `gh api` when gh is installed: the skill runs on the owner's
    machine, where the token lives in gh's keychain and never in the
    environment, and bypass actors are visible only to that token. Anything
    but a 404 from gh (not logged in, offline) falls back to a plain request."""
    fixture_dir = os.environ.get("FLOOR_CHECK_API_DIR")
    if fixture_dir:
        f = Path(fixture_dir) / (path + ".json")
        if not f.is_file():
            return ABSENT
        # Unparseable is ERROR, as an answer gh cannot parse is below: how a
        # fixture says the API failed.
        try:
            return json.loads(read(f))
        except ValueError:
            return ERROR
    if not network:
        return ERROR
    if shutil.which("gh"):
        try:
            # --paginate: GitHub returns 30 per page by default, and a repository
            # with the door's labels plus GitHub's own defaults is over that
            # (33 measured on plinth-template). One page would report labels
            # missing that are there.
            cmd = ["gh", "api", path] + (["--paginate"] if paginate else [])
            r = subprocess.run(cmd, capture_output=True, text=True, timeout=30, check=False)
        except (OSError, subprocess.TimeoutExpired):
            r = None
        if r is not None and r.returncode == 0:
            try:
                return json.loads(r.stdout)
            except ValueError:
                return ERROR
        if r is not None and "HTTP 404" in r.stderr:
            return ABSENT
    req = urllib.request.Request(f"https://api.github.com/{path}")
    req.add_header("Accept", "application/vnd.github+json")
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
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


def check_files(root: Path, owner: str | None, network: bool, host: str = "github") -> None:
    for name in ("LICENSE", "README.md", "CHANGELOG.md", "AGENTS.md"):
        p = root / name
        ok(p.is_file() and p.stat().st_size > 0, f"{name} present", f"{name} missing or empty")

    # CONTRIBUTING: present is not adequate. A third of the ones in the wild
    # are stubs with no build/test command and no way to land a change.
    c = root / "CONTRIBUTING.md"
    if ok(c.is_file(), "CONTRIBUTING.md present", "CONTRIBUTING.md missing"):
        text = read(c)
        ok(re.search(r"uv run pytest|uv sync|pytest|npm test|make test|tests?/\S+\.(sh|py)", text, re.IGNORECASE) is not None,
           "CONTRIBUTING.md says how to build and test",
           "CONTRIBUTING.md has no build or test command")
        ok(re.search(r"pull request|\bPR\b|fork|merge", text, re.IGNORECASE) is not None,
           "CONTRIBUTING.md says how to land a change",
           "CONTRIBUTING.md has no pull request flow")
        body = [ln for ln in text.splitlines() if ln.strip()]
        ok(len(body) >= 10, f"CONTRIBUTING.md is not a stub ({len(body)} lines)",
           f"CONTRIBUTING.md looks like a stub ({len(body)} lines)")

    if (root / "SECURITY.md").is_file():
        result("PASS", "SECURITY.md present")
    elif host == "gitlab":
        # GitLab has no owner-level `.github` repository to inherit from (#547 review, round 3).
        result("FAIL", "SECURITY.md missing: on GitLab nothing is inherited from an owner's .github repository")
    else:
        got = inherited_file(owner, "SECURITY.md", network)
        if got is ERROR:
            result("SKIP", "SECURITY.md not local; inheritance not verified (offline or API error)")
        else:
            ok(got is not ABSENT, "SECURITY.md inherited from the owner's .github repository",
               "SECURITY.md neither local nor in the owner's .github repository")

    if host == "gitlab":
        check_gitlab_templates(root)
        result("INFO", "Dependabot does not run on GitLab: nothing raises the plinth include or uv.lock's pins "
                       "for you; `deps` scans uv.lock on each merge request")
        check_gitattributes(root)
        check_agent_settings(root, host)
        check_doc_links(root)
        check_tracked_dotenv(root)
        check_template_drift(root, network, host, owner)
        return

    forms = root / ".github" / "ISSUE_TEMPLATE"
    local = {p.name: read(p) for p in sorted(forms.iterdir())
             if p.is_file() and p.suffix in FORM_SUFFIXES} if forms.is_dir() else {}
    # A directory is not a template. `.gitkeep` alone leaves the owner's shared
    # set in force, so the question is whether a template or a config is there,
    # not whether the folder exists.
    if local:
        check_issue_forms(local, "local")
        # GitHub does not merge the two sets: any local template or config
        # replaces the owner's shared set entirely, per folder, not per file.
        result("INFO", "a local ISSUE_TEMPLATE replaces the owner's shared set; GitHub does not merge them")
    else:
        listing = api(f"repos/{owner}/.github/contents/.github/ISSUE_TEMPLATE", network) if owner else ERROR
        if listing is ERROR or (listing is not ABSENT and not isinstance(listing, list)):
            result("SKIP", "issue forms not local; inheritance not verified (offline or API error)")
        elif listing is ABSENT:
            result("FAIL", "issue forms neither local nor in the owner's .github repository")
        else:
            files, unread = {}, []
            for entry in cast("list[dict]", listing):  # a list: the two branches above took every other value
                name = entry.get("name", "")
                # Configuration is not a candidate template. Fetching it would
                # let a failed read of `config.yml` alone hide a listing that
                # already proves no form is there.
                if name in CONFIG_NAMES:
                    continue
                if Path(name).suffix in FORM_SUFFIXES:
                    text = inherited_file(owner, f".github/ISSUE_TEMPLATE/{name}", network)
                    # A listing entry is not a template. Counting a file whose
                    # content never arrived would turn an API failure into a pass.
                    if isinstance(text, str):
                        files[name] = text
                    else:
                        unread.append(name)
            if unread:
                result("SKIP", f"inherited forms not verified (content unreadable): {', '.join(sorted(unread))}")
            # Absence is concluded only when every candidate was actually read.
            if files or not unread:
                check_issue_forms(files, "inherited")

    ok((root / ".github" / "dependabot.yml").is_file(), ".github/dependabot.yml present",
       ".github/dependabot.yml missing: pins age silently")

    check_gitattributes(root)
    check_agent_settings(root)
    check_doc_links(root)
    check_tracked_dotenv(root)
    check_action_pins(root)
    check_template_drift(root, network, host, owner)


def md_front_matter_name(text: str) -> str:
    """The value of `name:` in a Markdown template's front matter, or ""."""
    fm = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, re.DOTALL)
    if not fm:
        return ""
    m = re.search(r"^name:[ \t]*(.*)$", fm.group(1), re.MULTILINE)
    # Quotes are syntax, not a name: `name: ""` has no title behind it.
    return m.group(1).strip().strip("'\"").strip() if m else ""


def yaml_body_is_list(text: str) -> bool:
    """Does `body:` hold a sequence? GitHub rejects a form whose body is not one.

    Regex, not a parser: this file is standard library only."""
    m = re.search(r"^body:[ \t]*(.*)$", text, re.MULTILINE)
    if not m:
        return False
    inline = m.group(1).strip()
    if inline:
        return inline.startswith("[")
    for line in text[m.end():].splitlines():
        if line.strip():
            return re.match(r"^\s*-\s", line) is not None
    return False


def check_issue_forms(files: dict[str, str], where: str) -> None:
    # Presence is judged by what is there, not by filename: GitHub reads every
    # form in the folder whatever it is called, so a name this checker did not
    # expect is not a missing form.
    forms = {n: t for n, t in files.items() if n not in CONFIG_NAMES}
    # Found, not valid: this line says which files are there. Whether each is a
    # template GitHub will actually offer is the per-file verdict below.
    ok(bool(forms), f"issue templates found ({where}): {', '.join(sorted(forms))}",
       f"no issue template ({where}): every issue arrives in whatever shape its writer chose")
    alias_trap = re.compile(r"^\s*[\w-]+:\s+[*&]")
    usable = 0
    for name, text in sorted(forms.items()):
        # `.yml` was already checked before this file started reading `.yaml`
        # and `.md`; those two are new ground. A defect found only because the
        # net widened is reported, not made to fail a build that passed
        # yesterday. Promoting one is a later decision, taken once consumers
        # have had a release to see it.
        known = name.endswith(".yml")
        say = (lambda cond, good, bad: ok(cond, good, bad)) if known else \
              (lambda cond, good, bad: result("PASS" if cond else "WARN", good if cond else bad))
        if name.endswith(".md"):
            # A legacy Markdown template is front matter and prose. GitHub reads
            # its `name:` from that front matter; the key alone is not a name,
            # and without a value there is no title to list the template under.
            good = bool(md_front_matter_name(text))
            say(good, f"{name} has Markdown front matter with a name",
                f"{name} has no front matter `name:` with a value: GitHub does not offer it as a template")
            usable += good
            continue
        keys = [k for k in ("name:", "description:", "body:") if not re.search(rf"^{k}", text, re.MULTILINE)]
        say(not keys, f"{name} has name, description, body", f"{name} lacks {keys}")
        # A value starting with `*` or `&` is read as a YAML alias and breaks the whole form.
        trap = [n for n, ln in enumerate(text.splitlines(), 1) if alias_trap.match(ln)]
        say(not trap, f"{name} has no unquoted YAML alias", f"{name} line {trap}: value starts with * or &")
        # `labels:` is plinth's policy, not GitHub's syntax: forms are valid
        # without it, so it does not decide whether GitHub can offer the file.
        labelled = re.search(r"^labels:\s*\[.+\]", text, re.MULTILINE) or re.search(r"^labels:\s*\n\s+- ", text, re.MULTILINE)
        say(labelled is not None, f"{name} labels its issues",
            f"{name} has no labels: those issues never sort in a list")
        # `body:` holding a scalar is a form GitHub rejects. This check is new
        # ground for every extension, so it never fails on its own; it decides
        # `usable` only for the extensions this file did not read before, where
        # no repository can have been passing on the strength of it.
        listed = yaml_body_is_list(text)
        if not keys:
            result("PASS" if listed else "WARN",
                   f"{name} body is a list" if listed else
                   f"{name} body is not a list: GitHub rejects a form whose body is not a sequence")
        usable += not keys and not trap and (listed or known)
    # An invalid extra is a WARN because the repository passed without it being
    # read. A repository whose every template is invalid never passed: it failed
    # the old filename check too, so leaving it green would be a loosening, not
    # compatibility.
    if forms:
        ok(usable > 0, f"at least one template GitHub can offer ({where})",
           f"no usable issue template ({where}): every file found is missing what GitHub needs to offer it")


def check_gitlab_templates(root: Path) -> None:
    """GitLab offers every `.md` under .gitlab/issue_templates/ and
    .gitlab/merge_request_templates/ by file name; no front matter. An issue
    template labels its issues with a `/label ~name` quick action, as
    plinth-template renders them; one without it is a WARN, as on GitHub."""
    for where, what, bad in ((".gitlab/issue_templates", "issue templates",
                              "every issue arrives in whatever shape its writer chose"),
                             (".gitlab/merge_request_templates", "merge request templates",
                              "the squash commit is made from whatever description the merge request has")):
        d = root / where
        found = sorted(p.name for p in d.iterdir() if p.is_file() and p.suffix == ".md" and p.stat().st_size > 0) \
            if d.is_dir() else []
        ok(bool(found), f"{what} found ({where}): {', '.join(found)}", f"no {what[:-1]} under {where}/: {bad}")
        if where.endswith("issue_templates"):
            for name in found:
                labelled = re.search(r"^/label\s+~\S", read(d / name), re.MULTILINE)
                result("PASS" if labelled else "WARN", f"{name} labels its issues" if labelled else
                       f"{name} has no `/label ~name` line: those issues never sort in a list")


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


def check_agent_settings(root: Path, host: str = "github") -> None:
    p = root / ".claude" / "settings.json"
    if not ok(p.is_file(), ".claude/settings.json present", ".claude/settings.json missing"):
        return
    try:
        deny = json.loads(read(p)).get("permissions", {}).get("deny", [])
    except json.JSONDecodeError:
        result("FAIL", ".claude/settings.json is not valid JSON")
        return
    def bash_rule_stops(cmd: str, d: str) -> bool:
        """A `*` in a Bash rule matches any text and nothing else is special
        (fnmatch would read `?` and `[...]` too). `Bash(source .env*` is not a
        rule: without the closing parenthesis `d[5:-1]` would drop the `*`."""
        if not (d.startswith("Bash(") and d.endswith(")")):
            return False
        return re.fullmatch(".*".join(map(re.escape, d[5:-1].split("*"))), cmd) is not None

    wants = {
        "force push": lambda d: d.startswith(("Bash(git push --force", "Bash(git push -f")),
        "rm -rf": lambda d: d.startswith("Bash(rm -rf"),
        "gh auth token": lambda d: d.startswith("Bash(gh auth token"),
        ".env reads": lambda d: d.startswith("Read(./.env"),
        # `Read(./.env)` also stops `cat`, `head`, `tail`, `sed`, `grep` and `<`
        # in Bash; `. ./.env` and `source .env` go through it (#128).
        "`. ./.env`": lambda d: bash_rule_stops(". ./.env", d),
        "`source .env`": lambda d: bash_rule_stops("source .env", d),
        # The Read deny's Bash check sees only a top-level command; `$(cat .env)`
        # and `(cat .env)` ran past it. A Bash rule reaches those (#136).
        "`cat .env`": lambda d: bash_rule_stops("cat .env", d),
        "`grep KEY .env`": lambda d: bash_rule_stops("grep KEY .env", d),
        "gh config reads": lambda d: d.startswith("Read(~/.config/gh"),
    }
    if host == "gitlab":
        # glab in gh's place (plinth-template v1.13.0): `-t` is `--show-token`
        # spelled short, so a deny of one alone leaves the other open.
        del wants["gh auth token"], wants["gh config reads"]
        wants["glab auth status --show-token"] = lambda d: bash_rule_stops("glab auth status --show-token", d)
        wants["glab auth status -t"] = lambda d: bash_rule_stops("glab auth status -t", d)
        wants["glab config get token"] = lambda d: bash_rule_stops("glab config get token", d)
        wants["glab config reads"] = lambda d: d.startswith("Read(~/.config/glab-cli")
    for what, match in wants.items():
        ok(any(match(d) for d in deny), f".claude/settings.json denies {what}",
           f".claude/settings.json does not deny {what}")


# The three predicates below were named by #42 and shipped by #95. Each is new
# ground: a repository passed yesterday without them being read, so a finding is
# a WARN, and promoting one to FAIL is a compatibility decision taken later.

# Placeholder dotenv names: committed on purpose, values not real.
DOTENV_PLACEHOLDERS = {".env.example", ".env.sample", ".env.template"}


def check_tracked_dotenv(root: Path) -> None:
    """Is a `.env` or `.env.<anything>` in the index? The evidence is git's, not
    the disk's: an untracked local `.env` is what `.gitignore` is for. Names
    only; the contents are not read, and this is not a secret scanner (history,
    other file names and `.envrc` are outside it)."""
    try:
        r = subprocess.run(["git", "-C", str(root), "ls-files", "-z"], capture_output=True, timeout=30, check=False,
                           encoding="utf-8", errors="replace")  # a file name is any bytes; never a traceback
    except (OSError, subprocess.TimeoutExpired):
        r = None
    if r is None or r.returncode != 0:
        result("SKIP", "tracked dotenv files not verified (git could not list the tracked files of --root)")
        return
    tracked = [f for f in r.stdout.split("\0") if f]
    found = sorted(f for f in tracked if (n := f.rsplit("/", 1)[-1]) not in DOTENV_PLACEHOLDERS
                   and (n == ".env" or n.startswith(".env.")))
    if not found:
        result("PASS", f"no dotenv file is tracked ({len(tracked)} tracked files read; names only, not contents or history)")
    for f in found:
        result("WARN", f"tracked dotenv file: {f}")
        result("INFO", f"  git rm --cached -- {shlex.quote(f)}   (ignore it in .gitignore; a value that was ever real is rotated, not only untracked)")


USES_LINE = re.compile(r"""^\s*(?:-\s+)?uses:\s+(['"]?)([^'"\s#]+)\1\s*(?:#.*)?$""")


def action_is_pinned(value: str) -> bool:
    if value.startswith("./"):
        return True  # a local action or workflow: the commit is this repository's own
    if value.startswith("docker://"):
        return re.search(r"@sha256:[0-9a-f]{64}$", value) is not None
    return re.fullmatch(r"[^@]+@[0-9a-fA-F]{40}", value) is not None


# A line whose value is a block scalar indicator (`run: |`, `key: >-`), a
# comment after it allowed. The key is matched from the line's start, so a
# `: |` inside a trailing comment (`jobs:  # note: |`) is not one (#334): a
# plain key holds no `: ` and no ` #`, a quoted one runs to its closing quote.
# The key is optional: an explicit key's value line (`? run` then `: |`) has none.
BLOCK_LINE = re.compile(r"""^\s*(?:-\s+)*(?:'(?:[^']|'')*'|"(?:[^"\\]|\\.)*"|[^\s#'"](?:[^\s:#]|:(?=\S)|(?<=\S)#|\s+(?=[^\s:#]))*)?"""
                        r"""\s*:\s*[|>][-+0-9]*\s*(?:#.*)?$""")


def yaml_lines(text: str):
    """Yield (line number, indent, line) for each line of workflow YAML text
    that is syntax: blank lines, comments and the interior of a block scalar
    (`run: |`) are skipped. The line reader iter_uses and the caller item
    share, so both skip the same ground the same way."""
    block = None
    for n, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        if block is not None:
            if indent > block:
                continue  # inside a block scalar: shell, not workflow syntax
            block = None
        if line.lstrip().startswith("#"):
            continue
        if BLOCK_LINE.match(line):
            # The scalar's lines sit deeper than its key, and after `- ` the key starts past the dash.
            block = cast("re.Match[str]", re.match(r"\s*(?:-\s+)*", line)).end()  # matches every string, if only empty
        yield n, indent, line


def iter_uses(text: str):
    """Yield (line, value, readable) for every apparent `uses:` in workflow
    YAML text. Lines, not a YAML parser (standard library only): comments and
    the interior of a block scalar (`run: |`) are skipped. `readable` is False
    for a `uses` the line pattern cannot parse (flow style, an anchored or
    explicit key); `value` is None in that case. Shared by check_action_pins
    and #219's plinth-pin lookup, so both skip the same ground the same way."""
    for n, _, line in yaml_lines(text):
        m = USES_LINE.match(line)
        if m:
            yield n, m.group(2), True
        # The net is wider than any one spelling: the word anywhere in the key part
        # of the line (`? uses`, `&a uses:`, `"uses":`), or as a key inside a flow
        # mapping. A word inside a value (`run: grep uses:`) is not a key.
        elif re.search(r"\buses\b", re.split(r":(?:\s|$)", line, maxsplit=1)[0]) \
                or re.search(r"""[{,]\s*['"]?uses['"]?\s*:""", line):
            yield n, None, False


def workflow_files(root: Path) -> list[Path]:
    """.github/workflows/*.yml|yaml, sorted. Shared by check_action_pins and
    #219's plinth-pin lookup, so both scan exactly the same files."""
    d = root / ".github" / "workflows"
    return sorted(p for p in d.iterdir() if p.is_file() and p.suffix in {".yml", ".yaml"}) if d.is_dir() else []


def check_action_pins(root: Path) -> None:
    """Every `uses:` in .github/workflows/*.yml|yaml is a full commit SHA (a
    sha256 digest for docker://, anything for a local ./ path). A `uses` the
    line pattern cannot read (iter_uses) is a SKIP, not a pass. Composite
    actions under .github/actions are not read, and whether a SHA exists
    upstream is not asked."""
    files = workflow_files(root)
    if not files:
        result("INFO", "no workflow file under .github/workflows: no action pin to check")
        return
    total, clean = 0, True
    for p in files:
        rel = p.relative_to(root).as_posix()
        unpinned, unread = [], []
        for n, value, readable in iter_uses(read(p)):
            if readable:
                total += 1
                if not action_is_pinned(value):
                    unpinned.append((n, value))
            else:
                unread.append(n)
        if unpinned:
            clean = False
            result("WARN", f"{rel}: not pinned to a full commit SHA: " + ", ".join(f"line {n} {v}" for n, v in unpinned))
            for v in sorted({v for _, v in unpinned}):
                m = re.fullmatch(r"([^/@]+/[^/@]+)(?:/[^@]*)?@(.+)", v)
                if v.startswith("docker://"):
                    result("INFO", f"  {v}: pin the image by digest (docker://image@sha256:<digest>)")
                elif m:
                    # Quoted: the line is pasted into a shell, and a ref may hold `$(...)` or `;`.
                    result("INFO", f"  gh api {shlex.quote(f'repos/{m.group(1)}/commits/{m.group(2)}')} --jq .sha   (then pin the uses: to that SHA, the old ref as its comment)")
                else:
                    result("INFO", f"  {v}: write it as owner/repo@<full commit SHA>")
        if unread:
            clean = False
            result("SKIP", f"{rel}: action pins not verified: line {', '.join(map(str, unread))} "
                           "mentions uses in a form this checker does not read")
    if clean:
        result("PASS", f"every action in {len(files)} workflow file{'s' * (len(files) != 1)} is pinned to a commit ({total} uses)")


# The reusable workflow a consumer's `ci` job calls (#325). Its jobs report as
# `ci / <job>`, the names the ruleset requires, so a `ci` job that stops calling
# it can put plain jobs of the same names in its place and every required check
# goes green.
CALLER_WORKFLOW = f"{PLINTH_REPO}/.github/workflows/python-ci.yml"
# What coolbress/plinth's own `ci` job calls instead, by local path; accepted
# for that repository only, and no other local workflow is.
PLINTH_OWN_CALLER = "./.github/workflows/plinth-ci.yml"
# The keys a `ci` job that calls the workflow may carry: the ones the
# template's does. Any other key a caller job can take (`if`, `needs`, `name`,
# `strategy`, `concurrency`) can get it skipped, rename its checks or cut it
# short while plain jobs report the `ci / <job>` names. A list of what is
# allowed, not of what is not: each review round found one more (#332).
CALLER_KEYS = {"uses", "with", "secrets", "permissions"}
# One `key:` line: a plain or quoted key, then nothing but an optional comment
# (a mapping follows) or a value.
KEY_LINE = re.compile(r"""^\s*([A-Za-z_][\w-]*|'[^']*'|"[^"]*")\s*:(?:\s+(.*?))?\s*$""")


def key_line(line: str) -> tuple[str, str] | None:
    """(key, value) of a plain `key: value` line, quotes and a trailing
    comment dropped from both; None for any other form (flow style, an
    anchor, an alias, an explicit `? key`)."""
    m = KEY_LINE.match(line)
    if not m:
        return None
    key, value = m.group(1).strip("'\""), (m.group(2) or "")
    value = "" if value.startswith("#") else value
    if key == "<<" or value[:1] in {"&", "*", "{", "["}:
        return None
    return key, value


def caller_job(text: str) -> tuple[str, str, dict[str, str | None]]:
    """What the `ci` job of a ci.yml calls: ("uses", value), ("missing", why),
    ("skippable", keys) or ("unread", why), with the inputs its `with:` block
    passes for ("uses", ...): name to plain value, None for one this reader
    cannot read (a value that continues on the next line, a key it cannot
    parse that names an input, a key given twice). Skippable is any key on the job
    outside CALLER_KEYS. A line reader, not a YAML parser (standard library
    only): a top-level `jobs:` block, its `ci:` key, and a `uses:` key directly
    under it. Anything in those three places it cannot read -- flow style, an
    anchor, an alias, a merge key, a duplicate key, a double-quoted key with
    an escape -- is unread, never a pass: it could hold or hide the call."""
    lines = list(yaml_lines(text))
    # A document marker opening the file (yamllint's document-start rule asks
    # for it) starts the one document; any later one is a second (#334).
    if lines and re.fullmatch(r"---\s*(?:#.*)?", lines[0][2]):
        lines = lines[1:]
    # A double-quoted key may spell another key with an escape (`"jo\u0062s"`
    # is `jobs` to YAML): a second jobs or ci this reader would not see.
    if any(re.match(r'^\s*(?:-\s+)?"[^"]*\\', line) for _, _, line in lines):
        return "unread", "a double-quoted key holds an escape, which can spell jobs or ci", {}
    tops = [(i, line) for i, (_, indent, line) in enumerate(lines) if indent == 0]
    jobs = [i for i, line in tops if (m := KEY_LINE.match(line)) and m.group(1).strip("'\"") == "jobs"]
    # Every top-level line has to be a plain or quoted `key: ...`, whatever its
    # value: an alias key (`*j:`), a merge key, a tag, an explicit `? key`, a
    # flow mapping or a document marker can each supply a second jobs.
    odd = next((line for _, line in tops if not KEY_LINE.match(line)), None)
    if odd is not None:
        return "unread", f"a top-level line is written in a form this checker does not read: {odd.strip()}", {}
    if len(jobs) > 1:
        return "unread", "more than one top-level jobs key", {}
    if not jobs:
        return "missing", "no `ci` job (no jobs at all)", {}
    start = jobs[0]
    if key_line(lines[start][2]) != ("jobs", ""):
        return "unread", "jobs is not a block mapping", {}
    body = []
    for _, indent, line in lines[start + 1:]:
        if indent == 0:
            break
        body.append((indent, line))
    if not body:
        return "missing", "no `ci` job (jobs is empty)", {}
    col = body[0][0]
    found = []
    for k, (indent, line) in enumerate(body):
        if indent < col:
            return "unread", "the jobs block is indented unevenly", {}
        if indent > col:
            continue
        kv = key_line(line)
        if kv is None:
            return "unread", f"a job key is written in a form this checker does not read: {line.strip()}", {}
        if kv[0] == "ci":
            if kv[1]:
                return "unread", f"the ci job is not a block mapping: {line.strip()}", {}
            found.append(k)
    if len(found) > 1:
        return "unread", "jobs has more than one ci key", {}
    if not found:
        return "missing", "no `ci` job", {}
    job = []
    for indent, line in body[found[0] + 1:]:
        if indent <= col:
            break
        job.append((indent, line))
    if not job:
        return "missing", "the `ci` job is empty", {}
    inner = job[0][0]
    uses, gates, withs = [], [], 0
    inputs: dict[str, str | None] = {}
    for k, (indent, line) in enumerate(job):
        if indent != inner:
            continue
        kv = key_line(line)
        if kv is None:
            return "unread", f"a key of the ci job is written in a form this checker does not read: {line.strip()}", {}
        if kv[0] not in CALLER_KEYS:
            gates.append(f"{kv[0]}:")
        if kv[0] == "with":
            withs += 1
            inputs = with_inputs(job[k + 1:], inner) if not kv[1] else {UNREAD_LINE: line.strip()}
        if kv[0] == "uses":
            m = USES_LINE.match(line)
            if not m:
                return "unread", f"the ci job's uses is written in a form this checker does not read: {line.strip()}", {}
            # A deeper line right under it continues the plain scalar: YAML
            # folds it into the value, which is then not the one read here.
            if k + 1 < len(job) and job[k + 1][0] > inner:
                return "unread", f"the ci job's uses continues on the next line: {job[k + 1][1].strip()}", {}
            uses.append(m.group(2))
    if len(uses) > 1:
        return "unread", "the ci job has more than one uses key", {}
    if withs > 1:
        return "unread", "the ci job has more than one with key", {}
    if not uses:
        return "missing", "the `ci` job calls no reusable workflow; it runs its own steps", {}
    if gates:
        return "skippable", " and ".join(gates), {}
    return "uses", uses[0], inputs


def with_inputs(lines: list[tuple[int, str]], parent: int) -> dict[str, str | None]:
    """The inputs a `with:` block passes: the lines deeper than `parent` that
    follow it, names in lower case. A key line carries its value; a deeper
    line under it continues that value, which is then not the one read. A
    line with no name this reader can take (`? key`, a merge key) is kept
    under UNREAD_LINE: it could pass either input."""
    out: dict[str, str | None] = {}
    block = []
    for indent, line in lines:
        if indent <= parent:
            break
        block.append((indent, line))
    if not block:
        return out
    col, last = block[0][0], None
    for indent, line in block:
        if indent > col:
            if last is not None:
                out[last] = None
            continue
        kv = key_line(line)
        if kv is None:
            name = re.match(r"""\s*['"]?([\w-]+)""", line)
            last = name.group(1).lower() if name else UNREAD_LINE
            out[last] = None if name else line.strip()
            continue
        last = kv[0].lower()
        value = re.sub(r"\s+#.*$", "", kv[1]).strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
            value = value[1:-1]
        out[last] = None if last in out else value
    return out


UNREAD_LINE = "<unread>"
# The inputs of python-ci.yml that set how much a check holds, and plinth's
# defaults for them (#435). A `with:` that loosens one past its default is a
# WARN every run: a project may choose the value, and the line keeps the choice
# visible after the pull request that set it. The other inputs have no agreed
# direction of "looser".
DEFAULT_MAX_DIFF_LINES = 400
DEFAULT_SEVERITY = "high"


def check_inputs(inputs: dict[str, str | None], where: str) -> None:
    """A WARN for each of the two inputs the `with:` loosens past plinth's
    default, a SKIP for each it passes in a form not read, and a SKIP for a
    line that could pass either."""
    if UNREAD_LINE in inputs:
        result("SKIP", f"the ci job {where} has a with: line this checker does not read: {inputs[UNREAD_LINE]}; "
                       "max-diff-lines and deps-fail-on-severity not verified")
    for name in ("max-diff-lines", "deps-fail-on-severity"):
        if name not in inputs:
            continue
        value = inputs[name]
        if value is None or "${{" in value:
            result("SKIP", f"the ci job {where} passes {name}: its value is not read (an expression, or a form this checker does not read)")
            continue
        if name == "max-diff-lines":
            try:
                n = float(value)
            except ValueError:
                n = math.nan
            if not math.isfinite(n) or n != int(n):
                result("SKIP", f"the ci job {where} passes max-diff-lines: {value}: not read as a whole number")
                continue
            if n <= 0:
                result("WARN", f"the ci job {where} passes max-diff-lines: {value}: ci / diff-size measures and never fails "
                               f"(plinth's default is {DEFAULT_MAX_DIFF_LINES})")
            elif n > DEFAULT_MAX_DIFF_LINES:
                result("WARN", f"the ci job {where} passes max-diff-lines: {value}, above plinth's default of "
                               f"{DEFAULT_MAX_DIFF_LINES}: a larger diff passes ci / diff-size")
        elif value == "critical":
            result("WARN", f"the ci job {where} passes deps-fail-on-severity: {value}: a high-severity advisory passes ci / deps "
                           f"(plinth's default is {DEFAULT_SEVERITY})")
        elif value not in {"high", "moderate", "low"}:
            result("SKIP", f"the ci job {where} passes deps-fail-on-severity: {value}: not read as a severity")


def check_web_input(inputs: dict[str, str | None], where: str, archetype: str | None) -> None:
    """A web project's ci job passes `web: true` (#614). Without it
    `ci / migrations` and `ci / deploy-check` pass as "does not apply" while
    the ruleset still requires them, so deleting the line would lower the
    standard with every check green. Only a literal true passes: missing,
    false, an expression or a form this checker does not read is a FAIL."""
    if archetype != "web":
        return
    value = inputs.get("web")
    if value is not None and value.strip().strip("'\"") in {"true", "True", "TRUE"}:
        result("PASS", f"the ci job {where} passes web: true, so ci / migrations and ci / deploy-check run")
        return
    seen = "no web: line" if "web" not in inputs else f"web: {value}" if value is not None else "a web: line this checker does not read"
    result("FAIL", f"the ci job {where} has {seen}: on the web archetype ci / migrations and ci / deploy-check "
                   "then pass as \"does not apply\" while the ruleset requires them")
    result("INFO", "  add `web: true` under the ci job's with:, as plinth-template renders it")


def check_caller(root: Path, repo: str | None, network: bool, from_checkout: bool = False,
                 archetype: str | None = None) -> None:
    """The `ci` job in .github/workflows/ci.yml calls plinth's python-ci.yml at
    a full commit SHA (#325). With --repo and the network, read from the
    default branch through the API (no ref), so a stale or feature-branch
    checkout does not hide a change that merged; otherwise from the checkout,
    and the line says so. from_checkout (--caller-from-checkout, what
    `ci / floor-check` passes) reads the checkout even then: in a pull
    request that is the pull request's own ci.yml, so a pull request that
    repairs a broken default branch is not failed by the file it repairs.
    coolbress/plinth calls its own plinth-ci.yml by local path; that one path
    is accepted, for that repository only. A pull request that removes the
    call removes `ci / floor-check` with it: only a run from outside the pull
    request's own workflows sees that, after the merge."""
    rel = ".github/workflows/ci.yml"
    if repo and network and not from_checkout:
        where = "on the default branch"
        data = api(f"repos/{repo}/contents/{rel}", network)
        if data is ABSENT:
            # A 404 is also what a repository that does not exist, or that
            # this token cannot see, answers for every file in it.
            if not isinstance(api(f"repos/{repo}", network), dict):
                result("SKIP", f"the ci job on the default branch not verified: repos/{repo} could not be read")
            else:
                result("FAIL", f"no {rel} on the default branch of {repo}: no `ci` job calls {CALLER_WORKFLOW}")
            return
        text = None
        if isinstance(data, dict) and data.get("encoding") == "base64" and isinstance(data.get("content"), str):
            try:
                text = base64.b64decode(data["content"]).decode("utf-8", errors="replace")
            except ValueError:
                text = None
        if text is None:
            result("SKIP", f"the ci job on the default branch not verified (the API did not return {rel} as a file)")
            return
    else:
        why = "--caller-from-checkout" if from_checkout else "--no-network" if not network else "no --repo"
        where = f"in the checkout ({why})" if from_checkout else f"in the checkout, not the default branch ({why})"
        p = root / rel
        if not p.is_file():
            result("SKIP", f"the ci job not verified: no {rel} in the checkout, and the default branch was not read ({why})")
            return
        text = read(p)
    kind, value, inputs = caller_job(text)
    if kind == "unread":
        result("SKIP", f"the ci job {where} not verified: {value}")
        return
    then = f"then set the ci job's uses: to {CALLER_WORKFLOW}@<that SHA>"
    latest = (f'gh api "repos/{PLINTH_REPO}/commits/$(gh api repos/{PLINTH_REPO}/releases/latest --jq .tag_name)" '
              f"--jq .sha   (plinth's latest release; {then})")
    if kind == "missing":
        result("FAIL", f"{rel} {where}: {value}, so nothing calls {CALLER_WORKFLOW} and plain jobs could report its check names")
        result("INFO", f"  {latest}")
        return
    if kind == "skippable":
        result("FAIL", f"the ci job {where} has {value}: only uses:, with:, secrets: and permissions: are allowed; "
                       "another key can get it skipped, renamed or cut short while plain jobs report its check names")
        result("INFO", f"  remove {value} from the `ci` job")
        return
    if repo and repo.lower() == PLINTH_REPO and value == PLINTH_OWN_CALLER:
        result("PASS", f"the ci job {where} calls {value} ({PLINTH_REPO} calls its own workflow by local path)")
        check_inputs(inputs, where)
        check_web_input(inputs, where, archetype)
        return
    m = re.fullmatch(r"([^/@]+/[^/@]+)(/[^@]*)@(.*)", value)
    if m and m.group(1).lower() == PLINTH_REPO and m.group(2) == CALLER_WORKFLOW[len(PLINTH_REPO):]:
        if re.fullmatch(r"[0-9a-fA-F]{40}", m.group(3)):
            result("PASS", f"the ci job {where} calls {value}")
        else:
            result("FAIL", f"the ci job {where} calls {value}: not pinned to a full commit SHA, so what runs can change without a pull request")
            # Quoted: the line is pasted into a shell, and a ref may hold `$(...)` or `;`.
            result("INFO", f"  gh api {shlex.quote(f'repos/{PLINTH_REPO}/commits/{m.group(3)}')} --jq .sha   ({then})")
        check_inputs(inputs, where)
        check_web_input(inputs, where, archetype)
    else:
        result("FAIL", f"the ci job {where} calls {value}, not {CALLER_WORKFLOW}")
        result("INFO", f"  {latest}")


def check_plinth_pins_agree(root: Path) -> None:
    """Every `uses:` of coolbress/plinth across the checkout's workflow files
    names the same full commit SHA (#447). ci.yml and label.yml are rendered
    at one commit; a hand edit that moves one leaves them apart, and the
    template-drift reason says so only while the template is behind. One SHA,
    or none, prints nothing. A WARN, never a FAIL: label / label is not a
    required check. A plinth `uses:` not on a full SHA is the action-pins
    item's WARN and is not counted here; a `uses:` it cannot read is a SKIP
    unless the readable ones already disagree, since it could be a plinth pin
    at another commit. The owner/repository and the SHA compare in lower case,
    as GitHub reads them; the fix line names each as written, since sed
    matches case, and rewrites only plinth references."""
    # file -> (owner/repository as written, ref as written), in order, once each
    by_file: dict[str, list[tuple[str, str]]] = {}
    unread: list[str] = []
    for p in workflow_files(root):
        for n, value, readable in iter_uses(read(p)):
            if not readable:
                unread.append(f"{p.name} line {n}")
                continue
            m = re.fullmatch(r"([^/@]+/[^/@]+)/[^@]*@([0-9a-fA-F]{40})", value)
            if m and m.group(1).lower() == PLINTH_REPO and m.groups() not in by_file.setdefault(p.name, []):
                by_file[p.name].append((m.group(1), m.group(2)))
    if len({ref.lower() for pins in by_file.values() for _, ref in pins}) < 2:
        if unread:
            result("SKIP", f"plinth workflow pins not compared: {', '.join(unread)} mentions uses in a form "
                           "this checker does not read, and could pin coolbress/plinth at another commit")
        return
    # The ci job's file first: the fix moves the others to the SHA it calls.
    names = sorted(by_file, key=lambda f: (f != "ci.yml", f))
    parts = [f"{f} at {' and '.join(dict.fromkeys(ref.lower() for _, ref in by_file[f]))}" for f in names]
    result("WARN", f"workflow pins disagree: {names[0]} calls plinth{parts[0][len(names[0]):]}"
                   + "".join(f", {x}" for x in parts[1:]))
    target = None
    ci = root / ".github" / "workflows" / "ci.yml"
    if ci.is_file():
        kind, value, _ = caller_job(read(ci))
        m = re.fullmatch(r"([^/@]+/[^/@]+)(/[^@]*)@([0-9a-fA-F]{40})", value) if kind == "uses" else None
        if m and m.group(1).lower() == PLINTH_REPO and m.group(2) == CALLER_WORKFLOW[len(PLINTH_REPO):]:
            target = m.group(3)
    if target is None:
        result("INFO", f"  set every {PLINTH_REPO} uses: to the one commit the ci job should call")
        return
    for f in names:
        for repo, old in by_file[f]:
            if old.lower() != target.lower():
                path = shlex.quote(f".github/workflows/{f}")
                # Only `<owner/repository>/<path>@<old>`: the same SHA elsewhere in the file is left alone.
                repo_re = repo.replace(".", r"\.")
                result("INFO", f"  sed -i.bak 's|{repo_re}/\\([^@]*\\)@{old}|{repo}/\\1@{target}|g' {path} && rm {path}.bak   "
                               "(moves it to the SHA the ci job calls)")


def new_project_pin() -> tuple[str, str, str, str, str] | None:
    """(template_repo, template_ref, template_sha, copier_version, copier_newer) as
    scripts/new-project.sh pins them -- read from that file and nowhere else
    (#219), so a template release only has to move the pin once. Found beside
    this file: locally, where both live in scripts/; in CI's floor-check job,
    which downloads both from the same plinth commit into the same directory."""
    p = Path(__file__).resolve().parent / "new-project.sh"
    if not p.is_file():
        return None
    text = read(p)
    fields = {}
    for name in ("template_repo", "template_ref", "template_sha", "copier_version", "copier_newer"):
        m = re.search(rf'^{name}="([^"]+)"$', text, re.MULTILINE)
        if not m:
            return None
        fields[name] = m.group(1)
    if not re.fullmatch(r"[0-9a-f]{40}", fields["template_sha"]):
        return None
    return (fields["template_repo"], fields["template_ref"], fields["template_sha"],
            fields["copier_version"], fields["copier_newer"])


def copier_answers(root: Path) -> dict[str, str] | None:
    """.copier-answers.yml as a flat mapping. Not a YAML parser (standard
    library only): one `key: value` per line, quotes stripped. The file the
    door writes has no nesting."""
    p = root / ".copier-answers.yml"
    if not p.is_file():
        return None
    out: dict[str, str] = {}
    for line in read(p).splitlines():
        m = re.match(r"^([A-Za-z_]\w*):\s*(.*)$", line)
        if m:
            out[m.group(1)] = m.group(2).strip().strip("'\"")
    return out


def resolve_plinth_pin(root: Path) -> tuple[str | None, str | None]:
    """The commit of coolbress/plinth this repository's CI calls today
    (#219): read from its own workflow `uses:` lines, the live truth
    Dependabot moves and `.copier-answers.yml` never does (a `plinth_sha` an
    update would otherwise take from a stale recorded answer or the
    template's own default, neither of which is what Dependabot last set).
    Returns (sha, None) once established, or (None, reason) when it is not.
    A plinth `uses:` not pinned to a full commit SHA is unknown too, not
    silently dropped: today's pin is not established while any of them could
    be tracking a moving ref (#233 review). So is any `uses:` this checker
    cannot parse at all (flow style, an anchored or explicit key): its value
    is unread, so it cannot be ruled out as a second, disagreeing plinth pin
    either (#233 review, round 2)."""
    shas: set[str] = set()
    loose = unread = False
    for p in workflow_files(root):
        for _, value, readable in iter_uses(read(p)):
            if not readable:
                unread = True
            elif value.startswith(f"{PLINTH_REPO}/"):
                ref = value.rpartition("@")[2]
                if re.fullmatch(r"[0-9a-fA-F]{40}", ref):
                    shas.add(ref)
                else:
                    loose = True
    if unread:
        return None, "a workflow uses: line could not be read; it may or may not pin coolbress/plinth"
    if loose:
        return None, f"a {PLINTH_REPO} workflow uses: line is not pinned to a full commit SHA"
    if len(shas) == 1:
        return next(iter(shas)), None
    if not shas:
        return None, f"no {PLINTH_REPO} workflow uses: line found"
    return None, f"workflow pins disagree: {', '.join(sorted(shas))}"


def resolve_gitlab_pin(root: Path) -> tuple[str | None, str | None, str | None]:
    """On GitLab (#547 review): the commit and checksum of the include of
    plinth's GitLab pipeline in .gitlab-ci.yml, the pin the pipeline runs
    today, as resolve_plinth_pin reads the workflows on GitHub. Not a YAML
    parser: the `remote:` line of the URL, and the `integrity:` line right
    after it, as the template renders them. Returns (sha, integrity, None),
    or (None, None, reason) unless there is exactly one such include, at a
    full commit SHA, with a checksum, and no other line naming plinth."""
    p = root / ".gitlab-ci.yml"
    if not p.is_file():
        return None, None, "no .gitlab-ci.yml"
    text = read(p)
    url = r"https://raw\.githubusercontent\.com/coolbress/plinth/([^/\s'\"]+)/gitlab/python-ci\.yml"
    found = re.findall(rf"^[ \t]*-?[ \t]*remote:[ \t]*['\"]?{url}['\"]?[ \t]*\n[ \t]*integrity:[ \t]*['\"]?sha256-([A-Za-z0-9+/]{{43}}=)['\"]?[ \t]*$",
                       text, re.MULTILINE)
    # The template's own comment names coolbress/plinth; only the definition counts.
    mentions = sum(1 for ln in text.splitlines() if not ln.lstrip().startswith("#") and "coolbress/plinth" in ln.lower())
    if len(found) != 1 or mentions != 1:
        return None, None, ("the include of plinth's GitLab pipeline is not one `remote:` line followed by its "
                            "`integrity:` line, as the template renders it")
    sha, integrity = found[0]
    if not re.fullmatch(r"[0-9a-fA-F]{40}", sha):
        return None, None, f"the include of plinth's GitLab pipeline is at {sha}, not a full commit SHA"
    return sha, integrity, None


def template_drift(root: Path, host: str | None = None) -> dict:
    """Where this repository stands against the template tag plinth is
    tested with, and the one `copier update` command that moves it there
    (#219). Offline. The drift item below prints it; --print-update-command
    prints the command alone for the template-update skill (#232), so the
    command that runs is the one this item prints, never a second
    construction of it. `state` is skip, ahead, current or behind; `reason`
    says why a skip was not verified; `cmd` is set only when behind and the
    plinth pin is established, and `why_not` says why it is not. `host` is
    the host the run resolved (--host first, then the answers); without it,
    the answers' `host:` (#547 review)."""
    pin = new_project_pin()
    if pin is None:
        return {"state": "skip", "reason": "scripts/new-project.sh not found beside the checker, or unreadable"}
    template_repo, target, target_sha, copier_version, copier_newer = pin
    out: dict = {"template_repo": template_repo, "target": target, "target_sha": target_sha}

    answers = copier_answers(root)
    if answers is None:
        return {**out, "state": "skip", "reason": "no .copier-answers.yml: not made by the door"}
    src_path = answers.get("_src_path", "")
    # Exactly what the door writes, not a substring: a foreign source such as
    # a local checkout at .../coolbress/plinth-template would otherwise pass
    # too, and copier update would then pull from it, not the real template
    # (#233 review).
    if src_path != f"gh:{template_repo}":
        return {**out, "state": "skip", "reason": f"_src_path {src_path!r} is not gh:{template_repo}, the door's own form"}
    if "_commit" not in answers:
        return {**out, "state": "skip", "reason": ".copier-answers.yml has no _commit"}
    recorded = answers["_commit"]
    if not re.fullmatch(r"v\d+\.\d+\.\d+", recorded):
        return {**out, "state": "skip", "reason": f"recorded tag {recorded!r} is not an exact release tag"}
    out["recorded"] = recorded

    def key(tag: str) -> tuple[int, ...]:
        return tuple(int(x) for x in tag[1:].split("."))

    if key(recorded) > key(target):
        return {**out, "state": "ahead"}
    if recorded == target:
        return {**out, "state": "current"}

    integrity = None
    if (host or answers.get("host")) == "gitlab":
        sha, integrity, why_not = resolve_gitlab_pin(root)
    else:
        sha, why_not = resolve_plinth_pin(root)
    # --defaults: without a terminal copier update stops at "Interactive
    # session required" (measured, copier 9.18.2), and the skill that runs
    # this line has none. It answers each question with the recorded answer.
    out.update(copier_version=copier_version, copier_newer=copier_newer)
    out["integrity"] = integrity
    out["host"] = host or answers.get("host")
    return {**out, "state": "behind", "cmd": update_line(out, sha, integrity) if sha else None, "why_not": why_not, "live": sha}


def update_line(d: dict, pin: str, integrity: str | None = None) -> str:
    """The `copier update` line to the target tag, carrying plinth pin `pin`,
    and on GitLab the include's checksum at that pin: a pin moved without its
    checksum fails every pipeline before a job runs. It fetches the tag's
    pinned commit, not the tag (#519): copier still records the tag as
    `_commit` (measured, copier 9.18.2)."""
    return (f"uvx --from copier=={d['copier_version']} --exclude-newer {d['copier_newer']} "
            f"copier update --defaults --vcs-ref {d['target_sha']} --data plinth_sha={pin}"
            + (f" --data plinth_gitlab_integrity={shlex.quote(integrity)}" if integrity else "")
            + d.get("owner_data", ""))


SHARED_GITHUB = Path(__file__).resolve().parent / "lib" / "shared-github.sh"
PR_TEMPLATE_PATHS = ("PULL_REQUEST_TEMPLATE.md", ".github/PULL_REQUEST_TEMPLATE.md", "docs/PULL_REQUEST_TEMPLATE.md")


def owner_shared(d: dict, owner: str | None, network: bool, root: Path) -> None:
    """On GitHub, give the update line the owner's answers, as
    /plinth:new-project gives `copier copy` (#726): whether `<owner>/.github`
    publishes a pull-request template and issue forms. Without them the
    update reads both as false, and a form the target tag added lands as one
    local file, which hides every form the owner shares. The same reads as
    new-project.sh, decided by the same functions (scripts/lib/shared-github.sh);
    fetched here, through `api`, so fixtures serve them. A read that fails is
    not an answer: `cmd` is withdrawn and `why_not` says why.

    An answer is true only while this repository has none of its own. Its
    own already replace the owner's (the forms per folder, the pull-request
    template per file), so a new one beside them hides nothing; and true
    would have copier delete them, a form edited by hand included, without
    a conflict (measured, copier 9.18.2). `owner_notes` say when either
    happens, and when the owner's folder holds a config and no form."""
    if not d.get("cmd") or (d.get("host") or "github") == "gitlab":
        return
    forms_dir = root / ".github" / "ISSUE_TEMPLATE"
    own_forms = forms_dir.is_dir() and any(p.is_file() and p.suffix in FORM_SUFFIXES for p in forms_dir.iterdir())
    own_pr = any((root / p).is_file() for p in PR_TEMPLATE_PATHS)
    notes: list[str] = []
    d["owner_notes"] = notes

    def withdraw(why: str) -> None:
        d["cmd"], d["why_not"] = None, why

    if own_forms and own_pr:
        d["owner_data"] = " --data owner_has_pr_template=false --data owner_has_issue_forms=false"
        d["cmd"] = update_line(d, d["live"], d.get("integrity"))
        return
    if not owner:
        withdraw("no --repo, so whether the owner's .github publishes a pull-request template or issue forms was "
                 "not read; without that answer the update reads both as false and can write a form that hides "
                 "the owner's shared ones")
        return
    if not SHARED_GITHUB.is_file():
        withdraw(f"{SHARED_GITHUB} not found beside the checker, so the owner's .github could not be judged")
        return

    def fetched(data, text) -> str:  # an `api` answer as new-project.sh's gh_read writes it
        if data is ABSENT:
            return "err:HTTP 404 Not Found"
        if data is ERROR:
            return "err:offline or API error"
        got = text(data)
        return "err:an unexpected response" if got is None else "ok:" + got

    def decide(fn: str, *answers: str) -> str:
        try:
            r = subprocess.run(["bash", "-c", '. "$0" && "$@"', str(SHARED_GITHUB), fn, *answers],
                               capture_output=True, text=True, check=False)
        except OSError as e:
            return f"unknown: {fn} did not run ({e})"
        out = r.stdout.strip()
        return out if r.returncode == 0 and out else f"unknown: {fn} gave no answer ({r.stderr.strip()})"

    def why(answer: str) -> str:
        return answer.removeprefix("unknown: ")

    shared = f"repos/{owner}/.github"
    vis = decide("shared_repo_public", fetched(api(shared, network), lambda j: j.get("visibility")
                                                if isinstance(j, dict) and isinstance(j.get("visibility"), str)
                                                else None))
    if vis.startswith("unknown"):
        withdraw(f"cannot read whether {owner}/.github is public ({why(vis)}); a failed lookup is not an answer: "
                 f"only a public .github repository is inherited from")
        return
    has_pr = has_forms = "no"
    if vis == "yes":
        pr_answers: list[str] = []
        for path in PR_TEMPLATE_PATHS:
            pr_answers += [path, fetched(api(f"{shared}/contents/{path}", network), lambda _: "")]
        has_pr = decide("shared_of", *pr_answers)
        listing = api(f"{shared}/contents/.github/ISSUE_TEMPLATE", network)
        names: list[str] | None = ([e["name"] for e in listing if isinstance(e, dict) and isinstance(e.get("name"), str)]
                                   if isinstance(listing, list) else None)
        form_answers = [fetched(listing, lambda _: None if names is None else "\n".join(names))]
        for name in names or []:
            form_answers += [name, fetched(api(f"{shared}/contents/.github/ISSUE_TEMPLATE/{name}", network),
                                           lambda j: j.get("content") if isinstance(j, dict)
                                           and isinstance(j.get("content"), str) else None)]
        has_forms = decide("shared_forms", *form_answers)
        bad = has_pr if has_pr.startswith("unknown") else has_forms
        if bad.startswith("unknown"):
            withdraw(f"cannot read whether {owner}/.github publishes shared templates ({why(bad)}); a failed lookup "
                     f"is not an answer: writing ours could replace yours, and skipping ours could leave none")
            return
        if has_forms == "config-only" and not own_forms:
            notes.append(f"{owner}/.github publishes an issue-template config but no form; the update writes "
                         f"the template's forms and config, and that config does not apply here")
    if has_forms == "yes" and own_forms:
        notes.append(f"{owner}/.github shares issue forms, but this repository's own .github/ISSUE_TEMPLATE "
                     f"replaces them; the update keeps those and adds the template's new ones beside them")
    if has_pr == "yes" and own_pr:
        notes.append(f"{owner}/.github shares a pull-request template, but this repository has its own; the "
                     f"update keeps it")
    pr = has_pr == "yes" and not own_pr
    forms = has_forms == "yes" and not own_forms
    d["owner_data"] = (f" --data owner_has_pr_template={'true' if pr else 'false'}"
                       f" --data owner_has_issue_forms={'true' if forms else 'false'}")
    d["cmd"] = update_line(d, d["live"], d.get("integrity"))


def tested_plinth_pin(template_repo: str, target: str, network: bool,
                      key: str = "plinth_sha", value: str = r"[0-9a-fA-F]{40}",
                      at: str | None = None) -> tuple[str | None, str | None]:
    """The plinth commit the target template tag was tested with: the
    `plinth_sha` default in that tag's copier.yml (#511), or with key and
    value another default there (plinth_gitlab_integrity, #547), read at
    commit `at`, the one the tag is pinned to (#519). Returns
    (value, None), or (None, reason) when it is not read. Not a YAML parser:
    the `default:` line inside the top-level `<key>:` block."""
    data = api(f"repos/{template_repo}/contents/copier.yml?ref={at or target}", network)
    if data in (ABSENT, ERROR):
        return None, f"{template_repo} copier.yml at {target}: offline or API error"
    try:
        text = base64.b64decode(data["content"]).decode()
    except (TypeError, KeyError, ValueError):
        return None, f"{template_repo} copier.yml at {target}: an unexpected contents response"
    m = re.search(rf"^{key}:[ \t]*\n((?:[ \t]+.*\n|[ \t]*\n)*)", text + "\n", re.MULTILINE)
    d = re.search(rf"^[ \t]+default:[ \t]*[\"']?({value})[\"']?[ \t]*$", m.group(1), re.MULTILINE) if m else None
    if not d:
        what = "a full commit SHA" if key == "plinth_sha" else "a checksum"
        return None, f"{template_repo} copier.yml at {target} has no {key} default that is {what}"
    return (d.group(1).lower() if key == "plinth_sha" else d.group(1)), None


def target_tag(d: dict, network: bool) -> tuple[str, str]:
    """Does the target tag still name the commit plinth was tested with,
    new-project.sh's template_sha beside its template_ref (#519)? The doors
    stop before rendering when it does not; the update command is the same
    render, so it is offered only on the same pair. Returns ("pinned", ""),
    ("moved", <the commit it names now>) or ("unread", <why>)."""
    data = api(f"repos/{d['template_repo']}/commits/{d['target']}", network)
    if data in (ABSENT, ERROR):
        return "unread", ("the tag was not found" if data is ABSENT else "offline or API error")
    now = data.get("sha") if isinstance(data, dict) else None
    if not isinstance(now, str) or not re.fullmatch(r"[0-9a-fA-F]{40}", now):
        return "unread", "an unexpected commit response"
    return ("pinned", "") if now.lower() == d["target_sha"] else ("moved", now.lower())


def moved_note(d: dict, now: str) -> str:
    return (f"template: {d['target']} now names commit {now}, not {d['target_sha']}, the commit plinth was "
            f"tested with; no update command until a plinth release names the tag's commit again")


def plinth_pin_choice(d: dict, network: bool) -> dict:
    """When the update is behind and the live pin is known: the live pin
    against the one the target tag was tested with (#511). #219 carries the
    live pin on purpose, so an update never overwrites what Dependabot set;
    this offers the tested pin beside it, only when it is newer, for a
    person to confirm. `state` is tested-ahead (`cmd` is the line with the
    tested pin, `recommend` the one plain sentence on what moving to it
    gains, #519), equal (`cmd` is the live line), live-ahead or unread (no
    `cmd`); `note` is the one line that says so, naming both SHAs when read."""
    live = d["live"].lower()
    calls = "the include is at" if d.get("integrity") else "the workflows call"
    target = d["target"]
    tested, why = tested_plinth_pin(d["template_repo"], target, network, at=d["target_sha"])
    if tested is None:
        return {"state": "unread", "note": f"plinth pin: the one {target} was tested with was not read ({why}); "
                                           f"the live pin {live} is kept"}
    if tested == live:
        return {"state": "equal", "tested": tested, "cmd": d["cmd"],
                "note": f"plinth pin: {calls} {live}, the one {target} was tested with"}
    url = f"https://github.com/{PLINTH_REPO}/compare/{live}...{tested}"
    tags: dict[str, list[str]] = {}
    listing = api(f"repos/{PLINTH_REPO}/tags?per_page=100", network, paginate=True)
    for t in listing if isinstance(listing, list) else []:
        sha = t.get("commit", {}).get("sha", "") if isinstance(t, dict) else ""
        if isinstance(sha, str) and isinstance(t.get("name"), str):
            tags.setdefault(sha.lower(), []).append(t["name"])
    # A failed tag read is said, not shown as an untagged commit (#512 review).
    tag_gap = "" if isinstance(listing, list) else " (release tags not read)"

    def name(sha: str) -> str:
        return f"{sha} ({', '.join(sorted(tags[sha]))})" if sha in tags else sha

    cmp = api(f"repos/{PLINTH_REPO}/compare/{live}...{tested}", network)
    status = cmp.get("status") if isinstance(cmp, dict) else None
    if status == "ahead":
        n = cmp.get("ahead_by")
        by = f", {n} commit(s) newer" if isinstance(n, int) else ", newer"
        integrity = None
        if d.get("integrity"):
            # On GitLab the tested pin moves with the checksum the same tag was tested with.
            integrity, why = tested_plinth_pin(d["template_repo"], target, network,
                                               "plinth_gitlab_integrity", r"[A-Za-z0-9+/]{43}=", d["target_sha"])
            if integrity is None:
                return {"state": "unread", "tested": tested,
                        "note": f"plinth pin: the include is at {live}; {target} was tested with {tested}, but its "
                                f"checksum was not read ({why}); the live pin is kept"}
        newer = f"{n} commit(s) newer than" if isinstance(n, int) else "newer than"
        checks = "pipeline" if d.get("integrity") else "checks"
        return {"state": "tested-ahead", "tested": tested, "cmd": update_line(d, tested, integrity),
                "note": f"plinth pin: {calls} {name(live)}; {target} was tested with "
                        f"{name(tested)}{by}{tag_gap}: {url}",
                "recommend": f"move the plinth pin to {name(tested)}: this repository's {checks} then run "
                             f"the plinth commit {target} was tested with, {newer} the one they run now, so what "
                             f"plinth changed in between reaches it"}
    if status == "behind":
        return {"state": "live-ahead", "tested": tested,
                "note": f"plinth pin: {calls} {name(live)}, newer than {name(tested)} that {target} "
                        f"was tested with; the live pin is kept, never moved backwards{tag_gap}: {url}"}
    why = ("the two commits have diverged" if status == "diverged"
           else "offline or API error" if cmp in (ABSENT, ERROR) else "an unexpected compare response")
    return {"state": "unread", "tested": tested,
            "note": f"plinth pin: {calls} {live}; {target} was tested with {tested}, but the two "
                    f"were not compared ({why}); the live pin is kept"}


def check_template_drift(root: Path, network: bool, host: str | None = None, owner: str | None = None) -> None:
    """#219 stage 1: has the template plinth is tested with today moved past
    the tag this repository was rendered from? Reports the drift and an
    update command; runs nothing that writes. A PASS means only that the
    recorded tag is the target tag -- not that this repository's own render
    matches it file for file: another archetype, inherited forms or a
    hand-made edit can mean a changed template file was never rendered here."""
    d = template_drift(root, host)
    if d["state"] == "skip":
        result("SKIP", f"template drift not verified ({d['reason']})")
        return
    template_repo, target = d["template_repo"], d["target"]
    recorded = d["recorded"]
    if d["state"] == "ahead":
        result("INFO", f"template: the recorded tag {recorded} is ahead of {target}, the tag plinth is tested with")
        return
    if d["state"] == "current":
        # A tag moved since this repository was rendered from it (#519).
        tag, now = target_tag(d, network)
        if tag == "moved":
            result("WARN", f"template: the recorded tag is the target tag ({target}), but {target} now names "
                           f"commit {now}, not {d['target_sha']}, the commit plinth was tested with")
            return
        # The PASS claims the tags only; whether the tag still names its
        # commit is said beside it when unread, not counted: every offline
        # run would otherwise count it as not verified.
        result("PASS", f"template: the recorded tag is the target tag ({target})")
        if tag == "unread":
            result("INFO", f"  not verified that {target} still names {d['target_sha']}, the commit "
                           f"plinth was tested with ({now})")
        return

    cmp = api(f"repos/{template_repo}/compare/{recorded}...{target}", network)
    if cmp in (ABSENT, ERROR):
        changed, unread_reason = None, "offline or API error"
    elif isinstance(cmp, dict) and isinstance(cmp.get("files"), list):
        changed = [f for f in cmp["files"] if isinstance(f, dict) and f.get("filename", "").startswith("template/")]
        unread_reason = None
    else:
        # A well-formed reply that still carries no `files` list (GitHub omits
        # it for a very large diff): read, but not into what was expected.
        changed, unread_reason = None, "an unexpected compare response"

    if changed is None:
        result("WARN", f"template: {recorded} is behind {target}, the tag plinth is tested with; "
                       f"the changed files could not be read ({unread_reason})")
    else:
        names = sorted(f["filename"][len("template/"):] for f in changed)
        result("WARN", f"template: {recorded} is behind {target}, the tag plinth is tested with; "
                       f"changed in the template: {', '.join(names) if names else '(nothing under template/)'}")
        result("INFO", "  the template's own change between the two tags, not this repository's diff: another "
                       "archetype, inherited forms or a hand-made edit can mean some of it was never rendered here")
        by_name = {f["filename"][len("template/"):]: f for f in changed}
        for name in TEMPLATE_DRIFT_DIFF_FILES:
            entry = by_name.get(name)
            patch = entry.get("patch") if isinstance(entry, dict) else None
            if patch:
                result("INFO", f"  {name}:")
                for pline in patch.splitlines():
                    result("INFO", f"    {pline}")

    owner_shared(d, owner, network, root)
    if not d["cmd"]:
        result("INFO", f"  no update command: {d['why_not']}")
        return
    for note in d.get("owner_notes", []):
        result("INFO", f"  {note}")
    tag, why = target_tag(d, network)
    if tag == "moved":
        result("WARN", moved_note(d, why))
        return
    if tag == "unread":
        result("INFO", f"  not verified that {target} still names {d['target_sha']}, the commit plinth was tested "
                       f"with ({why}); the template-update skill checks it before it runs this line:")
    result("INFO", f"  {d['cmd']}")
    choice = plinth_pin_choice(d, network)
    if choice["state"] == "equal":
        return
    result("INFO", f"  {choice['note']}")
    if choice["state"] == "tested-ahead":
        result("INFO", "  the line above keeps the live pin; this one moves it to the tested pin, if you choose it:")
        result("INFO", f"  {choice['cmd']}")


def print_update_command(root: Path, plinth_pin: str = "live", network: bool = True, host: str | None = None,
                         owner: str | None = None) -> int:
    """--print-update-command: the drift item's command line alone on
    stdout, exit 0; otherwise why there is none on stderr, exit 1. With
    --plinth-pin tested, the line with the tested pin, and the comparison
    on stderr whether or not there is one: --plinth-pin tested never prints
    a line that would move the pin backwards or past an unread comparison."""
    d = template_drift(root, host)
    owner_shared(d, owner, network, root)
    for note in d.get("owner_notes", []):
        print(note, file=sys.stderr)
    if d.get("cmd"):
        # Fail closed: this is the line that runs.
        tag, why = target_tag(d, network)
        if tag != "pinned":
            print("no update command: " + (moved_note(d, why) if tag == "moved" else
                  f"not verified that {d['target']} still names {d['target_sha']}, the commit plinth was tested with ({why})"),
                  file=sys.stderr)
            return 1
    if d.get("cmd") and plinth_pin == "tested":
        choice = plinth_pin_choice(d, network)
        print(choice["note"], file=sys.stderr)
        if choice.get("recommend"):
            print(f"recommended: {choice['recommend']}", file=sys.stderr)
        if choice.get("cmd"):
            print(choice["cmd"])
            return 0
        print("no update command with the tested pin: only the live pin's line stands", file=sys.stderr)
        return 1
    if d.get("cmd"):
        print(d["cmd"])
        return 0
    why = {
        "skip": lambda: f"template drift not verified ({d['reason']})",
        "ahead": lambda: f"the recorded tag {d['recorded']} is ahead of {d['target']}, the tag plinth is tested with",
        "current": lambda: f"the recorded tag is the target tag ({d['target']}): nothing to update",
        "behind": lambda: f"{d['recorded']} is behind {d['target']}, but there is no update command: {d['why_not']}",
    }[d["state"]]()
    print(f"no update command: {why}", file=sys.stderr)
    return 1


def check_doc_links(root: Path) -> None:
    link = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
    fenced = re.compile(r"```.*?```", re.DOTALL)
    inline = re.compile(r"`[^`\n]*`")
    docs = [p for p in root.rglob("*.md") if not (set(p.relative_to(root).parts) & SKIP_DIRS)]
    if not docs:
        result("FAIL", "no markdown document found at all")
        return
    broken: dict[str, list[str]] = {}
    # A symbolic link whose target is missing has nothing to read: named, not
    # read, so the checker reports it instead of stopping (#525).
    dangling = [d for d in docs if d.is_symlink() and not d.exists()]
    for doc in docs:
        if doc in dangling:
            continue
        text = inline.sub("", fenced.sub("", read(doc)))
        for target in link.findall(text):
            if target.startswith(("http://", "https://", "mailto:", "#")):
                continue
            path = (doc.parent / target.split("#", 1)[0]).resolve()
            if root.resolve() not in path.parents and path != root.resolve():
                continue  # outside the repository: a GitHub-interpreted URL, not a file
            if not path.exists():
                broken.setdefault(doc.relative_to(root).as_posix(), []).append(target)
    why = []
    if broken:
        why.append(f"links to files that do not exist: {broken}")
    if dangling:
        why.append("symbolic links to files that do not exist: " + ", ".join(
            f"{d.relative_to(root).as_posix()} -> {os.readlink(d)}" for d in dangling))
    ok(not broken and not dangling, f"relative links in {len(docs)} markdown files resolve",
       "; ".join(why))


# ── project-level floor ───────────────────────────────────────────────────


def archetype_of(project: Path, given: str | None) -> str | None:
    if given:
        return given
    answers = project / ".copier-answers.yml"
    if answers.is_file():
        m = re.search(r"^archetype:\s*(\S+)", read(answers), re.MULTILINE)
        if m:
            return m.group(1).strip("'\"")
    return None


def package_name(project: Path) -> str | None:
    if not (project / "pyproject.toml").is_file():
        return None
    m = re.search(r'^name\s*=\s*"([^"]+)"', read(project / "pyproject.toml"), re.MULTILINE)
    return m.group(1).replace("-", "_") if m else None


def projects_below(root: Path) -> list[str]:
    """Directory names one level under --root that hold a pyproject.toml
    (#221). One level and no further, and never a dot directory, one of
    SKIP_DIRS or a symlink: the point is to name the project the reader
    meant, not to search the tree. `--project` is relative to --root, so a name here is
    already what that flag takes."""
    try:
        entries = sorted(root.iterdir())
    except OSError:
        return []
    # is_dir() follows symlinks, so a link at the root pointing outside the
    # checkout would be offered as this repository's project and the reader
    # would be sent to read a tree that is not in it. A symlinked project
    # directory therefore gets no hint, which is what today already does.
    # isprintable() for the same reason one step further: this name is printed
    # into a result line the skill hands on whole, so a newline in it splits
    # that line and the rest reads as further results -- a directory named
    # "app\n  PASS  forged" put a PASS in the report (#238 review). Such a
    # name gets no hint either.
    return [d.name for d in entries
            if not d.name.startswith(".") and d.name not in SKIP_DIRS and d.name.isprintable()
            and not d.is_symlink() and d.is_dir() and (d / "pyproject.toml").is_file()]


# The lockfiles GitHub's dependency graph reads for npm packages; Bun's is not
# one of them, so dependency review sees nothing in a repository locked by Bun
# alone (#611 Findings).
NODE_LOCKFILES = ("package-lock.json", "npm-shrinkwrap.json", "yarn.lock", "pnpm-lock.yaml")
BUN_LOCKFILES = ("bun.lock", "bun.lockb")


def javascript_project(project: Path, root: Path) -> bool:
    """package.json and no pyproject.toml where the project is read (#681).
    A Python project one level down keeps today's --project hint (#221): that
    repository is a Python one checked from the wrong directory."""
    if not (project / "package.json").is_file() or (project / "pyproject.toml").is_file():
        return False
    return project != root or not projects_below(root)


def check_javascript_project(project: Path) -> None:
    """In place of check_project on a JavaScript or TypeScript repository:
    each Python item does not apply, said with its reason (#681)."""
    result("N/A", "pyproject.toml does not apply: it describes a Python project, and this one is described by package.json")
    result("N/A", "uv.lock does not apply: it is the lockfile of uv, Python's package manager; "
                  "this project's own lockfile is not checked")
    result("N/A", "the container image, .env.example and JSON logs items: does not apply: they belong to "
                  "plinth's Python archetypes, which check a Python image and Python source")
    bun = [n for n in BUN_LOCKFILES if (project / n).is_file()]
    if bun and not any((project / n).is_file() for n in NODE_LOCKFILES):
        result("INFO", f"{bun[0]} is the only lockfile here: GitHub's dependency review does not read it, "
                       "so a vulnerable dependency is not reported before a merge")


def check_project(project: Path, root: Path, archetype: str | None, host: str = "github") -> None:
    # Run at the root of a repository whose project is one directory down (a
    # monorepo, a backend/ folder, plinth's own canary/), this reported two
    # files missing that do exist, and nothing said that --project is the
    # answer (#221). With exactly one candidate below --root both lines name
    # it and the flag; with several they stay as they were and a list follows.
    # Which project is meant is the reader's to say: nothing is guessed,
    # nothing is re-run, and the list is an INFO so the counts do not move.
    present = (project / "pyproject.toml").is_file()
    # Only when this run is checking the root itself. A caller that named a
    # --project chose it; telling them to go and check a different one sends
    # them away from the project they meant to repair (#238 review). The
    # report #221 came from is a run at the root, which is this case.
    below = [] if present or project != root else projects_below(root)
    one = below[0] if len(below) == 1 else None
    # Written `--project=<value>`, and the value quoted: the line is pasted
    # into a shell, the directory name is the repository's to choose, and a
    # name that opens with `-` is one argparse reads as the next flag rather
    # than as this one's value.
    flag = f"--project={shlex.quote(one)}" if one else ""
    if one:
        result("FAIL", f"pyproject.toml missing here; found {one}/pyproject.toml: run again with {flag}")
    else:
        ok(present, "pyproject.toml present", "pyproject.toml missing")
        if below:
            result("INFO", "  pyproject.toml below the root in " + ", ".join(f"{d}/" for d in below)
                           + ": run again with --project=<one of them>")
    # Once a project has been found below the root, both items speak about it.
    # The root holds no pyproject.toml, so a uv.lock sitting there is not that
    # project's lockfile: reporting it as one passed an item for a file that
    # belongs to nothing this run checks, while sending the reader to a project
    # where `--project=` reports it missing straight away (#238 review).
    if one:
        if (root / one / "uv.lock").is_file():
            result("FAIL", f"uv.lock missing here; found {one}/uv.lock: run again with {flag}")
        else:
            result("FAIL", f"{one}/uv.lock missing: CI runs `uv sync --locked`")
    else:
        ok((project / "uv.lock").is_file(), "uv.lock committed",
           "uv.lock missing: CI runs `uv sync --locked`")

    if archetype is None:
        result("SKIP", "no archetype (no .copier-answers.yml, no --archetype); conditional items skipped")
        return
    answers = copier_answers(project) or {}
    if archetype not in CONDITIONAL_ARCHETYPES:
        result("INFO", f"archetype {archetype}: no container image, .env.example or JSON logs required")
        if archetype in PACKAGE_ARCHETYPES:
            # A repository-level file: GitHub reads workflows at the root, not
            # under --project, and the host is the one the run resolved,
            # --host before the answers (#720 review).
            check_release_workflow(root, host, archetype)
        return
    on_render = archetype == "web" and answers.get("hosting") != "elsewhere"
    result("INFO", f"archetype {archetype}: container image, .env.example and JSON logs required"
                   + (", and render.yaml" if on_render else ""))
    check_dockerfile(project)
    check_env_example(project)
    check_json_logs(project)
    if on_render:
        check_render_yaml(project)
    elif archetype == "web":
        check_hosted_elsewhere(answers.get("hosting_elsewhere"))
    if archetype in RELEASES:
        check_release_workflow(root, host, archetype)
    if archetype == "data-ml":
        check_model_card(project)


def check_model_card(project: Path) -> None:
    """The card a data-ml release publishes beside the model, with its
    personal-data question (plinth-template 1.31.0, #716). A WARN, never a
    FAIL: an instance rendered before the card existed passes as it did."""
    if (project / "MODEL_CARD.md").is_file():
        result("PASS", "MODEL_CARD.md present")
    else:
        result("WARN", "MODEL_CARD.md missing: a release publishes the model without saying what it was trained on")
        result("INFO", f"  plinth-template {RELEASES['data-ml'][1]} adds it with the training run: copier update")


def check_release_workflow(root: Path, host: str, archetype: str) -> None:
    """A `cli` or `library` publishes to PyPI on a version tag through the
    template's release.yml (plinth-template 1.29.0, #703), a `backend`
    its image to GHCR (#706), and a `data-ml` its model to a GitHub Release
    (#716). Read as text, standard library only: present, started by a tag
    and nothing else, and reading no stored secret; for `data-ml`, also no
    pickle among the files its `ASSETS` line uploads. Each
    finding is a WARN, never a FAIL: publishing is the person's choice, and
    an instance rendered before the file existed passes as it did."""
    what, since, instead = RELEASES[archetype]
    if host == "gitlab":
        result("INFO", f"{RELEASE_WORKFLOW} not required: on GitLab the template renders no release workflow")
        return
    p = root / RELEASE_WORKFLOW
    if not p.is_file():
        result("WARN", f"{RELEASE_WORKFLOW} missing: a version tag does not publish {what}")
        result("INFO", f"  plinth-template {since} adds it, with its steps in docs/how-to/publish-a-release.md: "
                       "copier update, then follow that page")
        return
    result("PASS", f"{RELEASE_WORKFLOW} present")
    # Comments dropped first: the file explains itself at length, and a
    # word in a comment is not a trigger or a secret.
    text = "\n".join(line.split(" #", 1)[0] for line in read(p).splitlines() if not line.lstrip().startswith("#"))
    m = re.search(r"^on:[ \t]*\n(.*?)(?=^\S|\Z)", text, re.MULTILINE | re.DOTALL)
    on = m.group(1) if m else ""
    # Every line of the block is read, or none is counted: `push:`, its
    # `tags:` and the tag patterns, nothing else. A quoted key, another event
    # or a filter beside `tags:` is not certified as tag-only (#720 review).
    lines = [line.rstrip() for line in on.splitlines() if line.strip()]
    tag_only = (len(lines) >= 2 and lines[0] == "  push:" and lines[1].startswith("    tags:")
                and all(line.startswith("      - ") for line in lines[2:]))
    if tag_only:
        result("PASS", f"{RELEASE_WORKFLOW} runs on a pushed tag only")
    else:
        unread = next((line.strip() for line in lines if not re.fullmatch(r"  push:|    tags:.*|      - .*", line)),
                      None) if lines else "no on: block this checker reads"
        seen = unread or "push: without tags:"
        result("WARN", f"{RELEASE_WORKFLOW} is not read as tag-only (first line not read: {seen}): "
                       "a branch push or a pull request could publish")
    # secrets.GITHUB_TOKEN is the run's own token, made for the run and not stored.
    stored = [x for x in re.findall(r"secrets\.\w+|^\s*password:", text, re.MULTILINE) if x != "secrets.GITHUB_TOKEN"]
    if stored:
        result("WARN", f"{RELEASE_WORKFLOW} reads a stored secret ({', '.join(sorted({s.strip() for s in stored}))}): "
                       f"{instead}, and a stored token can be copied and used from anywhere")
    else:
        result("PASS", f"{RELEASE_WORKFLOW} reads no stored secret")
    if archetype == "data-ml":
        # The template names what a release uploads once, in `env: ASSETS:`.
        found = list(re.finditer(r"^([ \t]*)ASSETS:[ \t]*(.*)$", text, re.MULTILINE))
        if not found:
            result("SKIP", f"{RELEASE_WORKFLOW}: no ASSETS line this checker reads; uploaded files not verified")
            return
        m = found[0]
        names = m.group(2).strip("'\" ").split()
        # Only one ASSETS line holding a list of plain file names is read. A
        # second ASSETS (one can override the other), a line indented deeper
        # under it (YAML continues the value there), `>-`, `|`, an expression
        # or a comment would hide names from this check.
        following = next((line for line in text[m.end():].splitlines() if line.strip()), "")
        continued = len(following) - len(following.lstrip()) > len(m.group(1))
        if (len(found) > 1 or continued or not names
                or not all(re.fullmatch(r"[\w./-]+", f) for f in names)):
            result("SKIP", f"{RELEASE_WORKFLOW}: ASSETS is not a one-line list of file names this checker reads "
                           f"(ASSETS: {m.group(2).strip()}); uploaded files not verified")
            return
        pickles = [f for f in names if f.lower().endswith(PICKLE_SUFFIXES)]
        if pickles:
            result("WARN", f"{RELEASE_WORKFLOW} uploads a pickle ({', '.join(pickles)}): loading one runs "
                           "whatever code it holds; save the model with skops, safetensors or ONNX")
        else:
            result("PASS", f"{RELEASE_WORKFLOW} uploads no pickle (ASSETS: {m.group(2).strip()})")


def check_render_yaml(project: Path) -> None:
    """The web archetype's Render Blueprint (plinth-template v1.20.0): the
    deploy that waits for the checks (#615). Asked of a `hosting: render`
    instance and of one with no hosting answer, rendered before the question
    existed (plinth-template#128)."""
    if not ok((project / "render.yaml").is_file(), "render.yaml present",
              "render.yaml missing: the web archetype deploys from it, after the checks pass"):
        result("INFO", "  restore it from the default branch: git restore --source=origin/main -- render.yaml")


# The places whose README section tells a person to set up HTTPS, backups and
# closed ports themselves (plinth-template#128); no item here reads them.
SELF_RUN_PLACES = ("vps", "home")


def check_hosted_elsewhere(place: str | None) -> None:
    """`hosting: elsewhere` (#678): the template renders no render.yaml, and
    no item reads the chosen place's own setup."""
    result("INFO", f"render.yaml not required: hosting is elsewhere ({place or 'no hosting_elsewhere answer'}), "
                   "and only Render reads that file")
    if place in SELF_RUN_PLACES:
        result("INFO", f"not checked by plinth: on {place}, HTTPS, backups and keeping the app's and the "
                       "database's ports closed are a person's to set up")


def check_dockerfile(project: Path) -> None:
    d = project / "Dockerfile"
    if not ok(d.is_file(), "Dockerfile present", "Dockerfile missing"):
        return
    text = read(d)
    froms = [re.sub(r"^--\S+\s+", "", f).split() for f in re.findall(r"^FROM\s+(.+)$", text, re.MULTILINE)]
    aliases = {parts[2] for parts in froms if len(parts) >= 3 and parts[1].upper() == "AS"}
    bases = [parts[0] for parts in froms if parts and parts[0] not in aliases and parts[0] != "scratch"]
    unpinned = [b for b in bases if "@sha256:" not in b]
    ok(bool(froms) and not unpinned, "every base image is pinned by digest",
       f"base images not pinned by digest: {unpinned or 'no FROM at all'}")
    users = re.findall(r"^USER\s+(\S+)", text, re.MULTILINE)
    ok(bool(users) and users[-1].split(":")[0] not in {"root", "0"}, "the image does not run as root",
       "the image runs as root (no USER, or the last USER is root)")
    ok("uv sync --locked" in text, "the image installs from the lockfile (uv sync --locked)",
       "the image does not use `uv sync --locked`: it can drift from the repository")
    pkg = package_name(project)
    cmd = re.search(r"^CMD\s+\[(.+)\]", text, re.MULTILINE)
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


# What a JSON log setup looks like in source: every pattern of one entry in one file.
JSON_LOG_HINTS = (
    ("a logging.Formatter subclass that calls json.dumps", (r"class\s+\w+\([\w.]*Formatter\)", r"json\.dumps")),
    ("structlog's JSONRenderer", (r"structlog", r"JSONRenderer")),
    ("python-json-logger", (r"pythonjsonlogger",)),
    ("loguru with serialize=True", (r"loguru", r"serialize\s*=\s*True")),
)


def check_json_logs(project: Path) -> None:
    """Does a service's source carry a known JSON log setup? Static and nothing
    more: the application is never run, so a PASS is a hint in a file, not proof
    of what the process prints. Logging the patterns do not know is a SKIP; only
    a source tree with no logging at all is a finding."""
    files = sorted((project / "src").rglob("*.py")) if (project / "src").is_dir() else []
    if not files:
        result("SKIP", "JSON logs not verified: no Python file under src/")
        return
    # Comments are dropped: `# TODO: add pythonjsonlogger` is not a setup. A string
    # is kept, because logging.config.dictConfig names its formatter in one.
    texts = {f.relative_to(project).as_posix(): re.sub(r"#.*", "", read(f)) for f in files}
    for rel, text in texts.items():
        for label, patterns in JSON_LOG_HINTS:
            if all(re.search(p, text) for p in patterns):
                result("PASS", f"JSON logs: static hint in {rel} ({label}); a hint in the source, not proof of what the process prints")
                return
    logging_in = [rel for rel, text in texts.items()
                  if re.search(r"^\s*(?:import|from)\s+[^#\n]*\b(?:logging|structlog|loguru)\b", text, re.MULTILINE)]
    if logging_in:
        result("SKIP", f"JSON logs not verified: {', '.join(logging_in)} set up logging in a way this checker does not recognise "
                       "(known: a logging.Formatter with json.dumps, structlog JSONRenderer, python-json-logger, loguru serialize=True)")
        return
    entry = f"src/{package_name(project) or '<package>'}/__main__.py"
    result("WARN", f"JSON logs: no logging found under src/ (entry point {entry}): a container's plain-text output is collected as unparsed lines")
    result("INFO", f"  in {entry}, give the root logger a StreamHandler(sys.stdout) whose logging.Formatter returns json.dumps(...) per record")


def check_image_job(root: Path) -> None:
    """The check the ruleset requires of a service archetype exists in the caller (#127)."""
    ci = root / ".github" / "workflows" / "ci.yml"
    text = read(ci) if ci.is_file() else ""
    m = re.search(r"^  image:\s*$", text, re.MULTILINE)
    # The job's own lines: up to the next two-space key. `buildx build` is a build too.
    block = re.split(r"^  \S", text[m.end():], maxsplit=1, flags=re.MULTILINE)[0] if m else ""
    ok(m is not None and re.search(r"docker (buildx )?build", block) is not None and "docker run" in block,
       "ci.yml carries the image job (docker build, docker run)",
       "ci.yml has no `image` job that builds and runs the container; the ruleset requires that check for this archetype")


def check_gitlab_image_job(root: Path) -> None:
    """A service archetype's .gitlab-ci.yml carries `docker-image`, the
    template's job that builds and runs the container (#127, #543)."""
    p = root / ".gitlab-ci.yml"
    text = read(p) if p.is_file() else ""
    m = re.search(rf"^{GITLAB_IMAGE_JOB}:\s*$", text, re.MULTILINE)
    block = re.split(r"^\S", text[m.end():], maxsplit=1, flags=re.MULTILINE)[0] if m else ""
    ok(m is not None and re.search(r"docker (buildx )?build", block) is not None and "docker run" in block,
       f".gitlab-ci.yml carries the {GITLAB_IMAGE_JOB} job (docker build, docker run)",
       f".gitlab-ci.yml has no `{GITLAB_IMAGE_JOB}` job that builds and runs the container; this archetype's floor has one")


def gitlab_job_block(tag: str) -> str | None:
    """The one `<<'<tag>'` heredoc of gitlab/python-ci.yml's floor-check job,
    dedented: PY is its include rule, REQ its PyYAML pinned by hash. None
    when the file or the block is not there."""
    try:
        text = GITLAB_PIPELINE.read_text(encoding="utf-8")
    except OSError:
        return None
    job = re.search(r"^floor-check:\n(.*?)(?=^\S|\Z)", text, re.MULTILINE | re.DOTALL)
    blocks = re.findall(rf"<<'{tag}'[^\n]*\n(.*?)\n[ \t]*{tag}\n", job.group(1), re.DOTALL) if job else []
    return textwrap.dedent(blocks[0]) if len(blocks) == 1 else None


def gitlab_rule_python(tmp: Path, network: bool) -> tuple[str | None, str]:
    """A Python that imports PyYAML: this one if it does, else a venv under
    tmp with the job's own PyYAML pinned by hash, binary wheels only, as the
    GitLab job installs it (#528). (None, why) when neither. Run from tmp,
    so the checkout is not on the module path."""
    probe = subprocess.run([sys.executable, "-c", "import yaml"], cwd=tmp, capture_output=True, check=False)
    if probe.returncode == 0:
        return sys.executable, ""
    if not network:
        return None, f"{sys.executable} has no PyYAML and --no-network leaves it uninstalled"
    if not (3, 11) <= sys.version_info[:2] <= (3, 14):
        return None, (f"{sys.executable} ({sys.version.split()[0]}) has no PyYAML, and the job's PyYAML is pinned "
                      "for CPython 3.11 to 3.14 only; run this checker with one of those")
    req = gitlab_job_block("REQ")
    if req is None:
        return None, f"{sys.executable} has no PyYAML and the job's pinned PyYAML could not be read"
    (tmp / "req.txt").write_text(req, encoding="utf-8")
    venv = tmp / "yaml"
    try:
        made = subprocess.run([sys.executable, "-m", "venv", str(venv)], capture_output=True, text=True, timeout=120, check=False)
        py = venv / "bin" / "python"
        got = made.returncode == 0 and subprocess.run(
            [str(py), "-m", "pip", "install", "--quiet", "--disable-pip-version-check", "--require-hashes",
             "--only-binary", ":all:", "--no-deps", "-r", str(tmp / "req.txt")],
            capture_output=True, text=True, timeout=300, check=False).returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        got = False
    if not got:
        return None, f"{sys.executable} has no PyYAML and the job's pinned PyYAML did not install"
    return str(py), ""


def check_gitlab_include(root: Path, network: bool, text: str | None = None, shown: str = ".gitlab-ci.yml") -> None:
    """.gitlab-ci.yml includes plinth's GitLab pipeline at a full commit SHA,
    with a checksum: the GitLab pipeline's floor-check rule, run here on the
    checkout (#543), or on `text`, the definition read from the default
    branch (#544), shown as `shown`. Its `pass:` is a PASS, `fail:` a FAIL,
    `not yet confirmed:` a SKIP. The rule runs from a temporary directory and
    reads the file by its absolute path, so a module in the checkout is never
    imported in place of PyYAML; the path is shown as `shown`."""
    what = f"{shown} includes plinth's GitLab pipeline at a full commit SHA"
    rule = gitlab_job_block("PY")
    if rule is None:
        result("SKIP", f"{what} not verified: the rule in {GITLAB_PIPELINE.name}'s floor-check job could not be read")
        return
    with tempfile.TemporaryDirectory() as tmp:
        py, why = gitlab_rule_python(Path(tmp), network)
        if py is None:
            result("SKIP", f"{what} not verified: {why}")
            return
        config = str(root / ".gitlab-ci.yml")
        if text is not None:
            config = str(Path(tmp) / "definition.yml")
            Path(config).write_text(text, encoding="utf-8")
        try:
            run = subprocess.run([py, "-c", rule], cwd=tmp, capture_output=True, text=True,
                                 env={**os.environ, "CONFIG": config}, timeout=60, check=False)
        except (OSError, subprocess.TimeoutExpired) as e:
            result("SKIP", f"{what} not verified: the rule did not run ({e.__class__.__name__})")
            return
    lines = [ln.replace(config, shown) for ln in run.stdout.splitlines() if ln.strip()]
    kinds = {"pass": "PASS", "fail": "FAIL", "not yet confirmed": "SKIP"}
    for ln in lines:
        kind, _, msg = ln.partition(": ")
        result(kinds.get(kind, "SKIP"), msg if kind in kinds else f"{what} not verified: the rule printed {ln[:200]!r}")
    if not lines:
        why = " ".join(run.stderr.split())[-200:] or f"exit {run.returncode}"
        result("SKIP", f"{what} not verified: the rule printed no verdict ({why})")


GITLAB_HOST = "gitlab.com"


def gl_api(path: str, network: bool, raw: bool = False, paginate: bool = False):
    """GET gitlab.com/api/v4/<path> through `glab api` with the user's own
    login (#544). JSON, or the text with raw; ABSENT on a 404; ERROR when
    offline, not logged in, or on any other failure. FLOOR_CHECK_GITLAB_API_DIR
    serves fixtures: <path>.json, or <path> as is with raw; a missing file is
    a 404 and `<path>.error` an error."""
    fixture_dir = os.environ.get("FLOOR_CHECK_GITLAB_API_DIR")
    if fixture_dir:
        f = Path(fixture_dir) / (path if raw else path + ".json")
        if (Path(fixture_dir) / (path + ".error")).is_file():
            return ERROR
        if not f.is_file():
            return ABSENT
        return read(f) if raw else json.loads(read(f))
    if not network or not shutil.which("glab"):
        return ERROR
    cmd = ["glab", "api", "--hostname", GITLAB_HOST, path] + (["--paginate"] if paginate else [])
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return ERROR
    if r.returncode != 0:
        # glab prints GitLab's error body on stdout: {"message":"404 Not found"} (measured, #533).
        return ABSENT if re.search(r'"message"\s*:\s*"404\b', r.stdout) or "HTTP 404" in r.stderr else ERROR
    if raw:
        return r.stdout
    try:
        return json.loads(r.stdout)
    except ValueError:
        return ERROR


def check_gitlab_wall(root: Path, repo: str, network: bool) -> None:
    """The wall /plinth:new-project --host gitlab raises (#533), read live
    through glab (#544): the default branch protected (no one pushes,
    Maintainers merge, no force push), "Pipelines must succeed" with skipped
    pipelines not counted, squash always and fast-forward, the labels, and
    the include read from the default branch -- the read from outside a merge
    request that the GitLab pipeline's own floor-check job cannot make.
    A setting that differs is a FAIL, the labels a WARN as on GitHub; a read
    that fails is a SKIP, never a PASS."""
    enc = urllib.parse.quote(repo, safe="")
    edit = f"https://{GITLAB_HOST}/{repo}/-/settings/repository"
    login = f"glab auth login --hostname {GITLAB_HOST}"
    project = gl_api(f"projects/{enc}", network)
    if not isinstance(project, dict):
        why = ("it was not found, or this login cannot see it" if project is ABSENT
               else f"offline, glab missing or not logged in ({login}), or an API error")
        result("SKIP", f"the GitLab wall of {repo} not verified: {why}")
        check_gitlab_include(root, network)
        return
    branch = project.get("default_branch")
    if not isinstance(branch, str) or not branch:
        result("SKIP", f"{repo} has no default branch GitLab names; its protection, merge checks and include not verified")
        return

    # Every rule whose name or wildcard pattern matches the branch applies, and
    # GitLab takes the most permissive of them (#548 review): a `*` rule that
    # lets Developers push opens `main` whatever its own rule says. On Premium
    # the list carries the parent group's rules too (`inherited: true`), and
    # they count the same way.
    rules = gl_api(f"projects/{enc}/protected_branches?per_page=100", network, paginate=True)
    if not isinstance(rules, list):
        result("SKIP", f"the protection of {branch} not verified: protected branches are not readable with this login "
                       "(it needs the Maintainer role on GitLab.com), or an API error")
    else:
        def matches(pattern: object) -> bool:
            return isinstance(pattern, str) and re.fullmatch(".*".join(map(re.escape, pattern.split("*"))), branch) is not None
        applying = [r for r in rules if isinstance(r, dict) and matches(r.get("name"))]

        def levels(key: str) -> list:
            return [a for r in applying if isinstance(r.get(key), list) for a in r[key] if isinstance(a, dict)]

        def named(xs: list) -> list:
            return [a for a in xs if a.get("user_id") or a.get("group_id") or a.get("deploy_key_id")]

        def described(xs: list) -> list:
            return [a.get("access_level_description") or a.get("access_level") for a in xs]
        push, merge = levels("push_access_levels"), levels("merge_access_levels")
        names = ", ".join(str(r.get("name")) for r in applying)
        bad = []
        if not applying:
            result("FAIL", f"{branch} is not a protected branch on {repo}: anyone with Developer can push to it")
            result("INFO", f"  glab api --hostname {GITLAB_HOST} -X POST projects/{enc}/protected_branches -f name={branch} "
                           "-F push_access_level=0 -F merge_access_level=40 -F allow_force_push=false   (a Maintainer)")
        else:
            if not push or any(a.get("access_level") != 0 for a in push) or named(push):
                bad.append(f"push allowed ({described(push)}), want No one")
            if not merge or any(not isinstance(a.get("access_level"), int) or a.get("access_level") < 40 for a in merge) or named(merge):
                bad.append(f"merge allowed to {described(merge)}, want Maintainers")
            force = [r.get("allow_force_push") for r in applying if r.get("allow_force_push") is not False]
            if force:
                bad.append(f"force push {force[0]!r}, want false")
            if bad:
                result("FAIL", f"{branch}'s protection on {repo} is weaker than the door's (rules that apply: {names}): {'; '.join(bad)}")
                result("INFO", f"  {edit}#js-protected-branches-settings   (each rule that matches {branch}: Allowed to push "
                               "and merge: No one; Allowed to merge: Maintainers; Allowed to force push: off)")
            else:
                result("PASS", f"{branch} is protected on {repo}: no one pushes, Maintainers merge, no force push "
                               f"(rules that apply: {names})")

    # Each group is judged on the fields GitLab returned (#548 review, round 2):
    # a readable mismatch is a FAIL even when another field is missing, and
    # only the missing fields are a SKIP.
    merge_url = f"https://{GITLAB_HOST}/{repo}/-/settings/merge_requests"
    groups = (
        ({"only_allow_merge_if_pipeline_succeeds": True, "allow_merge_on_skipped_pipeline": False},
         f"the merge checks of {repo} let a merge request merge without a green pipeline",
         f"{repo} merges only on a green pipeline (\"Pipelines must succeed\" on, skipped pipelines not counted)",
         (f"glab api --hostname {GITLAB_HOST} -X PUT projects/{enc} -F only_allow_merge_if_pipeline_succeeds=true "
          "-F allow_merge_on_skipped_pipeline=false"), ""),
        ({"squash_option": "always", "merge_method": "ff"},
         f"{repo} merges other than squash and fast-forward",
         f"{repo} squashes every merge request and fast-forwards",
         f"glab api --hostname {GITLAB_HOST} -X PUT projects/{enc} -f squash_option=always -f merge_method=ff",
         "; main gains commits that are not one squash per merge request"),
    )
    for want, bad_msg, good_msg, fix, why in groups:
        off = {k: project[k] for k, v in want.items() if k in project and project[k] != v}
        absent = [k for k in want if k not in project]
        if off:
            result("FAIL", f"{bad_msg}: " + ", ".join(f"{k}={v!r}" for k, v in off.items()) + why)
            result("INFO", f"  {fix}   (a Maintainer; or {merge_url})")
        if absent:
            result("SKIP", f"{', '.join(absent)} of {repo} not verified: GitLab did not return "
                           f"{'it' if len(absent) == 1 else 'them'} to this login (a project member reads them)")
        if not off and not absent:
            result("PASS", good_msg)

    # The definition GitLab runs: ci_config_path, .gitlab-ci.yml when empty.
    # One in another project or at a URL (`path@group/project`, http) is not read.
    cfg = project.get("ci_config_path") or ".gitlab-ci.yml"
    shown = f"{cfg} on {branch}"
    if "@" in cfg or "://" in cfg:
        result("SKIP", f"the include on {branch} not verified: the pipeline definition is {cfg}, outside this project")
    else:
        text = gl_api(f"projects/{enc}/repository/files/{urllib.parse.quote(cfg, safe='')}/raw?ref="
                      f"{urllib.parse.quote(branch, safe='')}", network, raw=True)
        if text is ABSENT:
            result("FAIL", f"no {cfg} on {branch} of {repo}: no pipeline runs, so \"Pipelines must succeed\" holds nothing back")
        elif not isinstance(text, str):
            result("SKIP", f"the include on {branch} not verified: {cfg} could not be read (an API error)")
        else:
            check_gitlab_include(root, network, text, shown)

    labels = gl_api(f"projects/{enc}/labels?per_page=100", network, paginate=True)
    f = labels_file()
    if f is None:
        result("SKIP", "labels.txt not found next to the checker; labels not checked")
    elif not isinstance(labels, list):
        result("SKIP", "labels not verified (offline, not logged in, or API error)")
    else:
        rows = [ln.split("|") for ln in read(f).splitlines() if ln.strip() and not ln.lstrip().startswith("#")]
        have = {e.get("name") for e in labels if isinstance(e, dict)}
        missing = [r for r in rows if r[0] not in have]
        if not missing:
            result("PASS", f"every label the door creates is present ({len(rows)})")
        else:
            result("WARN", f"labels the door creates that are missing: {', '.join(r[0] for r in missing)}")
            for r in missing:
                result("INFO", f"  glab label create --name {shlex.quote(r[0])} --color '#{r[1]}' --repo {repo}")


def ruleset_for(data: dict, archetype: str | None, code_scanning: bool = True) -> dict:
    """ruleset.json as the door applies it: with the image check for a service
    archetype, the two web checks for the web archetype (#614), and without the
    code_scanning rule for a private repository
    that has no GitHub Code Security (#350); every check name stays."""
    data = copy.deepcopy(data)
    if not code_scanning:
        data["rules"] = [r for r in data["rules"] if r["type"] != "code_scanning"]
    if archetype in CONDITIONAL_ARCHETYPES:
        for r in data["rules"]:
            if r["type"] == "required_status_checks":
                checks = r["parameters"]["required_status_checks"]
                checks.append({"context": IMAGE_CHECK, "integration_id": checks[0]["integration_id"]})
    if archetype == "web":
        for r in data["rules"]:
            if r["type"] == "required_status_checks":
                checks = r["parameters"]["required_status_checks"]
                checks += [{"context": c, "integration_id": checks[0]["integration_id"]} for c in WEB_CHECKS]
    return data


def check_env_example(project: Path) -> None:
    e = project / ".env.example"
    if not ok(e.is_file(), ".env.example present", ".env.example missing"):
        return
    pattern = re.compile(r"""os\.(?:environ\s*\[\s*|environ\.get\s*\(\s*|getenv\s*\(\s*)['"]([A-Z_][A-Z0-9_]*)['"]""")
    used = {m for f in (project / "src").rglob("*.py") for m in pattern.findall(read(f))} if (project / "src").is_dir() else set()
    documented = set(re.findall(r"^\s*#?\s*([A-Z_][A-Z0-9_]*)\s*=", read(e), re.MULTILINE))
    missing = sorted(used - documented)
    ok(not missing, ".env.example documents every variable the code reads",
       f".env.example is missing variables the code reads: {missing}")


# ── the wall ──────────────────────────────────────────────────────────────


def labels_file() -> Path | None:
    """`labels.txt`, the list the door creates from. Beside this file in CI,
    where python-ci.yml downloads both from the same plinth commit; one level up
    in a checkout, where it sits at the repository root."""
    here = Path(__file__).resolve().parent
    for c in (here / "labels.txt", here.parent / "labels.txt"):
        if c.is_file():
            return c
    return None


def check_labels(repo: str, network: bool) -> None:
    """Which labels the door creates does this repository not have?

    Names only: a colour or description that drifted is not worth a line, and
    the door's `--force` fixes it on the next run anyway. Never a FAIL --
    `ci / floor-check` passes `--repo` in every consumer's CI, so a FAIL here
    would block merges over a label, and a label is a convenience, not a wall
    stone (#78)."""
    f = labels_file()
    if f is None:
        result("SKIP", "labels.txt not found next to the checker; labels not checked")
        return
    want = [ln.split("|")[0] for ln in read(f).splitlines()
            if ln.strip() and not ln.lstrip().startswith("#")]
    colour = {ln.split("|")[0]: ln.split("|")[1] for ln in read(f).splitlines()
              if ln.strip() and not ln.lstrip().startswith("#")}
    data = api(f"repos/{repo}/labels?per_page=100", network, paginate=True)
    if data is ERROR or not isinstance(data, list):
        # Unreadable is not empty. Reporting every label missing because the API
        # failed is the fail-open case in reverse, and just as useless.
        result("SKIP", "labels not verified (offline, not logged in, or API error)")
        return
    have = {e.get("name") for e in data if isinstance(e, dict)}
    missing = [n for n in want if n not in have]
    if not missing:
        result("PASS", f"every label the door creates is present ({len(want)})")
        return
    result("WARN", f"labels the door creates that are missing: {', '.join(missing)}")
    for n in missing:
        result("INFO", f"  gh label create {n} --repo {repo} --color {colour[n]}")


# The values GitHub documents for a code_scanning rule's thresholds, weakest
# first: `none` blocks nothing, `all` blocks on every alert. A live value at
# or above the expected one holds the wall.
THRESHOLDS = {
    "alerts_threshold": ["none", "errors", "errors_and_warnings", "all"],
    "security_alerts_threshold": ["none", "critical", "high_or_higher", "medium_or_higher", "all"],
}


def codeql_policy(data: dict) -> dict[str, str] | None:
    """The thresholds ruleset.json gives CodeQL, or None when it has no such rule."""
    for r in data["rules"]:
        for t in r.get("parameters", {}).get("code_scanning_tools", []) if r["type"] == "code_scanning" else []:
            if t.get("tool") == "CodeQL":
                return {k: t[k] for k in THRESHOLDS if k in t}
    return None


def check_codeql_policy(repo: str, branch: str, tools: list[dict], policy: dict[str, str] | None) -> None:
    """The live CodeQL rules' thresholds against the policy (#96). `none` on
    both is a rule that blocks nothing, and it read as "enforced (rule)".
    GitHub applies every rule that targets the branch, so with several the
    strictest live value is what governs; weaker is a FAIL, a value that
    cannot be read (or is not one GitHub documents) is not verified."""
    if policy is None:
        result("SKIP", f"{branch}: CodeQL alert thresholds not compared (no --ruleset)")
        return
    weak, unread, live = [], [], {}
    for field, order in THRESHOLDS.items():
        ranks = [order.index(t[field]) for t in tools if t.get(field) in order]
        want = policy.get(field)
        if not ranks or want not in order:
            unread.append(field)
            continue
        live[field] = order[max(ranks)]
        if max(ranks) < order.index(want):
            weak.append(f"{field}={live[field]} (expected {want})")
    if weak:
        result("FAIL", f"{branch}: CodeQL alert thresholds weakened: {', '.join(weak)}")
        for rid in sorted({t["ruleset_id"] for t in tools if t.get("ruleset_id")}):
            result("INFO", f"  the rule is edited in https://github.com/{repo}/settings/rules/{rid}")
    if unread:
        result("SKIP", f"{branch}: CodeQL alert thresholds not verified: {', '.join(unread)} unreadable")
    if not weak and not unread:
        result("PASS", f"{branch}: CodeQL alert thresholds {live['alerts_threshold']} / {live['security_alerts_threshold']} "
                       f"(expected {policy['alerts_threshold']} / {policy['security_alerts_threshold']})")


# A private repository's wall is read against what its licences allow (#351,
# decided in #320): the code_scanning rule needs GitHub Code Security and push
# protection needs GitHub Secret Protection, both paid products that Team and
# Enterprise can buy and GitHub Pro cannot. Only `"private": true` in the
# repository's own answer counts: anything else is read as a public
# repository, where both are free and both are expected.
TURN_ON = ("On Team or Enterprise it can be turned on in the repository's Settings > Advanced Security, "
           "and may be billed")


def is_private(meta: dict) -> bool:
    return meta.get("private") is True


def product_status(meta: dict, *keys: str) -> str | None:
    """`enabled` or `disabled` as `security_and_analysis` answers for the
    product under any of `keys`, enabled first; None when it answers neither.
    None is not `disabled`: a token without repository administration gets no
    block at all, and a public repository's block has no code_security entry,
    so a missing answer says nothing about the product. What a private
    repository answers on each plan is not measured yet (#352)."""
    security = meta.get("security_and_analysis")
    entries = [security.get(k) for k in keys] if isinstance(security, dict) else []
    statuses = [e.get("status") for e in entries if isinstance(e, dict)]
    return next((s for s in ("enabled", "disabled") if s in statuses), None)


def check_push_protection(repo: str, meta: dict, actions_token: bool = False) -> None:
    """Is push protection on (#303)? `ci / secrets` reports a secret after the
    push, when it is already on GitHub; push protection refuses the push, for
    the secret formats GitHub knows. The door turns it on.

    Read from `security_and_analysis` in the repository itself, which a token
    without repository administration does not get: that is a SKIP, and so is
    an object with no readable status for it. Off is a WARN, never a FAIL:
    `ci / floor-check` is a required check in every consumer's CI, and a
    repository that passed before this item existed still passes.

    `ci / floor-check` runs on the Actions token, which never administers the
    repository, so there the unread settings would be a SKIP no consumer can
    clear, in every run. With --actions-token that one answer is an INFO
    naming who does read it; what the token does read is judged as ever.

    On a private repository it is expected only where GitHub Secret Protection
    is enabled (#351), read from the secret scanning status. Disabled there
    is an INFO naming the gap and `ci / secrets` in its place, with no call:
    turning it on is a purchase. Off with no secret scanning status is not
    verified."""
    security = meta.get("security_and_analysis")
    if security is None and actions_token:
        result("INFO", "push protection is not read here: the Actions token does not get the repository's security "
                       "settings; /plinth:floor-check reads it with a person's login", deferred=True)
        return
    if security is None:
        result("SKIP", "push protection not verified (this token does not read the repository's security settings; "
                       "one with repository administration does)")
        return
    entry = security.get("secret_scanning_push_protection") if isinstance(security, dict) else None
    status = entry.get("status") if isinstance(entry, dict) else None
    protection = product_status(meta, "secret_scanning") if is_private(meta) else "enabled"
    if status == "enabled":
        result("PASS", "push protection is on: GitHub refuses a push that carries a secret in a format it knows")
    elif protection == "disabled":
        result("INFO", "push protection is not expected here: GitHub Secret Protection is not enabled on this private "
                       "repository (a paid product for Team and Enterprise), so a push that carries a secret is not "
                       "refused. In its place: `ci / secrets`, which finds a secret after the push, when it has to "
                       f"be revoked. {TURN_ON}")
    elif status == "disabled" and protection is None:
        result("SKIP", "push protection not verified (it is off, and GitHub reports no secret scanning status for this "
                       "private repository: whether GitHub Secret Protection is enabled there was not read)")
    elif status == "disabled":
        result("WARN", "push protection is off: a push that carries a secret reaches GitHub, "
                       "and `ci / secrets` reports it only afterwards")
        # The body the door sends, both fields: push protection is a part of
        # secret scanning. As JSON on stdin, the form set-security-setting.sh
        # writes and reads back, so it does not depend on how a gh version
        # reads `-f a[b][c]=v`.
        body = json.dumps({"security_and_analysis": {k: {"status": "enabled"}
                                                     for k in ("secret_scanning", "secret_scanning_push_protection")}})
        result("INFO", f"  gh api -X PATCH repos/{repo} --input - <<<'{body}'"
                       "   (needs repository administration; on a private repository, GitHub Secret Protection too)")
    else:
        result("SKIP", "push protection not verified (GitHub reports no push protection status for this repository)")


def check_private_reporting(repo: str, meta: dict, network: bool, actions_token: bool = False) -> None:
    """Is private vulnerability reporting on (#747)? SECURITY.md sends a
    reporter to Security → Report a vulnerability, and the form is off until
    someone turns it on. The door does, on a public repository.

    A private repository is not offered it: on a private repository of a
    personal account on GitHub Free, GET and PUT of the setting both answered
    404 on 2026-10-31, where a public repository of the same account answered
    `{"enabled": true}` with the same token (GitHub Docs: "Owners and
    administrators of public repositories"). Other plans are not measured.
    There SECURITY.md names the route that works, so it is an INFO.
    Off is a WARN with the call; an answer that is not read is a SKIP, or
    with --actions-token an INFO left to the skill (the Actions token is not
    known to read it, which is not measured either)."""
    if is_private(meta):
        result("INFO", "private vulnerability reporting is not offered on a private repository: its SECURITY.md "
                       "names an issue instead where it was rendered with the answer visibility=private")
        return
    got = api(f"repos/{repo}/private-vulnerability-reporting", network)
    enabled = got.get("enabled") if isinstance(got, dict) else None
    if enabled is True:
        result("PASS", "private vulnerability reporting is on: SECURITY.md's Security → Report a vulnerability works")
    elif enabled is False:
        result("WARN", "private vulnerability reporting is off: SECURITY.md sends a reporter to "
                       "Security → Report a vulnerability, which this repository does not show")
        result("INFO", f"  gh api -X PUT repos/{repo}/private-vulnerability-reporting   (needs repository administration)")
    elif actions_token:
        result("INFO", "private vulnerability reporting is not read here: /plinth:floor-check reads it "
                       "with a login that administers the repository", deferred=True)
    else:
        result("SKIP", "private vulnerability reporting not verified (GitHub gave no answer this checker reads; "
                       "a login with repository administration reads it)")


# Owners whose actions `github_owned_allowed` lets run (GitHub Docs, "Managing
# GitHub Actions settings for a repository": actions/* and github/*).
GITHUB_OWNED = {"actions", "github"}


def allowlist_allows(value: str, patterns: list[str]) -> bool:
    """Whether one of `patterns_allowed` matches `owner/repo[/path]@ref`.
    GitHub documents `*` as the wildcard (`monalisa/octocat@*`,
    `monalisa/*`); matched here as a shell pattern, case-insensitively, the
    way owner and repository names are. `coolbress/plinth/*` (the door's, for
    a reusable workflow at a path) and `<owner>/<repo>@*` (the door's release
    actions) are the two shapes measured to start a run."""
    v = value.lower()
    return any(isinstance(p, str) and fnmatch.fnmatchcase(v, p.lower()) for p in patterns)


def check_actions_allowlist(root: Path, repo: str, network: bool, actions_token: bool = False) -> None:
    """Would every action the workflows use start (#747)? The door lets only
    GitHub-owned actions and the patterns it names run. A `uses:` outside
    them ends its run in startup_failure: no job, no check name, and no
    message saying why (the door's first release on a tag did, before #747).
    `copier update` changes files, not this setting, so a repository made
    before a template began to use an action learns of it here.

    Read: actions/permissions and its selected-actions, which need repository
    administration; a token without it is a SKIP, or with --actions-token an
    INFO left to the skill. The workflows are the local checkout's, as for
    the pins. A local `./` action is the repository's own and allowed; a
    `docker://` image is not judged (SKIP), since what the policy does with
    one is not measured. WARN, never FAIL, as push protection."""
    if not network and not os.environ.get("FLOOR_CHECK_API_DIR"):
        return  # the wall's own SKIP says offline
    uses: list[tuple[str, int, str]] = []
    for p in workflow_files(root):
        rel = p.relative_to(root).as_posix()
        uses += [(rel, n, v) for n, v, readable in iter_uses(read(p)) if readable and not v.startswith("./")]
    if not uses:
        return
    perms = api(f"repos/{repo}/actions/permissions", network)
    allowed = perms.get("allowed_actions") if isinstance(perms, dict) else None
    selected = api(f"repos/{repo}/actions/permissions/selected-actions", network) if allowed == "selected" else None
    if allowed not in ("all", "local_only", "selected") or (allowed == "selected" and not isinstance(selected, dict)):
        if actions_token:
            result("INFO", "the Actions allowlist is not read here: /plinth:floor-check reads it with a login "
                           "that administers the repository", deferred=True)
        else:
            result("SKIP", "the Actions allowlist not verified (this token does not read the repository's Actions "
                           "permissions; one with repository administration does)")
        return
    if perms.get("enabled") is False:
        result("WARN", "GitHub Actions is turned off on this repository: no workflow runs")
        return
    docker = [(f, n, v) for f, n, v in uses if v.startswith("docker://")]
    uses = [(f, n, v) for f, n, v in uses if not v.startswith("docker://")]
    patterns: list[str] = []
    if allowed == "all":
        refused = []
    elif allowed == "local_only":
        refused = uses
    else:
        assert isinstance(selected, dict)
        listed = selected.get("patterns_allowed")
        patterns = [p for p in listed if isinstance(p, str)] if isinstance(listed, list) else []
        owned = selected.get("github_owned_allowed") is True
        refused = [(f, n, v) for f, n, v in uses
                   if not (owned and v.split("/", 1)[0].lower() in GITHUB_OWNED) and not allowlist_allows(v, patterns)]
    for f, n, v in docker:
        result("SKIP", f"{f}: line {n} {v}: whether the Actions allowlist lets an image run is not judged here")
    if not refused:
        if uses:
            result("PASS", f"the Actions allowlist lets every action the workflows use start ({len(uses)} uses)")
        return
    result("WARN", "the Actions allowlist refuses: " + ", ".join(f"{f} line {n} {v.split('@', 1)[0]}" for f, n, v in refused)
           + ". A run that uses one ends in startup_failure, with no job and no message saying why")
    if allowed != "selected":
        result("INFO", f"  gh api -X PUT repos/{repo}/actions/permissions -F enabled=true -f allowed_actions=selected"
                       "   (needs repository administration; then run this again for the allowlist)")
        return
    assert isinstance(selected, dict)
    add = sorted({v.split("@", 1)[0] + "@*" for _, _, v in refused})
    body = json.dumps({"github_owned_allowed": selected.get("github_owned_allowed") is True,
                       "verified_allowed": selected.get("verified_allowed") is True,
                       "patterns_allowed": [*patterns, *add]})
    result("INFO", f"  gh api -X PUT repos/{repo}/actions/permissions/selected-actions --input - <<<{shlex.quote(body)}"
                   "   (needs repository administration)")


def check_wall(repo: str, expected: list[str], merge_methods: set[str], policy: dict[str, str] | None, network: bool,
               sources: dict[str, int | None] | None = None, actions_token: bool = False,
               merge: dict | None = None, not_applying: list[str] | None = None) -> None:
    """not_applying: on a JavaScript or TypeScript repository (#681), the
    expected checks only python-ci.yml runs, already left out of `expected`.
    When nothing is left, the required-checks rule is not asked for either,
    and CodeQL's default setup is asked to analyse that language, not Python."""
    if not network and not os.environ.get("FLOOR_CHECK_API_DIR"):
        result("SKIP", "wall not checked (offline)")
        return
    meta = api(f"repos/{repo}", network)
    if meta in (ABSENT, ERROR) or not isinstance(meta, dict):
        if meta is ABSENT:
            result("FAIL", f"repos/{repo} not found (404)")
        else:
            result("SKIP", f"could not read repos/{repo} (API error)")
        return
    branch = meta.get("default_branch")
    # The ruleset the door applies targets ~DEFAULT_BRANCH, so every rule below
    # governs whatever this says -- and the rules of a branch nobody works on
    # protect nobody. A repository the door damaged before #105 has the probe
    # branch here, a complete wall on it, and no rules on main at all, and
    # reading only the default branch reported that as a wall standing (#106).
    #
    # Said once and plainly, not only as the prefix on each rule line: a check
    # that passes should not depend on someone noticing a prefix.
    if branch is None:
        result("SKIP", "default branch not verified (the API did not report one); reading the wall on main")
        branch = "main"
    else:
        result("INFO", f"the wall is checked on {branch}, the repository's default branch")
    # WARN, never FAIL. `ci / floor-check` runs with --repo in every consumer's
    # CI, so a FAIL here blocks their merges -- and a repository whose default
    # is deliberately `master` or `trunk` is not broken, it just is not what the
    # door builds. Naming it is the whole job; deciding for them is not (#106,
    # the same reasoning that keeps a missing label a WARN in #84).
    if branch is not None and branch != "main":
        result("WARN", f"the default branch is {branch}, not main: the rules below govern {branch}. "
                       f"If main is where the work happens, main is unprotected")
        result("INFO", f"  gh api repos/{repo} -X PATCH -f default_branch=main   (then run this again)")
    # The squash commit is the pull request (title and description), not a
    # list of the branch's commits. The door sets it; a button merge in the
    # web UI uses it. The fields are visible to a token with push access.
    title, msg = meta.get("squash_merge_commit_title"), meta.get("squash_merge_commit_message")
    # The Actions token in `ci / floor-check` never sees them (#440): an INFO
    # left to the skill there, as push protection below, not a SKIP no
    # consumer can clear.
    if title is None and msg is None and actions_token:
        result("INFO", "squash commit settings not visible with this token; /plinth:floor-check reads them with a login that administers the repository", deferred=True)
    elif title is None and msg is None:
        result("SKIP", "squash commit settings not visible with this token (a push-access token sees them)")
    else:
        ok(title == "PR_TITLE" and msg == "PR_BODY",
           "squash commits carry the pull request title and description",
           f"squash commit settings drifted: title={title}, message={msg} (expected PR_TITLE, PR_BODY)")
    check_push_protection(repo, meta, actions_token)
    check_private_reporting(repo, meta, network, actions_token)
    rules = api(f"repos/{repo}/rules/branches/{branch}", network)
    # The merge line is printed on these two paths as well (#583): the skill's
    # summary relays it, and the role alone decides much of it.
    if rules is ERROR:
        result("SKIP", f"could not read the rules of {branch} (API error)")
        if merge is not None:
            check_merge_setup(branch, meta, "unread", actions_token)
        return
    if rules is ABSENT or not rules:
        result("FAIL", f"no rules govern {branch}: the wall is down")
        if merge is not None:
            check_merge_setup(branch, meta, "no rules", actions_token)
        return
    by_type = {r["type"]: r for r in rules}
    checks = not not_applying or bool(expected)
    for t in ("deletion", "non_fast_forward", "pull_request") + (("required_status_checks",) if checks else ()):
        ok(t in by_type, f"{branch}: {t} rule active", f"{branch}: {t} rule missing")

    pr = by_type.get("pull_request", {}).get("parameters", {})
    methods = set(pr.get("allowed_merge_methods", []))
    ok(bool(methods) and methods <= merge_methods,
       f"{branch}: merge methods within {sorted(merge_methods)}",
       f"{branch}: merge methods widened to {sorted(methods) or 'unknown'}")

    # Strict when any active required-checks rule is strict: GitHub enforces
    # each rule, so one strict rule already requires a current branch.
    strict = any(r.get("parameters", {}).get("strict_required_status_checks_policy") is True
                 for r in rules if r.get("type") == "required_status_checks")
    if not_applying:
        result("N/A", f"{branch}: requiring {', '.join(not_applying)} does not apply: python-ci.yml runs those "
                      "checks, and a JavaScript or TypeScript repository does not call it")
    if checks:
        ok(strict,
           f"{branch}: required checks are strict (branch must be current)",
           f"{branch}: required checks are not strict")
    # Every active required-checks rule counts: GitHub enforces each of them,
    # so a check is required when any rule requires it, and pinned when any
    # rule pins it. Keeping only the last rule of the type gave a false
    # "dropped" or "any source" when a second ruleset carried part of it.
    live: dict[str, set[int | None]] = {}
    for r in rules:
        if r.get("type") == "required_status_checks":
            for c in r.get("parameters", {}).get("required_status_checks", []):
                live.setdefault(c["context"], set()).add(c.get("integration_id"))
    have = set(live)
    missing = [c for c in expected if c not in live]
    if not checks:
        pass
    elif not ok(not missing, f"{branch}: all {len(expected)} expected checks are required",
              f"{branch}: required checks dropped: {missing}") and sources is not None \
            and all(sources.get(c) is not None for c in missing):
        # The script only adds checks, and asks for repository administration.
        result("INFO", "  require them again (repository administration): scripts/with-admin-token.sh "
                       f"scripts/upgrade-ruleset.sh {repo} " + " ".join(shlex.quote(f"{c}:{sources[c]}") for c in missing))
    # Which app may report each check is part of the wall. Without the pin, a
    # commit status of the same name, which anyone with write access can post,
    # satisfies the requirement.
    # Each check is compared with its own expected app, so a ruleset that pins
    # checks to different apps is still compared check by check.
    if not checks:
        pass
    elif sources is None:
        result("INFO", f"{branch}: the source of each required check is not compared (no --ruleset)")
    else:
        bad = unknown = 0
        for c in expected:
            if c not in live:
                unknown += 1   # reported above as dropped; the PASS cannot speak for it
                continue
            want = sources.get(c)
            if want is None:
                result("SKIP", f"{branch}: the expected app for required check {c} is not known "
                               "(not pinned in --ruleset); its source is not compared")
                unknown += 1
                continue
            if want in live[c]:
                continue
            bad += 1
            if None in live[c]:
                result("FAIL", f"{branch}: required check {c} accepts a status from any source "
                               f"(expected app {want}); anyone with write access can satisfy it")
            else:
                got = ", ".join(str(i) for i in sorted(i for i in live[c] if i is not None))
                result("FAIL", f"{branch}: required check {c} comes from app {got}, not {want}")
        apps = sorted({v for v in sources.values() if v is not None})
        # A PASS speaks for every expected check; with one uncompared it would not.
        if not bad and not unknown and apps:
            label = "app" if len(apps) == 1 else "apps"
            result("PASS", f"{branch}: required checks come from the expected {label} ({', '.join(map(str, apps))})")

    # CodeQL is part of the floor whatever the ruleset names: the door requires
    # it through a code_scanning rule (blocks with a reason, and on the alerts
    # themselves); repositories created before #41 require the
    # `CodeQL` check name instead. Either holds the wall; neither does not.
    # Every rule of the branch is read, not one per type: a second ruleset
    # can carry a second CodeQL rule.
    tools = [dict(t, ruleset_id=r.get("ruleset_id")) for r in rules if r.get("type") == "code_scanning"
             for t in r.get("parameters", {}).get("code_scanning_tools", []) if t.get("tool") == "CodeQL"]
    by_name = "CodeQL" in have
    # On a private repository the rule is expected only where GitHub Code
    # Security is enabled (#351); the earlier Advanced Security licence
    # includes code scanning and counts beside it. A rule that is there is
    # read as ever. One that is missing is a FAIL with the licence, a named
    # gap without it, and not verified where GitHub did not answer. The
    # Actions token in `ci / floor-check` never gets that answer, so with
    # --actions-token the unread settings are an INFO naming the run that
    # judges it, as for push protection: a SKIP there is one no consumer can
    # clear, and with or without the licence that run cannot fail the item.
    scanning = product_status(meta, "code_security", "advanced_security") if is_private(meta) else "enabled"
    if tools or by_name or scanning == "enabled":
        ok(bool(tools) or by_name,
           f"{branch}: CodeQL enforced ({'rule' if tools else 'check name'})",
           f"{branch}: CodeQL not enforced: no code_scanning rule for CodeQL and no CodeQL check name")
    elif scanning == "disabled":
        result("INFO", f"{branch}: CodeQL is not expected here: GitHub Code Security is not enabled on this private "
                       "repository (a paid product for Team and Enterprise), so no code_scanning rule for CodeQL and "
                       f"no scan. In its place: `ci / lint`'s security rules. {TURN_ON}")
    elif meta.get("security_and_analysis") is None and actions_token:
        result("INFO", f"{branch}: CodeQL is not judged here: no code_scanning rule for CodeQL and no CodeQL check "
                       "name, which on a private repository is a defect only where GitHub Code Security is enabled, "
                       "and the Actions token does not get the repository's security settings. The licence state is "
                       "judged when /plinth:floor-check is run with a login that administers the repository", deferred=True)
    else:
        why = ("this token does not read the repository's security settings; one with repository administration does"
               if meta.get("security_and_analysis") is None else
               "GitHub reports no Code Security status for this repository")
        result("SKIP", f"{branch}: CodeQL not verified: no code_scanning rule for CodeQL and no CodeQL check name, "
                       f"which on a private repository is a defect only where GitHub Code Security is enabled ({why})")
    if tools:
        check_codeql_policy(repo, branch, tools, policy)
    elif by_name:
        # A check name only asks the analysis to finish: the alerts it finds
        # block nothing. Said as not verified, not as the rule's policy.
        result("SKIP", f"{branch}: CodeQL alert thresholds not verified: a check name does not set them; "
                       f"the door's code_scanning rule does (scripts/add-ruleset-rule.sh {repo} code-scanning)")
    # The rule is only as wide as the languages default setup analyses. Enabled
    # before GitHub's language detection had run, it analysed `actions` alone
    # and the Python under src/ was never scanned while this line said
    # "enforced" (#120 finding I). Readable by an admin-read token; the Actions
    # token in `ci / floor-check` cannot, and says so rather than pass.
    # Without Code Security and without a rule there is no default setup to
    # read: the gap is already named above, and a SKIP here would count it twice.
    if tools or by_name or scanning != "disabled":
        setup = api(f"repos/{repo}/code-scanning/default-setup", network)
        langs = setup.get("languages") if isinstance(setup, dict) else None
        if not isinstance(langs, list) and actions_token:
            result("INFO", "CodeQL default setup languages not read here: the Actions token cannot read "
                           "code-scanning/default-setup; /plinth:floor-check reads them with a login that administers the repository", deferred=True)
        elif not isinstance(langs, list):
            result("SKIP", "CodeQL default setup languages not verified (the token cannot read code-scanning/default-setup)")
        else:
            # CodeQL's name for the language; `javascript` and `typescript`
            # are the older spellings GitHub still accepts (#681 review).
            if not_applying is None:
                lang, accepted, code = "python", {"python"}, "the Python under src/"
            else:
                lang, code = "javascript-typescript", "the JavaScript or TypeScript code"
                accepted = {lang, "javascript", "typescript"}
            if any(a in langs for a in accepted):
                result("PASS", f"CodeQL default setup analyses {langs}")
            else:
                result("WARN", f"CodeQL default setup analyses {langs}, not {code}")
                result("INFO", f"  gh api -X PATCH repos/{repo}/code-scanning/default-setup -f 'languages[]=actions' -f 'languages[]={lang}'")

    # The merge ruleset is the one ruleset allowed a bypass actor, judged by
    # its own shape; every other ruleset keeps none.
    judged, reserved = check_merge_ruleset(repo, branch, rules, merge, network, actions_token)
    if merge is not None:
        check_merge_setup(branch, meta, reserved, actions_token)
    ids = {r.get("ruleset_id") for r in rules if r.get("ruleset_source_type") == "Repository"} - judged
    for rid in sorted(i for i in ids if i):
        rs = api(f"repos/{repo}/rulesets/{rid}", network)
        actors = rs.get("bypass_actors") if isinstance(rs, dict) else None
        if actors is None:
            # Only visible with repository-administration read, which the
            # Actions token never has. The skill, run by the owner, sees it.
            if actions_token:
                result("INFO", f"ruleset {rid}: bypass actors not visible with this token; /plinth:floor-check reads them with a login that administers the repository", deferred=True)
                continue
            result("SKIP", f"ruleset {rid}: bypass actors not visible with this token (an admin-read token sees them)")
        else:
            ok(actors == [], f"ruleset {rid}: no bypass actors", f"ruleset {rid}: bypass actors present: {actors}")


def bypass_key(actor: dict) -> tuple[str, str, str]:
    return (str(actor.get("actor_id")), str(actor.get("actor_type")), str(actor.get("bypass_mode")))


def check_merge_ruleset(repo: str, branch: str, rules: list, merge: dict | None, network: bool,
                        actions_token: bool) -> tuple[set, str | None]:
    """The second ruleset the door applies (ruleset-merge.json, #568): the
    `update` rule alone, with the repository's admin role exempt from it, so
    an account with write access cannot merge and the admin still can, by
    every path it had. Recognised by its `update` rule; returns the ids judged here, which
    the no-bypass check then leaves alone, and what was found: "stands" (a
    PASS), "never" (its actors unread, but GitHub says this login can never
    bypass it), "missing" (the WARN) or None (anything else). A ruleset that carries `update`
    beside other rules is not one: its bypass would reach those rules, so it
    stays under the no-bypass check as well."""
    carriers = {r.get("ruleset_id") for r in rules if r.get("type") == "update"
                and r.get("ruleset_source_type") == "Repository" and r.get("ruleset_id")}
    if merge is None:
        if carriers:
            result("INFO", f"{branch}: the ruleset that reserves the merge to an admin is not compared (no --merge-ruleset)")
        return set(), None
    if not carriers:
        if any(r.get("type") == "update" for r in rules):
            result("SKIP", f"{branch}: the merge ruleset not verified: the update rule comes from a ruleset "
                           "outside this repository, whose bypass actors are not read here")
            return set(), None
        # Not in effect is not absent: a merge ruleset switched to evaluate or
        # disabled, or scoped off the default branch, is missing from the
        # branch's rules but still there, and then the merge is open while
        # it looks reserved. This repository's other rulesets are read for
        # one that carries `update`.
        listed = api(f"repos/{repo}/rulesets?per_page=100", network, paginate=True)
        if listed is ERROR or (listed is not ABSENT and not isinstance(listed, list)):
            result("SKIP", f"{branch}: the merge ruleset not verified: no ruleset in effect carries update, "
                           "and this repository's rulesets could not be listed")
            return set(), None
        in_effect = {r.get("ruleset_id") for r in rules}
        idle = []
        for item in listed if isinstance(listed, list) else []:
            rid = item.get("id") if isinstance(item, dict) else None
            if not rid or rid in in_effect or item.get("source_type", "Repository") != "Repository":
                continue
            rs = api(f"repos/{repo}/rulesets/{rid}", network)
            if isinstance(rs, dict) and any(r.get("type") == "update" for r in rs.get("rules", [])):
                idle.append(f"ruleset {rid} ({rs.get('enforcement')}, {rs.get('target')}, {rs.get('conditions')})")
        if idle:
            result("FAIL", f"{branch}: the merge ruleset is not in effect: {'; '.join(idle)}. Any account with write "
                           f"access can merge; expected enforcement {merge['enforcement']} on {merge['conditions']}")
            return set(), None
        # A WARN, not a FAIL: every repository made before #568 lacks it, and
        # `ci / floor-check` runs in each of them; while the agent works under
        # the person's own account it changes nothing.
        result("WARN", f"{branch}: no ruleset reserves the merge to an admin: any account with write access, "
                       "an agent's own account included, can merge a pull request")
        result("INFO", f"  scripts/with-admin-token.sh scripts/create-merge-ruleset.sh {repo}   (from a plinth checkout)")
        return set(), "missing"
    want_types = sorted(r["type"] for r in merge["rules"])
    want_actors = sorted(bypass_key(a) for a in merge["bypass_actors"])
    judged = set()
    passed = []
    cannot_bypass: list[bool] = []
    for rid in sorted(carriers):
        types = sorted({r.get("type") for r in rules if r.get("ruleset_id") == rid})
        if types != want_types:
            result("FAIL", f"{branch}: ruleset {rid} carries {types}, not {want_types} alone: "
                           "a bypass actor on it would reach every one of those rules")
            continue
        judged.add(rid)
        rs = api(f"repos/{repo}/rulesets/{rid}", network)
        # Its scope as well as its actor: widened to every branch, it still
        # lists `update` on the default branch, and stops everyone but the
        # admin from pushing a branch at all.
        scope_keys = ("target", "enforcement", "conditions")
        scope = {k: rs[k] for k in scope_keys} if isinstance(rs, dict) and all(k in rs for k in scope_keys) else None
        want_scope = {k: merge[k] for k in scope_keys}
        if scope is not None and scope != want_scope:
            result("FAIL", f"ruleset {rid}: the merge ruleset applies to {scope}, expected {want_scope}")
            continue
        actors = rs.get("bypass_actors") if isinstance(rs, dict) else None
        # GitHub's own answer for this login, readable without the actors.
        cannot_bypass.append(isinstance(rs, dict) and rs.get("current_user_can_bypass") == "never")
        if actors is None and actions_token:
            result("INFO", f"ruleset {rid}: the merge ruleset's bypass actors not visible with this token; "
                           "/plinth:floor-check reads them with a login that administers the repository", deferred=True)
        elif actors is None:
            result("SKIP", f"ruleset {rid}: the merge ruleset's bypass actors not visible with this token "
                           "(an admin-read token sees them)")
        elif sorted(bypass_key(a) for a in actors) != want_actors:
            result("FAIL", f"ruleset {rid}: the merge ruleset's bypass actors are {actors}, expected {merge['bypass_actors']}")
        elif scope is None:
            result("SKIP", f"ruleset {rid}: the merge ruleset's scope (target, enforcement, conditions) not read")
        else:
            result("PASS", f"ruleset {rid}: the merge is reserved to the repository admin (update, the admin role exempt)")
            passed.append(rid)
    if passed and len(passed) == len(carriers):
        return judged, "stands"
    # A login without the admin role cannot read the bypass actors (#569's
    # run): the line above is a SKIP, but GitHub still says whether this login
    # can bypass the ruleset, and "never" on every carrier in its scope means
    # its merge is refused.
    if cannot_bypass and len(cannot_bypass) == len(carriers) and all(cannot_bypass):
        return judged, "never"
    return judged, None


def check_merge_setup(branch: str, meta: dict, reserved: str | None, actions_token: bool) -> None:
    """Whether "merge on your word" is guidance or a boundary for the login
    this run reads with (#569): the login the agent inherits, when the skill
    runs in its session. GitHub lets the admin role past the merge ruleset
    whatever the token's own permissions (#517 measured the bypass following
    the account's role), so `permissions.admin` on the repository, the
    account's role, decides. The Actions token is not the agent's login, so
    `ci / floor-check` does not decide it; an unread role is not verified.
    `reserved` is check_merge_ruleset's answer, or "no rules" and "unread"
    when the branch's rules were empty or could not be read."""
    if actions_token:
        result("INFO", "the merge: not verified here: the Actions token is not the agent's login; "
                       "/plinth:floor-check decides guidance or boundary with the login the agent inherits", deferred=True)
        return
    perms = meta.get("permissions")
    admin = perms.get("admin") if isinstance(perms, dict) else None
    push = perms.get("push") if isinstance(perms, dict) else None
    if not isinstance(admin, bool):
        result("SKIP", "the merge: not verified: whether this login is the repository's admin could not be read")
    elif not admin and push is False:
        result("PASS", "the merge: boundary. This login cannot write to the repository, so it cannot merge; "
                       "you merge. It holds while no login with write access is left where the agent can reach it")
    elif not admin and push is not True:
        result("SKIP", "the merge: not verified: whether this login can write to the repository could not be read")
    elif admin:
        result("INFO", "the merge: guidance. This login is the repository's admin, and GitHub lets the admin merge, "
                       "so an agent working under it can merge too; it is asked to wait for your word, not stopped")
    elif reserved == "stands":
        result("PASS", f"the merge: boundary. This login is not the repository's admin and the merge ruleset stands "
                       f"on {branch}, so GitHub refuses its merge; you merge, with the button or your own login. "
                       "It holds while no admin login is left where the agent can reach it")
    elif reserved == "never":
        # Only this login's answer: whether the admin is still exempt, so
        # the person's merge goes through, is in the actors it cannot read.
        result("PASS", f"the merge: boundary. This login is not the repository's admin, and GitHub says it can never "
                       f"bypass the merge ruleset on {branch}, so GitHub refuses its merge. It holds while no admin "
                       "login is left where the agent can reach it. Whether the admin is still exempt, so that your "
                       "own merge goes through, is not read with this login: run /plinth:floor-check with yours")
    elif reserved == "missing":
        result("INFO", "the merge: guidance. This login is not the repository's admin, but no ruleset reserves the "
                       "merge to the admin, so it can merge; the WARN above adds that ruleset")
    elif reserved == "no rules":
        result("INFO", f"the merge: guidance. This login is not the repository's admin, but no rules govern {branch}, "
                       "so nothing reserves the merge to the admin and it can merge; the FAIL above is the wall to restore")
    elif reserved == "unread":
        result("SKIP", f"the merge: not verified: this login is not the repository's admin, and the rules of {branch} "
                       "could not be read, so whether a ruleset reserves the merge is not known")
    else:
        result("SKIP", "the merge: not verified: this login is not the repository's admin, "
                       "but the merge ruleset above was not found in its shape")


# ── this machine ──────────────────────────────────────────────────────────


def check_sandbox() -> None:
    """The sandbox is a setting of the machine, not of the repository, so CI
    never asks for it; the skill does. Only `sandbox.enabled: true` is a
    signal: `/sandbox` on Claude Code 2.1.278 writes that key nowhere read
    here (#222), so its absence says nothing about on or off and is not
    verified rather than a WARN. What the lines under it say was measured on
    macOS only; they say so."""
    conf = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")
    on = None
    for name in ("settings.json", "settings.local.json"):
        try:
            if json.loads(read(conf / name)).get("sandbox", {}).get("enabled") is True:
                on = on or conf / name
        except (OSError, ValueError, AttributeError):
            pass
    # A fact either way, never a PASS: on is not "good" here, since on macOS it
    # stops gh and the door, so the measured lines follow both.
    if on:
        result("INFO", f"sandbox.enabled is true in {on}")
    else:
        result("SKIP", f"sandbox not verified: sandbox.enabled is not true in {conf}/settings.json or settings.local.json, "
               "and /sandbox (Claude Code 2.1.278) does not write it there, so this cannot tell on from off")
    result("INFO", "  off: a `bash -c`, a `$(head -1 .env)`, a `grep -r` that names no file, or a script that opens "
           "`.env` itself still reads it; the sandbox is what closes those")
    result("INFO", "  on, macOS (measured on Claude Code 2.1.278): `gh` stops working, because the sandbox enforces the floor's "
           "deny `Read(~/.config/gh/**)` against `gh` itself; its fix, mask mode, is ignored in a repository's "
           ".claude/settings.json and on macOS blocks like deny even from user settings, so no project setting fixes it: "
           "anthropics/claude-code#95135 and anthropics/claude-code#67105 track it upstream")
    result("INFO", "  on, macOS: /plinth:new-project stops at `uvx --from copier copier`: ~/.cache/uv is not writable, "
           "and with UV_CACHE_DIR moved to a writable path uv panics reading the system proxy configuration")
    result("INFO", "  Linux, WSL2 and native Windows: not measured")


SHA = re.compile(r"[0-9a-f]{40}")


def check_plugins() -> None:
    """Each plugin installed from the plinth marketplace against the commit
    its entry pins (#743). `claude plugin update plinth@plinth` and
    `claude plugin install plinth@plinth` leave a dependency at its old commit
    while reading the entry's new skill list, so a skill the old commit keeps
    elsewhere reports "Path not found" until the dependency is updated by name
    (measured for #714). Read from Claude Code's own files under the config
    directory: installed_plugins.json (version 2) for what is installed and
    known_marketplaces.json for where the marketplace's copy is, whose
    marketplace.json holds the pins `claude plugin update <name>@plinth` moves
    to. A behind plugin is a WARN with that command; this never runs it.
    Anything not read or not comparable is a SKIP, never "at its pin": a
    plugin from another marketplace, an entry or install without a full
    commit, a file in a shape not known here. plinth itself has no pinned
    commit (its entry is the marketplace), so its installed version is
    compared with the marketplace copy's plugin.json."""
    conf = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")
    plugins_dir = conf / "plugins"
    try:
        installed = json.loads(read(plugins_dir / "installed_plugins.json"))
    except (OSError, ValueError) as e:
        result("SKIP", f"plugins not checked: {plugins_dir / 'installed_plugins.json'} not read ({type(e).__name__})")
        return
    if not isinstance(installed, dict) or installed.get("version") != 2 or not isinstance(installed.get("plugins"), dict):
        result("SKIP", f"plugins not checked: {plugins_dir / 'installed_plugins.json'} is not in the shape read here "
                       "(version 2 with a plugins map)")
        return
    try:
        loc = Path(json.loads(read(plugins_dir / "known_marketplaces.json"))["plinth"]["installLocation"])
        market = json.loads(read(loc / ".claude-plugin" / "marketplace.json"))
        if market.get("name") != "plinth":
            raise ValueError("not the plinth marketplace")
        entries = {e["name"]: e for e in market["plugins"]}
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as e:
        result("SKIP", f"plugins not checked: the plinth marketplace's copy and its marketplace.json not read "
                       f"through {plugins_dir / 'known_marketplaces.json'} ({type(e).__name__})")
        return

    def pinned(name: str) -> tuple[str | None, str]:
        """What the entry pins and how an install is compared with it: a full
        commit, or plinth's version; (None, why) when it pins neither."""
        e = entries.get(name)
        if not isinstance(e, dict):
            return None, "the plinth marketplace has no entry for it"
        if e.get("source") == "./":
            try:
                v = json.loads(read(loc / ".claude-plugin" / "plugin.json")).get("version")
            except (OSError, ValueError, AttributeError):
                v = None
            return (v, "version") if isinstance(v, str) and v else (None, "the marketplace copy's plugin.json version not read")
        sha = e.get("source", {}).get("sha") if isinstance(e.get("source"), dict) else None
        return (sha, "commit") if isinstance(sha, str) and SHA.fullmatch(sha) else (None, "its entry pins no full commit")

    current: list[str] = []
    other: list[str] = []
    for pid, installs in sorted(installed["plugins"].items()):
        name, _, mkt = pid.rpartition("@")
        if mkt != "plinth" or not name:
            other.append(pid)
            continue
        want, how = pinned(name)
        if not isinstance(installs, list) or not installs:
            result("SKIP", f"{pid} not checked: no install record read")
            continue
        for rec in installs:
            rec = rec if isinstance(rec, dict) else {}
            where = rec.get("scope") or "unknown scope"
            if rec.get("projectPath"):
                where += f" in {rec['projectPath']}"
            have = rec.get("gitCommitSha") if how == "commit" else rec.get("version")
            if want is None:
                result("SKIP", f"{pid} ({where}) not checked: {how}")
            elif not isinstance(have, str) or (how == "commit" and not SHA.fullmatch(have)):
                result("SKIP", f"{pid} ({where}) not checked: its install records no full {how}")
            elif have != want:
                shown = (lambda s: s[:12]) if how == "commit" else (lambda s: s)
                # The install's own scope, always named: without --scope,
                # `update` took user before Claude Code 2.1.281 and the most
                # specific scope of the current folder after it (third-party
                # review on #744). A project or local one runs from its folder.
                fix = f"claude plugin update {pid}"
                scope = rec.get("scope")
                if scope == "user":
                    fix += " --scope user"
                elif scope in ("project", "local"):
                    fix += f" --scope {scope}"
                    path = rec.get("projectPath")
                    fix = f"cd {shlex.quote(path)} && {fix}" if isinstance(path, str) and path else \
                        f"{fix}, run from the project folder it was installed for"
                result("WARN", f"{pid} ({where}) is behind its pin: installed {how} {shown(have)}, the plinth "
                               f"marketplace pins {shown(want)}; its skills may report \"Path not found\". "
                               f"fix: {fix}")
            else:
                current.append(f"{pid} ({where})")
    if current:
        result("INFO", "at the plinth marketplace's pin: " + ", ".join(current))
    if other:
        result("SKIP", "plugins not checked, not from the plinth marketplace: " + ", ".join(other))


# gh's own git helper, whatever path it was installed under, and nothing else:
# a `!` helper that also calls gh may answer with its own token first. A path
# with a space comes single-quoted from `gh auth setup-git` (gh 2.101.0).
# Without `!`, git runs `git credential-gh ...`, another program; an absolute
# path without `!` does run gh, but is reported as another helper all the same.
# An unquoted path takes no shell character: `!/x;/usr/bin/gh ...` runs /x first.
# Only spaces and tabs separate the words: a newline starts another command.
GH_HELPER = re.compile(r"!('[^']*/gh(\.exe)?'|([\w./~+@%:,-]*/)?gh(\.exe)?)[ \t]+auth[ \t]+git-credential")


# glab's credential helper, as the GitLab door writes it (`!glab auth git-credential`).
GLAB_HELPER = re.compile(r"!('[^']*/glab(\.exe)?'|([\w./~+@%:,-]*/)?glab(\.exe)?)[ \t]+auth[ \t]+git-credential")
# The variables glab takes a token from, before its stored login.
GLAB_TOKEN_VARS = ("GITLAB_TOKEN", "GITLAB_ACCESS_TOKEN", "OAUTH_TOKEN")


# One ~/.netrc token: a double-quoted one (group 1), a bare one (group 2), or a
# quote left open (group 3).
NETRC_TOKEN = re.compile(r'"((?:[^"\\]|\\.)*)"|([^\s"]\S*)|("\S*)')


# Variables that change which gh or git configuration is read (third-party
# review round 8 on #344). GIT_CONFIG makes git read that file in place of
# the repository's .git/config (#349).
CONFIG_MASKS = ("GH_CONFIG_DIR", "XDG_CONFIG_HOME", "GIT_CONFIG", "GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM",
                "GIT_CONFIG_NOSYSTEM", "GIT_CONFIG_COUNT", "GIT_CONFIG_PARAMETERS")
# The same for glab, whose configuration GLAB_CONFIG_DIR moves.
GLAB_CONFIG_MASKS = ("GLAB_CONFIG_DIR",) + CONFIG_MASKS[1:]


def host_https(url: str | None, host: str = "github.com") -> bool | None:
    """Does a config subsection (`credential.<url>.helper`) apply to a push to
    https://<host> (github.com, or gitlab.com for #547)? git applies every entry whose URL matches the request,
    in config order, and an empty helper clears the list read so far
    (`credential_apply_config`, git 2.55.0; #349). True when it names the host
    and nothing narrower; None when it also names a path, a username, a port, a
    query or a fragment, which git applies to some requests or to none (counted, but its empty value is not taken
    as clearing the list); False otherwise. A scheme-less host name applies:
    git matches it as a partial URL. Raises ValueError for a URL that cannot
    be parsed."""
    if url is None:
        return True
    u = urllib.parse.urlsplit(url if "://" in url else "https://" + url)
    if u.scheme != "https" or (u.hostname or "") != host:
        return False
    port = u.port   # raises ValueError for a port that is not a number
    if u.username is not None or port not in (None, 443) or u.path.strip("/") or u.query or u.fragment or "?" in url or "#" in url:
        return None
    return True


def netrc_has_host(words: list[str], host: str = "github.com") -> bool | None:
    """Does ~/.netrc hold an entry for host, or a default one? A keyword
    opens an entry (`machine <host>`, `default`) or takes one value inside it
    (`login`, `password`, `account`), so `default` counts only where a keyword
    stands. Any other sequence (a stray word, a keyword without its value,
    `macdef`) is not placed: None."""
    found, entry, i = False, False, 0
    while i < len(words):
        w = words[i].lower()
        if w == "default":
            found, entry, i = True, True, i + 1
        elif w == "machine" and i + 1 < len(words):
            found, entry, i = found or words[i + 1].lower() == host, True, i + 2
        elif w in ("login", "password", "account") and entry and i + 1 < len(words):
            i += 2
        else:
            return None
    return found


def none_found(what: str) -> None:
    """Finding nothing is not a pass: these rules read gh's and git's formats
    as far as they go, and a credential they do not recognise is not reported
    (#344's review found one after another). A WARN is what they found."""
    result("INFO", f"{what}; no other credential found by these rules; best effort, see the guide's list")


def check_credentials(root: Path, host: str = "github") -> None:
    """What on this machine can push to github.com besides the token the agent
    was given (#336). Measured with gh 2.101.0 and git 2.55.0: a second account
    stored in gh is one `gh auth switch` away, and a git helper other than gh's
    answers whenever it comes first or gh has no login, and one listed after
    gh's collects the credential of every push that succeeds. Presence only:
    no value is read or printed. An item that could not be read is not
    verified; SSH is never read here, since the key that counts is the one
    GitHub accepts. `gh auth status` checks each stored token with GitHub, so
    this item goes online even under --no-network; offline, gh's answer is
    what it is, and one that is not its JSON is not verified.

    On GitLab (#547) the same reads for gitlab.com: glab's token variables,
    git helpers other than glab's, an Authorization header and ~/.netrc. The
    login glab stores is not counted (its configuration is not read), a SKIP."""
    gitlab = host == "gitlab"
    name, cli = ("gitlab.com", "glab") if gitlab else ("github.com", "gh")
    token_vars = GLAB_TOKEN_VARS if gitlab else ("GH_TOKEN", "GITHUB_TOKEN")
    env_tokens = [var for var in token_vars if os.environ.get(var)]
    for var in env_tokens:
        result("WARN", f"{var} is set in this environment: {cli}, and the git push it serves, use it before any stored login")
        result("INFO", f"  remove {var} where it is set (a shell startup file), then restart Claude Code")

    # Each points gh or git away from, or adds to, the configuration read by
    # default; that one is not read here, and the agent can unset the variable.
    for var in (GLAB_CONFIG_MASKS if gitlab else CONFIG_MASKS):
        if var in os.environ:   # set but empty counts: `GIT_CONFIG_GLOBAL=` reads no global file
            result("SKIP", f"{var} is set: the gh or git configuration read without it was not read, "
                   "and the agent can unset it")

    if gitlab:
        result("SKIP", "the login glab stores for gitlab.com not verified: glab's configuration is not read here; "
               "`glab auth status --hostname gitlab.com` shows it")
    else:
        env = {k: v for k, v in os.environ.items() if k not in ("GH_TOKEN", "GITHUB_TOKEN")}
        try:
            r = subprocess.run(["gh", "auth", "status", "--hostname", "github.com", "--json", "hosts"],
                               capture_output=True, text=True, timeout=30, check=False, env=env)
            accounts = json.loads(r.stdout)["hosts"].get("github.com", []) if r.returncode == 0 else None
        except (OSError, subprocess.TimeoutExpired, ValueError, KeyError, TypeError, AttributeError):
            accounts = None
        if not isinstance(accounts, list):
            result("SKIP", "accounts stored in gh not verified: `gh auth status --json hosts` could not be read")
        else:
            logins = [str(acct.get("login", "?")) if isinstance(acct, dict) else "?" for acct in accounts]
            active = [str(acct.get("login", "?")) for acct in accounts if isinstance(acct, dict) and acct.get("active")]
            if len(logins) > 1:
                result("WARN", f"gh stores {len(logins)} accounts for github.com (active: {', '.join(active) or 'none'}): "
                       "each is one `gh auth switch` away")
                # Which account holds the agent's token is not known here, active or
                # not (third-party review round 9 on #344): the person chooses.
                result("INFO", "  keep only the account that holds the agent's token; log out each of the others:")
                for login in logins:
                    result("INFO", f"  gh auth logout --hostname github.com --user {shlex.quote(login)}")
            elif logins and env_tokens:
                # The agent can unset the variable itself, and the stored login answers.
                result("WARN", f"gh stores 1 account for github.com ({logins[0]}) besides {' and '.join(env_tokens)}: "
                       "unsetting the variable uses it")
                result("INFO", "  keep one: the agent's token stored in gh with the variable removed, or "
                       f"gh auth logout --hostname github.com --user {shlex.quote(logins[0])}")
            else:
                none_found(f"gh stores {len(logins) or 'no'} account{'' if len(logins) == 1 else 's'} for github.com"
                           + (f": {logins[0]}" if logins else ""))

    g: subprocess.CompletedProcess[str] | None
    try:
        g = subprocess.run(["git", "-C", str(root), "config", "--null", "--get-regexp",
                            r"^(credential\..*helper|http\..*extraheader)$"],
                           capture_output=True, text=True, timeout=30, check=False)
    except (OSError, subprocess.TimeoutExpired):
        g = None
    if g is None or g.returncode not in (0, 1):   # 1: no such key
        result("SKIP", "git credential helpers not verified: `git config` could not be read")
    else:
        helpers: list[str] = []
        headers = 0
        for entry in filter(None, g.stdout.split("\0")):
            key, _, value = entry.partition("\n")
            section, _, rest = key.partition(".")
            sub = rest.rpartition(".")[0]
            try:
                applies = host_https(sub or None, name)
            except ValueError:
                # Named by what follows its last `@` only: a user or password
                # before it, with or without a scheme, is never printed.
                shown = "…@" + sub.rpartition("@")[2] if "@" in sub else sub
                shown = shown if shown.isprintable() else "a URL with a control character"
                result("SKIP", f'git config [{section} "{shown}"] not verified: its URL could not be parsed, '
                       f"so whether it applies to {name} is unknown")
                continue
            if applies is False:
                continue
            if section == "http":
                headers += value.strip().lower().startswith("authorization")
            elif value.strip():
                helpers.append(value.strip())
            elif applies:   # an empty helper clears the list read so far, as git does
                helpers = []
        # Named by its first word only: a `!` helper is a shell command that may carry the token itself.
        others = ["a `!` shell command" if h.startswith("!") else h.split()[0]
                  for h in helpers if not (GLAB_HELPER if gitlab else GH_HELPER).fullmatch(h)]
        if others:
            result("WARN", f"git has {len(others)} credential helper{'s' if len(others) > 1 else ''} for {name} "
                   f"besides {cli}'s: {', '.join(others)} (`git config --show-origin --get-regexp 'credential.*helper'` "
                   "shows where)")
            result("INFO", f"  one listed before {cli}'s, or any while {cli} has no login, answers the push; one listed after "
                   f"{cli}'s was seen storing the credential a push succeeded with. Delete its {name} entry, then clear the list with an "
                   f"empty `helper =` before {cli}'s under `[credential \"https://{name}\"]` in ~/.gitconfig")
        else:
            none_found(f"git asks {'only ' + cli if helpers else 'no credential helper'} for {name}")
        if headers:
            result("WARN", f"git config sends an Authorization header to {name} (http.extraHeader): "
                   "`git config --show-origin --get-regexp extraheader` shows where")

    netrc = Path(os.environ.get("HOME") or Path.home()) / ".netrc"
    try:
        # A line opening with `#` is a comment to netrc's readers.
        lines = [line for line in read(netrc).splitlines() if not line.lstrip().startswith("#")] if netrc.exists() else []
    except OSError:
        lines = None
    # curl takes a token in double quotes, backslash escapes inside, as one
    # word without the quotes; a quote left open is not guessed at.
    tokens = [m for line in lines or [] for m in NETRC_TOKEN.finditer(line)]
    words = [re.sub(r"\\(.)", r"\1", m.group(1)) if m.group(1) is not None else m.group(2) or "" for m in tokens]
    github = netrc_has_host(words, name)
    if lines is None:
        result("SKIP", f"{netrc} not verified: it exists and could not be read")
    elif any(m.group(3) is not None for m in tokens):
        result("SKIP", f"{netrc} not verified: a quoted token is not closed")
    # Host names and keywords in any case: curl 8.5.0 matched `GITHUB.COM` (third-party review on #344).
    elif github is None:
        result("SKIP", f"{netrc} not verified: a token sequence this reader does not place (a stray word, "
               "a keyword without its value, or macdef)")
    elif github:
        result("WARN", f"{netrc} holds a login for {name} (or a default one): git over HTTPS uses it")
    else:
        none_found(f"no {name} login in {netrc}")

    if gitlab:
        result("SKIP", "SSH keys not verified here: GitLab's Preferences → SSH Keys, and the project's Deploy keys, "
               "say which keys push")
    else:
        result("SKIP", "SSH keys not verified here: GitHub's Settings → SSH and GPG keys, and the repository's Deploy keys, "
               "say which keys push; see docs/how-to/give-the-agent-a-token.md")
    result("INFO", "  not read either: a program named by GIT_ASKPASS or core.askPass, a token saved in any other file")


# A PostgreSQL URL, the scheme in any case and with an optional SQLAlchemy
# driver (`postgresql+psycopg://`). The match runs to the next space or quote.
PG_URL = re.compile(r"postgres(?:ql)?(?:\+\w+)?://[^\s'\"`]*", re.IGNORECASE)
# Database names that say they are for tests: `test`, `app_test`, `test-app`, `tests`, `testing`.
TEST_DB = re.compile(r"(?:^|[_-])test(?:s|ing)?(?:[_-]|$)", re.IGNORECASE)
# Hosts that cannot be a production server: loopback, a Unix socket (empty or a
# path), and RFC 2606/6761's reserved names, which placeholders use. A host
# that is a variable or a placeholder (`${PGHOST}`, `<host>`) is not judged.
LOCAL_SUFFIXES = (".localhost", ".example", ".test", ".invalid", ".example.com", ".example.org", ".example.net")
LOCAL_HOSTS = {"", "localhost", "example.com", "example.org", "example.net"}
# A name printed beside a hit: an identifier, or nothing. A line such as
# `postgres://user:pw@host/db=x` has text before its `=` that is not a name.
PRINTABLE_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_.-]{0,63}")


def pg_url_is_production(url: str) -> bool:
    """Could this PostgreSQL URL reach a production database? False only when
    every destination it names is local (or a placeholder), or the database
    it names is a test one; True for anything else, a URL this cannot
    parse included. Every host libpq could connect to is judged, not the one
    this reader expects to win (third-party review rounds 1 and 2 on #648):
    those of the authority (`h1,h2:5433`) and each comma list of every
    `host=` and `hostaddr=`. The database is the one libpq uses: the last
    `dbname=`, else the path. A `service=` takes them from a file not read
    here, so a URL with one is never judged local."""
    try:
        split = urllib.parse.urlsplit(url)
    except ValueError:   # an unclosed `[` of an IPv6 host
        return True
    query = urllib.parse.parse_qs(split.query, keep_blank_values=True)
    if "service" in query:
        return True
    authority = split.netloc.rpartition("@")[2]
    hosts = [h.rpartition("]")[0].lstrip("[") if h.startswith("[") else h.partition(":")[0] for h in authority.split(",")]
    hosts += [h.strip() for key in ("host", "hostaddr") for v in query.get(key, []) for h in v.split(",")]
    dbname = (query.get("dbname") or [urllib.parse.unquote(split.path.lstrip("/"))])[-1]
    if dbname and TEST_DB.search(dbname):
        return False

    def local(host: str) -> bool:
        host = urllib.parse.unquote(host).lower()
        try:
            ip = ipaddress.ip_address(host)
        except ValueError:
            ip = None
        return (host in LOCAL_HOSTS or host.startswith("/") or host.endswith(LOCAL_SUFFIXES)
                or (ip is not None and (ip.is_loopback or ip.is_unspecified)) or any(c in host for c in "${}<>"))
    return not all(local(h) for h in hosts)


def dotenv_values(text: str):
    """Yield (line number, name, value) for each assignment in dotenv text:
    blank lines and `#` comments skipped, `export ` dropped, a quoted value
    read inside its quotes, an unquoted one up to a ` #` comment. A line with
    no `=`, or with no variable name before it, is yielded whole, name None:
    it is read, not guessed at."""
    for n, line in enumerate(text.splitlines(), 1):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        s = re.sub(r"^export\s+", "", s)
        name, eq, value = s.partition("=")
        # Text before the `=` that is not a name (`postgres://u:pw@h/db=x`) is part of the value.
        if not eq or not PRINTABLE_NAME.fullmatch(name.strip()):
            yield n, None, s
            continue
        value = value.strip()
        if value[:1] in {"'", '"'} and value[0] in value[1:]:
            value = value[1:value.index(value[0], 1)]
        else:
            value = re.split(r"\s#", value, maxsplit=1)[0]
        yield n, name.strip(), value


def production_url_in(value: object) -> bool:
    return isinstance(value, str) and any(pg_url_is_production(m.group(0)) for m in PG_URL.finditer(value))


DB_FIX = ("keep the production URL only in the host's settings (its dashboard's environment variables) and use a "
          "local database for work, the template's SQLite default")


def check_database_urls(root: Path) -> None:
    """Is a production database URL within the agent's reach (#648)? A
    PostgreSQL URL whose host is not local and whose database is not a test
    one, in three places: this process's environment, `.env*` files under
    --root (tracked or not; a directory named `.env*` is not entered, it is
    usually a virtualenv), and the `env` block of .claude/settings.json and
    settings.local.json, the repository's and the user's. A WARN names the
    place (the variable, or the file and line), never the value. Shell
    profile files are not read, nor other database schemes: nothing found is
    an INFO naming those limits, never a PASS."""
    found = 0

    def warn(where: str, fix: str) -> None:
        nonlocal found
        found += 1
        result("WARN", f"a production database URL is within the agent's reach: {where}")
        result("INFO", f"  {fix}; {DB_FIX}")

    def named(name: str | None, what: str) -> str:
        return name if name is not None and PRINTABLE_NAME.fullmatch(name) else what

    for var in sorted(os.environ):
        if production_url_in(os.environ[var]):
            warn(f"{named(var, 'a variable')} in this environment", "remove it where it is set (a shell startup file), then restart Claude Code")

    files = []
    for d, dirs, names in os.walk(root):
        dirs[:] = sorted(x for x in dirs if x not in SKIP_DIRS and not x.startswith(".env"))
        files += [Path(d) / f for f in sorted(names) if f.startswith(".env")]
    for p in files:
        rel = p.relative_to(root).as_posix()
        try:
            text = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            result("SKIP", f"{rel} not verified: it could not be read")
            continue
        for n, name, value in dotenv_values(text):
            if production_url_in(value):
                warn(f"{rel} line {n}" + (f" ({name})" if name else ""), "delete the line")

    conf = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")
    for p, shown in [(root / ".claude" / n, f".claude/{n}") for n in ("settings.json", "settings.local.json")] + \
                    [(conf / n, str(conf / n)) for n in ("settings.json", "settings.local.json")]:
        if not p.is_file():
            continue
        try:
            env = json.loads(read(p)).get("env", {})
        except (OSError, ValueError, AttributeError):
            result("SKIP", f"{shown} not verified: it could not be read as JSON")
            continue
        if not isinstance(env, dict):
            result("SKIP", f"{shown} not verified: its env is not an object")
            continue
        for var in sorted(env):
            if production_url_in(env[var]):
                warn(f"{named(var, 'an entry')} in the env of {shown}", "delete the entry")

    if not found:
        result("INFO", "no production database URL found in this environment, the repository's .env* files or the env of "
               ".claude/settings*.json (the repository's and the user's); best effort: shell profile files, other files "
               "and schemes other than postgres:// and postgresql:// are not read")


# ── main ──────────────────────────────────────────────────────────────────


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", default=".", help="repository checkout")
    ap.add_argument("--project", default=".", help="project root, relative to --root and inside it (the repository itself, or a directory under it)")
    ap.add_argument("--repo", help="owner/name on GitHub, or group/name on GitLab.com; enables inheritance and wall checks")
    ap.add_argument("--host", choices=("github", "gitlab"),
                    help="where the repository lives; default: `host:` in .copier-answers.yml, else github")
    ap.add_argument("--ruleset", help="ruleset.json the door applies; its contexts are the expected checks and its CodeQL thresholds the expected policy")
    ap.add_argument("--expect-checks", help="required check names, comma separated; overrides --ruleset")
    ap.add_argument("--merge-ruleset", help="ruleset-merge.json the door applies beside --ruleset: the `update` rule "
                    "bypassed by the repository admin only; compared with the live ruleset that carries `update`")
    ap.add_argument("--archetype", help="override the archetype in .copier-answers.yml")
    ap.add_argument("--no-network", action="store_true", help="skip everything that needs api.github.com")
    ap.add_argument("--caller-from-checkout", action="store_true",
                    help="read the ci job from the checkout, not the default branch: what `ci / floor-check` passes, "
                         "so a pull request that repairs the caller can merge")
    ap.add_argument("--actions-token", action="store_true",
                    help="the run's token is the Actions token, which does not get a repository's security settings, "
                         "bypass actors, CodeQL default setup or squash commit settings: each one it cannot read is an "
                         "INFO naming who reads it, not a SKIP, and so is a private repository's missing CodeQL rule, "
                         "which only the licence state can judge. What "
                         "`ci / floor-check` passes; the skill and the e2e runner do not")
    ap.add_argument("--verdicts", metavar="FILE",
                    help="also write one verdict line per FAIL, SKIP and read left to /plinth:floor-check, "
                         "or a pass line, to FILE (ci / floor-check's job summary)")
    ap.add_argument("--sandbox", action="store_true", help="also report what this machine's Claude Code settings say about the sandbox")
    ap.add_argument("--plugins", action="store_true",
                    help="also compare each plugin installed from the plinth marketplace with the commit its entry pins")
    ap.add_argument("--credentials", action="store_true",
                    help="also report what else on this machine can push to github.com (gitlab.com with --host gitlab): "
                         "gh accounts, git helpers, ~/.netrc; and a production database URL in the environment, "
                         ".env* files or the env of .claude/settings*.json")
    ap.add_argument("--print-conditional-archetypes", action="store_true", help=argparse.SUPPRESS)
    ap.add_argument("--print-update-command", action="store_true",
                    help="print the template drift item's `copier update` line alone and exit (1, with the reason, when there is none)")
    ap.add_argument("--plinth-pin", choices=("live", "tested"), default="live",
                    help="with --print-update-command: the line carrying the plinth pin the workflows call (live, "
                         "the default) or the one the target template tag was tested with (tested; only when it is newer)")
    ap.add_argument("--print-ruleset", action="store_true",
                    help="print --ruleset as the door applies it for --archetype (the image check added for a service archetype), and exit")
    ap.add_argument("--without-code-scanning", action="store_true",
                    help="with --print-ruleset: leave the code_scanning rule out, as the door does for a private "
                         "repository without GitHub Code Security")
    a = ap.parse_args()

    if a.print_conditional_archetypes:
        print(" ".join(CONDITIONAL_ARCHETYPES))
        return 0
    if a.without_code_scanning and not a.print_ruleset:
        ap.error("--without-code-scanning needs --print-ruleset")
    if a.print_ruleset:
        if not a.ruleset:
            ap.error("--print-ruleset needs --ruleset")
        print(json.dumps(ruleset_for(json.loads(read(Path(a.ruleset))), a.archetype, code_scanning=not a.without_code_scanning), indent=2))
        return 0

    root = Path(a.root).resolve()
    if a.plinth_pin != "live" and not a.print_update_command:
        ap.error("--plinth-pin needs --print-update-command")
    if a.print_update_command:
        return print_update_command(root, a.plinth_pin, not a.no_network, a.host,
                                    a.repo.split("/")[0] if a.repo else None)
    project = (root / a.project).resolve()
    if project != root and root not in project.parents:
        # Every item reads one repository: .github/, AGENTS.md, the ruleset at
        # --root and the project under it. A project elsewhere on disk used to
        # end in a traceback from relative_to (#464); it is a usage error.
        ap.error(f"--project must be inside --root: {project} is not under {root}; "
                 "pass the repository as --root and the project's path under it as --project")
    network = not a.no_network
    owner = a.repo.split("/")[0] if a.repo else None

    host = a.host or (copier_answers(root) or {}).get("host") or "github"
    if host not in ("github", "gitlab"):
        result("SKIP", f".copier-answers.yml says host: {host}, which this checker does not read; "
                       "read as github (pass --host to choose)")
        host = "github"
    print(f"floor check: root={root} project={project.relative_to(root) if project != root else '.'}"
          + (" host=gitlab" if host == "gitlab" else ""))
    javascript = host == "github" and javascript_project(project, root)
    if javascript:
        result("INFO", "read as a JavaScript or TypeScript project (package.json here, no pyproject.toml): plinth has "
                       "no checks for its language, so no lint, typecheck, test or build check; the checks that do not "
                       "depend on the language still apply: the documents, .claude/settings.json, .gitattributes, "
                       "Dependabot, tracked .env files, action pins and, with a repository name, the ruleset, push "
                       "protection and CodeQL")
    check_files(root, owner, network, host)
    archetype = archetype_of(project, a.archetype)
    if javascript:
        check_javascript_project(project)
        archetype = None
    else:
        check_project(project, root, archetype, host)
    if archetype in CONDITIONAL_ARCHETYPES:
        (check_gitlab_image_job if host == "gitlab" else check_image_job)(root)

    if host == "gitlab":
        if a.repo and network:
            check_gitlab_wall(root, a.repo, network)
        else:
            check_gitlab_include(root, network)
            result("SKIP", "no --repo: wall not checked" if not a.repo else "--no-network: the GitLab wall not checked")
    else:
        if javascript:
            result("N/A", f"the ci job's call to {CALLER_WORKFLOW} does not apply: that workflow runs Python's lint, "
                          "typecheck, test and build, which have nothing to run on here")
        else:
            check_caller(root, a.repo, network, a.caller_from_checkout, archetype)
        check_plinth_pins_agree(root)

    if host == "gitlab":
        pass
    elif a.repo:
        expected: list[str] = []
        merge_methods = {"squash"}
        policy = None
        sources: dict[str, int | None] | None = None
        pinned: dict[str, int] = {}
        common: int | None = None
        if a.ruleset:
            data = ruleset_for(json.loads(read(Path(a.ruleset))), archetype)
            policy = codeql_policy(data)
            expected = [c["context"] for r in data["rules"] if r["type"] == "required_status_checks"
                        for c in r["parameters"]["required_status_checks"]]
            # Each check's expected app is the one the ruleset pins it to. A name
            # only --expect-checks gives takes the app every ruleset check shares,
            # and is left uncompared (SKIP) when they do not share one.
            pinned = {c["context"]: c["integration_id"] for r in data["rules"]
                      if r["type"] == "required_status_checks"
                      for c in r["parameters"]["required_status_checks"] if c.get("integration_id") is not None}
            all_ids = {c.get("integration_id") for r in data["rules"] if r["type"] == "required_status_checks"
                       for c in r["parameters"]["required_status_checks"]}
            common = next(iter(all_ids)) if len(all_ids) == 1 and None not in all_ids else None
            merge_methods = {m for r in data["rules"] if r["type"] == "pull_request"
                             for m in r["parameters"].get("allowed_merge_methods", [])} or merge_methods
        if a.expect_checks:
            expected = [c.strip() for c in a.expect_checks.split(",") if c.strip()]
        # A `ci / <job>` name is reported by the ci job's call to python-ci.yml,
        # which a JavaScript or TypeScript repository does not make (#681).
        not_applying = [c for c in expected if c.startswith("ci / ")] if javascript else None
        if not_applying:
            expected = [c for c in expected if c not in not_applying]
        if a.ruleset:
            sources = {c: pinned.get(c, common) for c in expected}
        result("INFO", f"wall expectation: checks {expected}, merge methods {sorted(merge_methods)}")
        merge = json.loads(read(Path(a.merge_ruleset))) if a.merge_ruleset else None
        check_wall(a.repo, expected, merge_methods, policy, network, sources, a.actions_token, merge, not_applying)
        check_actions_allowlist(root, a.repo, network, a.actions_token)
        check_labels(a.repo, network)
    else:
        result("SKIP", "no --repo: wall not checked")

    if a.sandbox:
        check_sandbox()
    if a.plugins:
        check_plugins()
    if a.credentials:
        check_credentials(root, host)
        check_database_urls(root)

    print(f"-- {fails} failed, {skips} not verified" + (f", {left} left to /plinth:floor-check" if left else "")
          + (f", {na} do not apply" if na else ""))
    if a.verdicts:
        lines = verdicts if fails else ["pass: the floor, no FAIL in what this run read", *verdicts]
        Path(a.verdicts).write_text("".join(f"{line}\n" for line in lines), encoding="utf-8")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
