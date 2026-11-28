#!/usr/bin/env python3
"""Floor check: does a repository still have what the door gave it, and does
its wall still stand? Read-only. Exit 1 on any FAIL.

Run by `ci / floor-check` in python-ci.yml and by the floor-check skill, from
this same file; token, network and inputs can still make their results differ.
An item the run could not read (offline, no --repo, an API error, a token that
does not see it) is a SKIP, counted in the summary and never a PASS: exit 0
says no FAIL in what was checked, and `N not verified` says what was not (#119).
A SKIP no change on this machine or repository clears (SSH keys, the sandbox's
unrecorded state, a GitHub status the plan does not expose) ends
`[cannot be read here]` and is counted apart inside that number (#1002).
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
does not read is in its docstring and in skills/floor-check/reference.md.

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

render.yaml is read whenever it is there (#811), WARN-only: each web
service's healthCheckPath and autoDeployTrigger: checksPass, a database plan
other than free, and no literal value for a secret-named envVars key. A form
the small block-YAML reader does not read is one SKIP for the file. Without
the file nothing is said, except on a Render web instance, which needs it.

Two more WARN-only items read settings the same way (#747): the Actions
allowlist against the `uses:` lines of the local workflows (an action it
refuses ends its run in startup_failure), and private vulnerability
reporting, which SECURITY.md names (an INFO on a private repository, which
GitHub does not offer it), and whether SECURITY.md's route fits the
repository's visibility.

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
the workflows call today (#219), and is printed only when that pin is not
older than the one the target tag was tested with, after up to three more
reads: the tag's copier.yml, plinth's tags and a compare of the two plinth
commits (#511). Older, or not compared, there is no line: the pin is raised
first, in a pull request of its own, and --print-update-command with --repo
names an open one that changes the plinth uses: lines, one read for the open
pull requests and one for each one's files (#1183). The line is
printed only while the target tag still names new-project.sh's template_sha,
the commit plinth was tested with, read with one more call: a moved tag is a
WARN with no line, and an unread one prints the line here but not from
--print-update-command, the line that runs (#519). On GitHub the line also
carries the owner's two answers, read as /plinth:new-project reads them
(the owner's .github: its visibility, three pull-request template paths,
the shared issue-template folder and each form in it, #726), true only
while the repository has none of its own; without --repo, or with a read
that fails, there is no line, here or from --print-update-command. With
--move-archetype <a>, --print-update-command prints the same-tag line with
`--data archetype=<a>` instead, only at the target tag and never to or from
`web`, and names on stderr the required check the move drops or adds (#1004).

Beside that item, outside `ci / floor-check` (--actions-token): two or three
more reads compare the tag this plinth targets with the latest release's and
the tag the CI pin was tested with (#843). Older is a WARN with the commands
to type; a release not read is an INFO. --print-plugin-skew is the same
comparison for the template-update skill, which stops on it.
--print-behind is for /plinth:guide (#904): the drift item's template
comparison and the CI's plinth pin against plinth's latest release (two reads:
the release, and GitHub's compare), one line each, `not read` when not read.

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
import datetime
import fnmatch
import importlib
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
# The short list #219's drift item shows a diff for, alongside the bare list
# of what else changed, by the rendered name: each one's source under
# template/ is that name or that name with .jinja (#969).
TEMPLATE_DRIFT_DIFF_FILES = ("AGENTS.md", "CONTRIBUTING.md", ".gitignore")

SKIP_DIRS = {".git", ".venv", "node_modules", ".plinth-ci", ".smoke", ".scratch", "dist"}
# What GitHub accepts under .github/ISSUE_TEMPLATE: forms in either YAML
# spelling, and the legacy Markdown templates it still renders. `config.yml`
# is the folder's configuration, not a form.
FORM_SUFFIXES = {".yml", ".yaml", ".md"}
CONFIG_NAMES = {"config.yml", "config.yaml"}

UNREADABLE = "[cannot be read here]"
LEFT_TO_SKILL = "; left to /plinth:floor-check"
# The one next action a FAIL or WARN carries where CI shows it (#837); python-ci.yml's
# floor-check step has the same words. Empty for a person's run, which is the skill.
# At the plinth commit ci / floor-check fetched this from (job.workflow_sha); main run by hand.
REPORT = f"https://github.com/coolbress/plinth/blob/{(os.environ.get('PLINTH_SHA') or 'main')[:12]}/skills/floor-check/SKILL.md#report"
NEXT_ACTION = f"run /plinth:floor-check, which writes the fix for each item: {REPORT}"
next_action = ""
# "json" (--format json): the run is printed once, as one JSON document, at
# the end; nothing else goes to stdout.
out_format = "text"
# The SKIP's next action; a line the job annotates stays within 300 characters
# (the report beside it has the whole text).
SKIP_NEXT = f"; run /plinth:floor-check where it can read this: {REPORT}"

# --- Checks, ids and states (#1103) -----------------------------------------
# Every check has an entry in REGISTRY: an opaque id (`FC-<area><nn>`, never
# reused; a retired id stays as an alias of the one that replaced it), what it
# needs to run, who acts on what it finds, and the states it can return. A
# check reports through emit(id, state, msg_key, values); the text and
# verdicts renderers turn the results into the lines this file printed before
# ids existed, byte for byte (tests/floor-check-golden.sh holds them).
# Every line the checker prints comes from a registered check: there is no
# way left to print a verdict without an id (tests/floor-check-golden.sh).
#
# The states, one to one with the verdicts printed:
#   pass PASS, fail FAIL, warn WARN, unknown SKIP (with a reason),
#   review INFO left to someone who can read it (with who), not_applicable N/A,
#   info INFO.
# Areas, one name per letter (#1103). The letter groups the checks; it does
# not define them: a check that moves area keeps its id, and its entry's
# `area` names where it is now.
#   A files    B agent    C project    D ci    E wall    F plinth    G machine    R records
AREAS = {"A": "files", "B": "agent", "C": "project", "D": "ci", "E": "wall", "F": "plinth", "G": "machine",
         "R": "records"}
STATES = ("pass", "fail", "warn", "unknown", "review", "not_applicable", "info")
SHOWN = {"pass": "PASS", "fail": "FAIL", "warn": "WARN", "unknown": "SKIP", "review": "INFO",
         "not_applicable": "N/A", "info": "INFO"}
HOSTS = ("github", "gitlab")
NEEDS = ("files", "git", "network", "gh", "admin", "machine")
HANDOFFS = ("agent", "person", "admin", "ci")
LIFECYCLES = ("experimental", "stable")
# Where a check's result is shown (#1103): in the report, only in the JSON
# (#1105), or only when the skill is asked for that view.
VIEWS = ("report", "json", "opt-in:machine", "opt-in:standards", "opt-in:all")
# The OSPS Baseline release an entry's `baseline` ids come from;
# tests/floor-check-registry.sh holds every id to that release's list.
OSPS_BASELINE = "v2026.08.28"
DOCS = "skills/floor-check/reference.md"


def check(cid: str, name: str, *, states: tuple[str, ...], handoff: str, fix: str, docs: str,
          messages: dict[str, str], hosts: tuple[str, ...] = HOSTS, archetypes: tuple[str, ...] | None = None,
          needs: tuple[str, ...] = ("files",), lifecycle: str = "stable", aliases: tuple[str, ...] = (),
          unreached: dict[str, str] | None = None, area: str | None = None, not_keepable: str | None = None,
          baseline: tuple[str, ...] = (), view: str = "report", ci_visible: bool = True,
          view_why: str | None = None) -> dict:
    """One REGISTRY entry. `archetypes` None is every archetype; `unreached`
    names, for a declared state no fixture of tests/floor-check-cases.sh
    reaches, why not. `area` is the id's letter unless the check moved.
    `not_keepable` says why .plinth-adoption.yml may not keep this finding
    (#1112); every other entry is keepable. `baseline` names the OSPS
    Baseline controls (OSPS_BASELINE) the check reads. `view` other than
    `report` says why in `view_why`; `ci_visible` is whether `ci /
    floor-check` prints it."""
    area = area or cid[3]
    assert re.fullmatch(r"FC-[A-Z]\d\d", cid) and cid[3] in AREAS and area in AREAS, cid
    assert states and set(states) <= set(STATES), (cid, states)
    assert handoff in HANDOFFS and lifecycle in LIFECYCLES and set(hosts) <= set(HOSTS) and set(needs) <= set(NEEDS), cid
    # An experimental check has not earned a FAIL: it may only warn.
    assert lifecycle == "stable" or "fail" not in states, cid
    assert set(unreached or {}) <= set(states), cid
    assert view in VIEWS and (view == "report") == (view_why is None), cid
    return {"id": cid, "name": name, "area": area, "hosts": hosts, "archetypes": archetypes, "needs": needs,
            "lifecycle": lifecycle, "states": states, "handoff": handoff, "fix": fix, "docs": docs,
            "messages": messages, "aliases": aliases, "unreached": unreached or {},
            "keepable": not_keepable is None, "not_keepable": not_keepable, "baseline": baseline,
            "view": view, "ci_visible": ci_visible, "view_why": view_why}


def _registry(*entries: dict) -> dict[str, dict]:
    reg: dict[str, dict] = {}
    for e in entries:
        assert e["id"] not in reg, e["id"]
        reg[e["id"]] = e
    aliases = [a for e in entries for a in e["aliases"]]
    assert len(aliases) == len(set(aliases)) and not set(aliases) & set(reg), "an alias names one retired id"
    return reg


STATIC = f"{DOCS}#what-the-static-checks-read-and-what-they-do-not"
GITLAB_DOCS = f"{DOCS}#a-gitlab-checkout"
TWO_WAY = ("pass", "fail")


def _documents() -> tuple[dict, ...]:
    """Area A: the documents and issue templates a repository carries."""
    top = tuple(check(cid, f"{doc} present", states=TWO_WAY, handoff="agent", docs=STATIC,
                      fix=f"add a {doc} that says what it is for; /plinth:new-project renders one",
                      messages={"good": f"{doc} present", "bad": f"{doc} missing or empty"},
                      baseline=("OSPS-LE-03.01",) if doc == "LICENSE" else ())
                for cid, doc in (("FC-A01", "LICENSE"), ("FC-A02", "README.md"), ("FC-A03", "CHANGELOG.md"),
                                 ("FC-A04", "AGENTS.md")))
    return top + (
        check("FC-A05", "CONTRIBUTING.md present", states=TWO_WAY, handoff="agent", docs=STATIC,
              fix="add a CONTRIBUTING.md with the build and test commands and how a change lands",
              baseline=("OSPS-GV-03.01",),
              messages={"good": "CONTRIBUTING.md present", "bad": "CONTRIBUTING.md missing"}),
        check("FC-A06", "CONTRIBUTING.md says how to build and test", states=TWO_WAY, handoff="agent", docs=STATIC,
              fix="write the commands that build and test the project in CONTRIBUTING.md", baseline=("OSPS-DO-07.01",),
              messages={"good": "CONTRIBUTING.md says how to build and test",
                        "bad": "CONTRIBUTING.md has no build or test command"}),
        check("FC-A07", "CONTRIBUTING.md says how to land a change", states=TWO_WAY, handoff="agent", docs=STATIC,
              fix="say in CONTRIBUTING.md how a change lands: a pull request, its review and its merge",
              messages={"good": "CONTRIBUTING.md says how to land a change",
                        "bad": "CONTRIBUTING.md has no pull request flow"}),
        check("FC-A08", "CONTRIBUTING.md is not a stub", states=TWO_WAY, handoff="agent", docs=STATIC,
              fix="write CONTRIBUTING.md out: at least ten lines a contributor can follow",
              messages={"good": "CONTRIBUTING.md is not a stub ({lines} lines)",
                        "bad": "CONTRIBUTING.md looks like a stub ({lines} lines)"}),
        check("FC-A09", "SECURITY.md present or inherited", states=("pass", "fail", "unknown"), handoff="agent",
              docs=STATIC, needs=("files", "network"), baseline=("OSPS-VM-02.01",),
              fix="add a SECURITY.md that says how to report a vulnerability, or one in the owner's .github repository",
              messages={"local": "SECURITY.md present",
                        "inherited": "SECURITY.md inherited from the owner's .github repository",
                        "gitlab": "SECURITY.md missing: on GitLab nothing is inherited from an owner's .github repository",
                        "absent": "SECURITY.md neither local nor in the owner's .github repository",
                        "unread": "SECURITY.md not local; inheritance not verified (offline or API error)"}),
        check("FC-A10", "issue templates present or inherited", states=("pass", "fail", "unknown"), handoff="agent",
              docs=STATIC, hosts=("github",), needs=("files", "network"),
              fix="add issue forms under .github/ISSUE_TEMPLATE/ (bug, feature, task), or in the owner's .github repository",
              messages={"good": "issue templates found ({where}): {names}",
                        "bad": "no issue template ({where}): every issue arrives in whatever shape its writer chose",
                        "absent": "issue forms neither local nor in the owner's .github repository",
                        "unread": "issue forms not local; inheritance not verified (offline or API error)",
                        "content": "inherited forms not verified (content unreadable): {names}"}),
        check("FC-A11", "a local ISSUE_TEMPLATE replaces the owner's set", states=("info",), handoff="person",
              docs=STATIC, hosts=("github",), fix="",
              messages={"info": "a local ISSUE_TEMPLATE replaces the owner's shared set; GitHub does not merge them"}),
        check("FC-A12", "a Markdown issue template has a name", states=("pass", "warn"), handoff="agent",
              docs=STATIC, hosts=("github",), needs=("files", "network"),
              fix="give the template front matter with a `name:` value",
              messages={"good": "{name} has Markdown front matter with a name",
                        "bad": "{name} has no front matter `name:` with a value: GitHub does not offer it as a template"}),
        check("FC-A13", "an issue form has name, description and body", states=("pass", "fail", "warn"),
              handoff="agent", docs=STATIC, hosts=("github",), needs=("files", "network"),
              fix="add the missing top-level keys to the form",
              messages={"good": "{name} has name, description, body", "bad": "{name} lacks {keys}"}),
        check("FC-A14", "an issue form has no unquoted YAML alias", states=("pass", "fail", "warn"), handoff="agent",
              docs=STATIC, hosts=("github",), needs=("files", "network"),
              fix="quote the value that starts with * or &",
              messages={"good": "{name} has no unquoted YAML alias",
                        "bad": "{name} line {lines}: value starts with * or &"}),
        check("FC-A15", "an issue form labels its issues", states=("pass", "fail", "warn"), handoff="agent",
              docs=STATIC, hosts=("github",), needs=("files", "network"),
              fix="add `labels:` with the label the issue sorts under",
              messages={"good": "{name} labels its issues",
                        "bad": "{name} has no labels: those issues never sort in a list"}),
        check("FC-A16", "an issue form's body is a list", states=("pass", "warn"), handoff="agent", docs=STATIC,
              hosts=("github",), needs=("files", "network"),
              fix="make `body:` a list of form elements",
              messages={"good": "{name} body is a list",
                        "bad": "{name} body is not a list: GitHub rejects a form whose body is not a sequence"}),
        check("FC-A17", "at least one issue template GitHub can offer", states=TWO_WAY, handoff="agent", docs=STATIC,
              hosts=("github",), needs=("files", "network"),
              fix="fix one template so GitHub offers it: the per-file lines above say what each lacks",
              messages={"good": "at least one template GitHub can offer ({where})",
                        "bad": "no usable issue template ({where}): every file found is missing what GitHub needs to offer it"}),
        check("FC-A18", "Dependabot configured", states=TWO_WAY, handoff="agent", docs=STATIC, hosts=("github",),
              fix="add .github/dependabot.yml for the project's ecosystems and its GitHub Actions",
              messages={"good": ".github/dependabot.yml present", "bad": ".github/dependabot.yml missing: pins age silently"}),
        check("FC-A19", "Dependabot does not run on GitLab", states=("info",), handoff="person", docs=GITLAB_DOCS,
              hosts=("gitlab",), fix="",
              messages={"info": "Dependabot does not run on GitLab: nothing raises the plinth include or uv.lock's "
                                "pins for you; `deps` scans uv.lock on each merge request"}),
        check("FC-A20", "GitLab issue templates present", states=TWO_WAY, handoff="agent", docs=GITLAB_DOCS,
              hosts=("gitlab",), fix="add issue templates under .gitlab/issue_templates/",
              messages={"good": "issue templates found (.gitlab/issue_templates): {names}",
                        "bad": "no issue template under .gitlab/issue_templates/: every issue arrives in whatever "
                               "shape its writer chose"}),
        check("FC-A21", "GitLab merge request templates present", states=TWO_WAY, handoff="agent", docs=GITLAB_DOCS,
              hosts=("gitlab",), fix="add a merge request template under .gitlab/merge_request_templates/",
              messages={"good": "merge request templates found (.gitlab/merge_request_templates): {names}",
                        "bad": "no merge request template under .gitlab/merge_request_templates/: the squash commit "
                               "is made from whatever description the merge request has"}),
        check("FC-A22", "a GitLab issue template labels its issues", states=("pass", "warn"), handoff="agent",
              docs=GITLAB_DOCS, hosts=("gitlab",), fix="add a `/label ~name` line to the template",
              messages={"good": "{name} labels its issues",
                        "bad": "{name} has no `/label ~name` line: those issues never sort in a list"}),
        check("FC-A23", ".gitattributes present", states=TWO_WAY, handoff="agent", docs=STATIC,
              fix="add a .gitattributes; plinth-template's normalises line endings and folds lockfiles",
              messages={"good": ".gitattributes present", "bad": ".gitattributes missing"}),
        check("FC-A24", ".gitattributes normalises line endings", states=TWO_WAY, handoff="agent", docs=STATIC,
              fix="add `* text=auto` to .gitattributes",
              messages={"good": ".gitattributes normalises line endings (* text=auto)",
                        "bad": ".gitattributes does not normalise line endings"}),
        check("FC-A25", ".gitattributes folds uv.lock in diffs", states=TWO_WAY, handoff="agent", docs=STATIC,
              fix="add `uv.lock linguist-generated` to .gitattributes",
              messages={"good": ".gitattributes folds uv.lock in diffs (linguist-generated)",
                        "bad": "uv.lock is not marked linguist-generated: review reads machine-written lines"}),
        check("FC-A26", ".gitattributes needs no local git config", states=TWO_WAY, handoff="agent", docs=STATIC,
              fix="remove the diff=, merge= or filter= driver that only works with each user's local git config",
              messages={"good": ".gitattributes has no rule that needs local git config",
                        "bad": ".gitattributes rules need local git config: {rules}"}),
        check("FC-A27", "relative links in the Markdown documents resolve", states=TWO_WAY, handoff="agent",
              docs=STATIC, fix="point each broken link at a file that exists, or remove it",
              messages={"good": "relative links in {count} markdown files resolve", "bad": "{why}",
                        "none": "no markdown document found at all"}),
        check("FC-A28", "no dotenv file is tracked", states=("pass", "warn", "unknown", "info"), handoff="agent",
              docs=STATIC, needs=("files", "git"), baseline=("OSPS-BR-07.01",),
              not_keepable="a tracked secret reaches everyone who can read the repository, and stays in its history",
              fix="untrack the file and ignore it in .gitignore; rotate a value that was ever real",
              messages={"good": "no dotenv file is tracked ({count} tracked files read; names only, not contents or history)",
                        "bad": "tracked dotenv file: {file}",
                        "untrack": "  git rm --cached -- {quoted}   (ignore it in .gitignore; a value that was ever "
                                   "real is rotated, not only untracked)",
                        "unread": "tracked dotenv files not verified (git could not list the tracked files of --root)"}),
    )


AGENT_DOCS = f"{DOCS}#what-the-static-checks-read-and-what-they-do-not"
# What .claude/settings.json's permissions.deny is read for, one check each:
# (id, what, hosts). The rules that match each are check_agent_settings'.
AGENT_DENIES = (
    ("FC-B04", "rm -rf", HOSTS), ("FC-B05", "gh auth token", ("github",)), ("FC-B06", ".env reads", HOSTS),
    ("FC-B07", "`. ./.env`", HOSTS), ("FC-B08", "`source .env`", HOSTS), ("FC-B09", "`cat .env`", HOSTS),
    ("FC-B10", "`grep KEY .env`", HOSTS), ("FC-B11", "gh config reads", ("github",)),
    ("FC-B12", "glab auth status --show-token", ("gitlab",)), ("FC-B13", "glab auth status -t", ("gitlab",)),
    ("FC-B14", "glab config get token", ("gitlab",)), ("FC-B15", "glab config reads", ("gitlab",)),
)


def _agent() -> tuple[dict, ...]:
    """Area B: what the repository's agent settings stop an agent doing."""
    return (
        check("FC-B01", ".claude/settings.json present", states=TWO_WAY, handoff="agent", docs=AGENT_DOCS,
              fix="add .claude/settings.json with plinth-template's permissions.deny",
              messages={"good": ".claude/settings.json present", "bad": ".claude/settings.json missing"}),
        check("FC-B02", ".claude/settings.json is valid JSON", states=("fail",), handoff="agent", docs=AGENT_DOCS,
              fix="make .claude/settings.json valid JSON",
              messages={"bad": ".claude/settings.json is not valid JSON"}),
        check("FC-B03", ".claude/settings.json denies force push", states=("pass", "fail", "warn", "info"),
              handoff="agent", docs=AGENT_DOCS,
              fix="add plinth-template's force-push rules to permissions.deny; /plinth:template-update brings them",
              messages={"good": ".claude/settings.json denies force push: {denied}",
                        "bad": ".claude/settings.json does not deny force push",
                        "partly": ".claude/settings.json denies force push only as {denied}; not {missing}",
                        "add": "  add to permissions.deny: {rules}   (plinth-template's rules; an existing project "
                               "gets them from /plinth:template-update)"}),
        *(check(cid, f".claude/settings.json denies {what}", states=TWO_WAY, handoff="agent", docs=AGENT_DOCS,
                hosts=hosts, fix=f"add a permissions.deny rule that stops {what}",
                messages={"good": f".claude/settings.json denies {what}",
                          "bad": f".claude/settings.json does not deny {what}"})
          for cid, what, hosts in AGENT_DENIES),
    )


PROJECT_DOCS = f"{DOCS}#what-the-static-checks-read-and-what-they-do-not"
# The archetypes come from the constants the run reads, never a list written
# here: the template owns the vocabulary (tests/archetype-single-source.sh).
SERVICES = CONDITIONAL_ARCHETYPES
RELEASING = tuple(RELEASES)
RENDER_FIX = "the fix line under this item says what to set"


def _project() -> tuple[dict, ...]:
    """Area C: the project --project points at, by its archetype."""
    two = ("pass", "fail")
    return (
        check("FC-C01", "pyproject.toml present", states=("pass", "fail", "info"), handoff="agent", docs=PROJECT_DOCS,
              fix="add a pyproject.toml, or run again with --project=<the directory that has one>",
              baseline=("OSPS-QA-02.01",),
              messages={"good": "pyproject.toml present", "bad": "pyproject.toml missing",
                        "found": "pyproject.toml missing here; found {one}/pyproject.toml: run again with {flag}",
                        "below": "  pyproject.toml below the root in {dirs}: run again with --project=<one of them>"}),
        check("FC-C02", "uv.lock committed", states=two, handoff="agent", docs=PROJECT_DOCS,
              fix="run `uv lock` and commit uv.lock",
              messages={"good": "uv.lock committed", "bad": "uv.lock missing: CI runs `uv sync --locked`",
                        "found": "uv.lock missing here; found {one}/uv.lock: run again with {flag}",
                        "below": "{one}/uv.lock missing: CI runs `uv sync --locked`"}),
        check("FC-C03", "the archetype is known", states=("unknown", "info"), handoff="person", docs=PROJECT_DOCS,
              fix="pass --archetype, or keep .copier-answers.yml",
              messages={"none": "no archetype (no .copier-answers.yml, no --archetype); conditional items skipped",
                        "plain": "archetype {archetype}: no container image, .env.example or JSON logs required",
                        "service": "archetype {archetype}: container image, .env.example and JSON logs required{render}"}),
        check("FC-C04", "read as a JavaScript or TypeScript project", states=("info",), handoff="person",
              docs=PROJECT_DOCS, hosts=("github",), fix="",
              messages={"info": "read as a JavaScript or TypeScript project (package.json here, no pyproject.toml): "
                                "plinth has no checks for its language, so no lint, typecheck, test or build check; "
                                "the checks that do not depend on the language still apply: the documents, "
                                ".claude/settings.json, .gitattributes, Dependabot, tracked .env files, action pins "
                                "and, with a repository name, the ruleset, push protection and CodeQL"}),
        check("FC-C05", "the Python items do not apply to a JavaScript project", states=("not_applicable",),
              handoff="person", docs=PROJECT_DOCS, hosts=("github",), fix="",
              messages={"pyproject": "pyproject.toml does not apply: it describes a Python project, and this one is "
                                     "described by package.json",
                        "uvlock": "uv.lock does not apply: it is the lockfile of uv, Python's package manager; "
                                  "this project's own lockfile is not checked",
                        "service": "the container image, .env.example and JSON logs items: does not apply: they "
                                   "belong to plinth's Python archetypes, which check a Python image and Python source"}),
        check("FC-C06", "a Bun lockfile is not the only lockfile", states=("info",), handoff="agent",
              docs=PROJECT_DOCS, hosts=("github",), fix="commit an npm, yarn or pnpm lockfile beside it",
              messages={"info": "{name} is the only lockfile here: GitHub's dependency review does not read it, "
                                "so a vulnerable dependency is not reported before a merge"}),
        check("FC-C07", "MODEL_CARD.md present", states=("pass", "warn", "info"), handoff="agent", docs=PROJECT_DOCS,
              archetypes=("data-ml",), fix="copier update, which adds MODEL_CARD.md with the training run",
              messages={"good": "MODEL_CARD.md present",
                        "bad": "MODEL_CARD.md missing: a release publishes the model without saying what it was trained on",
                        "update": "  plinth-template {since} adds it with the training run: copier update"}),
        check("FC-C08", "the release workflow present", states=("pass", "warn", "info"), handoff="agent",
              docs=PROJECT_DOCS, archetypes=RELEASING,
              fix="copier update, then follow docs/how-to/publish-a-release.md",
              messages={"good": "{workflow} present",
                        "bad": "{workflow} missing: a version tag does not publish {what}",
                        "update": "  plinth-template {since} adds it, with its steps in docs/how-to/publish-a-release.md: "
                                  "copier update, then follow that page",
                        "gitlab": "{workflow} not required: on GitLab the template renders no release workflow"}),
        check("FC-C09", "the release workflow runs on a pushed tag only", states=("pass", "warn"), handoff="agent",
              docs=PROJECT_DOCS, hosts=("github",), archetypes=RELEASING,
              fix="make `on:` a push of tags and nothing else",
              messages={"good": "{workflow} runs on a pushed tag only",
                        "bad": "{workflow} is not read as tag-only (first line not read: {seen}): "
                               "a branch push or a pull request could publish"}),
        check("FC-C10", "the release workflow reads no stored secret", states=("pass", "warn"), handoff="agent",
              docs=PROJECT_DOCS, hosts=("github",), archetypes=RELEASING,
              fix="publish with the run's own token or Trusted Publishing, and delete the stored secret",
              messages={"good": "{workflow} reads no stored secret",
                        "bad": "{workflow} reads a stored secret ({secrets}): {instead}, and a stored token can be "
                               "copied and used from anywhere"}),
        check("FC-C11", "the release uploads no pickle", states=("pass", "warn", "unknown"), handoff="agent",
              docs=PROJECT_DOCS, hosts=("github",), archetypes=("data-ml",),
              fix="save the model with skops, safetensors or ONNX",
              messages={"good": "{workflow} uploads no pickle (ASSETS: {assets})",
                        "bad": "{workflow} uploads a pickle ({pickles}): loading one runs whatever code it holds; "
                               "save the model with skops, safetensors or ONNX",
                        "none": "{workflow}: no ASSETS line this checker reads; uploaded files not verified",
                        "form": "{workflow}: ASSETS is not a one-line list of file names this checker reads "
                                "(ASSETS: {assets}); uploaded files not verified"}),
        check("FC-C12", "render.yaml present", states=("pass", "fail", "info"), handoff="agent", docs=PROJECT_DOCS,
              archetypes=("web", "dashboard"), fix="git restore --source=origin/main -- render.yaml",
              messages={"good": "render.yaml present",
                        "bad": "render.yaml missing: the web archetype deploys from it, after the checks pass",
                        "dashboard": "render.yaml missing: a dashboard with hosting: render deploys from it, "
                                     "after the checks pass",
                        "restore": "  restore it from the default branch: git restore --source=origin/main -- render.yaml"}),
        check("FC-C13", "render.yaml is read", states=("unknown",), handoff="person", docs=PROJECT_DOCS,
              fix="write render.yaml in the block form plinth-template's is in",
              messages={"form": "render.yaml not read ({why}, a form this checker does not read): "
                                "health check, deploy trigger, database plan and secret values not verified",
                        "mapping": "render.yaml not read (it is not a mapping): "
                                   "health check, deploy trigger, database plan and secret values not verified",
                        "layout": "render.yaml not read (its {keys} layout is not one this checker reads): "
                                  "health check, deploy trigger, database plan and secret values not verified"}),
        check("FC-C14", "a Render web service has a health check", states=("pass", "warn", "info"), handoff="agent",
              docs=PROJECT_DOCS, fix=RENDER_FIX,
              messages={"good": "render.yaml: web service {svc} has a health check (healthCheckPath: {path})",
                        "bad": "render.yaml: web service {svc} has no healthCheckPath: Render sends traffic to a "
                               "new deploy without asking it whether it started",
                        "add": "  add healthCheckPath: /healthz to the service (the template's route that answers "
                               "without touching the database)",
                        "none": "render.yaml declares no web service: health check and deploy trigger not read"}),
        check("FC-C15", "a Render web service deploys after the checks pass", states=("pass", "warn", "info"),
              handoff="agent", docs=PROJECT_DOCS, fix=RENDER_FIX,
              messages={"good": "render.yaml: web service {svc} deploys only after the checks pass "
                                "(autoDeployTrigger: checksPass)",
                        "bad": "render.yaml: web service {svc} deploys without waiting for the checks ({said})",
                        "add": "  set autoDeployTrigger: checksPass on the service"}),
        check("FC-C16", "a Render database is on a paid plan", states=("pass", "warn", "info"), handoff="person",
              docs=PROJECT_DOCS, fix=RENDER_FIX,
              messages={"good": "render.yaml: database {db} is on a paid plan ({plan})",
                        "bad": "render.yaml: database {db} {said}: Render deletes a free Postgres after 30 days, "
                               "and it has no backups",
                        "add": "  set plan: to a paid one, as the template's plan: 0.1c-256mb (about US $6 a month)"}),
        check("FC-C17", "no secret-named Render variable carries a literal value", states=("pass", "warn", "info"),
              handoff="agent", docs=PROJECT_DOCS, fix=RENDER_FIX, baseline=("OSPS-BR-07.01",),
              not_keepable="a literal secret reaches everyone who can read the repository, and stays in its history",
              messages={"good": "render.yaml: no secret-named envVars entry carries a literal value",
                        "bad": "render.yaml: secret-named envVars set with a literal value ({keys}): "
                               "the value sits in the repository and in every clone of it",
                        "add": "  set each with sync: false (typed in Render's dashboard), generateValue: true or "
                               "fromDatabase instead, then change the exposed value where it is used",
                        "none": "render.yaml declares no envVars entries: secret values not read"}),
        check("FC-C18", "a web app hosted elsewhere", states=("info",), handoff="person", docs=PROJECT_DOCS,
              archetypes=("web",), fix="",
              messages={"info": "render.yaml not required: hosting is elsewhere ({place}), and only Render reads that file",
                        "self": "not checked by plinth: on {place}, HTTPS, backups and keeping the app's and the "
                                "database's ports closed are a person's to set up"}),
        check("FC-C19", "Dockerfile present", states=two, handoff="agent", docs=PROJECT_DOCS, archetypes=SERVICES,
              fix="add a Dockerfile; plinth-template's builds from uv.lock as a non-root user",
              messages={"good": "Dockerfile present", "bad": "Dockerfile missing"}),
        check("FC-C20", "every base image is pinned by digest", states=two, handoff="agent", docs=PROJECT_DOCS,
              archetypes=SERVICES, fix="pin each FROM image as name@sha256:<digest>",
              messages={"good": "every base image is pinned by digest",
                        "bad": "base images not pinned by digest: {unpinned}"}),
        check("FC-C21", "the image does not run as root", states=two, handoff="agent", docs=PROJECT_DOCS,
              archetypes=SERVICES, fix="end the Dockerfile with a USER that is not root",
              messages={"good": "the image does not run as root",
                        "bad": "the image runs as root (no USER, or the last USER is root)"}),
        check("FC-C22", "the image installs from the lockfile", states=two, handoff="agent", docs=PROJECT_DOCS,
              archetypes=SERVICES, fix="install with `uv sync --locked` in the Dockerfile",
              messages={"good": "the image installs from the lockfile (uv sync --locked)",
                        "bad": "the image does not use `uv sync --locked`: it can drift from the repository"}),
        check("FC-C23", "the image's CMD runs the package", states=two, handoff="agent", docs=PROJECT_DOCS,
              archetypes=SERVICES, fix="make CMD [\"python\", \"-m\", \"<package>\"] with src/<package>/__main__.py",
              messages={"good": "CMD runs python -m {pkg} and src/{pkg}/__main__.py exists",
                        "bad": "CMD {parts} does not run an existing module python -m {pkg}"}),
        check("FC-C24", ".dockerignore present", states=two, handoff="agent", docs=PROJECT_DOCS, archetypes=SERVICES,
              fix="add a .dockerignore that leaves out .git, .env and .venv",
              messages={"good": ".dockerignore present", "bad": ".dockerignore missing"}),
        check("FC-C25", ".dockerignore keeps .git, .env and .venv out", states=two, handoff="agent",
              docs=PROJECT_DOCS, archetypes=SERVICES, fix="add the missing names to .dockerignore",
              messages={"good": ".dockerignore keeps .git, .env, .venv out of the image",
                        "bad": ".dockerignore lacks {missing}: they ship inside the image"}),
        check("FC-C26", "the service logs JSON", states=("pass", "warn", "unknown", "info"), handoff="agent",
              docs=PROJECT_DOCS, archetypes=SERVICES,
              fix="give the root logger a handler whose formatter writes one JSON object per record",
              messages={"good": "JSON logs: static hint in {rel} ({label}); a hint in the source, not proof of what "
                                "the process prints",
                        "nosrc": "JSON logs not verified: no Python file under src/",
                        "unknown": "JSON logs not verified: {files} set up logging in a way this checker does not "
                                   "recognise (known: a logging.Formatter with json.dumps, structlog JSONRenderer, "
                                   "python-json-logger, loguru serialize=True)",
                        "bad": "JSON logs: no logging found under src/ (entry point {entry}): a container's "
                               "plain-text output is collected as unparsed lines",
                        "add": "  in {entry}, give the root logger a StreamHandler(sys.stdout) whose logging.Formatter "
                               "returns json.dumps(...) per record"}),
        check("FC-C27", ".env.example present", states=two, handoff="agent", docs=PROJECT_DOCS, archetypes=SERVICES,
              fix="add a .env.example naming each variable the code reads, with no real value",
              messages={"good": ".env.example present", "bad": ".env.example missing"}),
        check("FC-C28", ".env.example documents every variable the code reads", states=two, handoff="agent",
              docs=PROJECT_DOCS, archetypes=SERVICES, fix="add the missing names to .env.example",
              messages={"good": ".env.example documents every variable the code reads",
                        "bad": ".env.example is missing variables the code reads: {missing}"}),
    )


CI_DOCS = f"{DOCS}#what-the-static-checks-read-and-what-they-do-not"


def _ci() -> tuple[dict, ...]:
    """Area D: the ci job, what it calls and passes, and the pins in the workflows."""
    gh = ("github",)
    caller_fix = "make the `ci` job call coolbress/plinth's python-ci.yml at a full commit SHA, as the template renders it"
    return (
        check("FC-D01", "every action is pinned to a commit", states=("pass", "warn", "unknown", "info"),
              handoff="agent", docs=CI_DOCS, hosts=gh,
              fix="pin each uses: to a full commit SHA, with the old ref as its comment",
              messages={"good": "every action in {count} workflow file{s} is pinned to a commit ({total} uses)",
                        "none": "no workflow file under .github/workflows: no action pin to check",
                        "bad": "{rel}: not pinned to a full commit SHA: {lines}",
                        "docker": "  {value}: pin the image by digest (docker://image@sha256:<digest>)",
                        "sha": "  gh api {path} --jq .sha   (then pin the uses: to that SHA, the old ref as its comment)",
                        "form": "  {value}: write it as owner/repo@<full commit SHA>",
                        "unread": "{rel}: action pins not verified: line {lines} mentions uses in a form this "
                                  "checker does not read"}),
        check("FC-D02", "the ci job calls plinth's python-ci.yml at a commit",
              states=("pass", "fail", "unknown", "info", "not_applicable"), handoff="agent", docs=CI_DOCS, hosts=gh,
              needs=("files", "network"), fix=caller_fix,
              messages={"repo": "the ci job on the default branch not verified: repos/{repo} could not be read",
                        "nofile": "no {rel} on the default branch of {repo}: no `ci` job calls {workflow}",
                        "notfile": "the ci job on the default branch not verified (the API did not return {rel} as a file)",
                        "nocheckout": "the ci job not verified: no {rel} in the checkout, and the default branch was "
                                      "not read ({why})",
                        "unread": "the ci job {where} not verified: {value}",
                        "missing": "{rel} {where}: {value}, so nothing calls {workflow} and plain jobs could report "
                                   "its check names",
                        "skippable": "the ci job {where} has {value}: only uses:, with:, secrets: and permissions: are "
                                     "allowed; another key can get it skipped, renamed or cut short while plain jobs "
                                     "report its check names",
                        "remove": "  remove {value} from the `ci` job",
                        "own": "the ci job {where} calls {value} ({repo} calls its own workflow by local path)",
                        "good": "the ci job {where} calls {value}",
                        "ref": "the ci job {where} calls {value}: not pinned to a full commit SHA, so what runs can "
                               "change without a pull request",
                        "other": "the ci job {where} calls {value}, not {workflow}",
                        "hint": "  {command}",
                        "js": "the ci job's call to {workflow} does not apply: that workflow runs Python's lint, "
                              "typecheck, test and build, which have nothing to run on here"}),
        check("FC-D03", "the ci job keeps max-diff-lines at or below plinth's default", states=("warn", "unknown"),
              handoff="agent", docs=CI_DOCS, hosts=gh, fix="remove max-diff-lines from the ci job's with:, or lower it",
              messages={"line": "the ci job {where} has a with: line this checker does not read: {line}; "
                                "max-diff-lines and deps-fail-on-severity not verified",
                        "value": "the ci job {where} passes {name}: its value is not read (an expression, or a form "
                                 "this checker does not read)",
                        "number": "the ci job {where} passes max-diff-lines: {value}: not read as a whole number",
                        "off": "the ci job {where} passes max-diff-lines: {value}: ci / diff-size measures and never "
                               "fails (plinth's default is {default})",
                        "above": "the ci job {where} passes max-diff-lines: {value}, above plinth's default of "
                                 "{default}: a larger diff passes ci / diff-size"}),
        check("FC-D04", "the ci job keeps deps-fail-on-severity at plinth's default or stricter",
              states=("warn", "unknown"), handoff="agent", docs=CI_DOCS, hosts=gh,
              fix="remove deps-fail-on-severity from the ci job's with:, or set it to high or lower",
              messages={"value": "the ci job {where} passes {name}: its value is not read (an expression, or a form "
                                 "this checker does not read)",
                        "critical": "the ci job {where} passes deps-fail-on-severity: {value}: a high-severity "
                                    "advisory passes ci / deps (plinth's default is {default})",
                        "severity": "the ci job {where} passes deps-fail-on-severity: {value}: not read as a severity"}),
        check("FC-D05", "a web project's ci job passes web: true", states=("pass", "fail", "info"), handoff="agent",
              docs=CI_DOCS, hosts=gh, archetypes=("web",), fix="add `web: true` under the ci job's with:",
              messages={"good": "the ci job {where} passes web: true, so ci / migrations and ci / deploy-check run",
                        "bad": "the ci job {where} has {seen}: on the web archetype ci / migrations and "
                               "ci / deploy-check then pass as \"does not apply\" while the ruleset requires them",
                        "add": "  add `web: true` under the ci job's with:, as plinth-template renders it"}),
        check("FC-D06", "ci.yml carries the image job", states=("pass", "fail"), handoff="agent", docs=CI_DOCS,
              hosts=gh, archetypes=CONDITIONAL_ARCHETYPES,
              fix="add the template's `image` job, which builds and runs the container, to ci.yml",
              messages={"good": "ci.yml carries the image job (docker build, docker run)",
                        "bad": "ci.yml has no `image` job that builds and runs the container; the ruleset requires "
                               "that check for this archetype"}),
        check("FC-D07", ".gitlab-ci.yml carries the docker-image job", states=("pass", "fail"), handoff="agent",
              docs=GITLAB_DOCS, hosts=("gitlab",), archetypes=CONDITIONAL_ARCHETYPES,
              fix="add the template's docker-image job, which builds and runs the container, to .gitlab-ci.yml",
              messages={"good": ".gitlab-ci.yml carries the {job} job (docker build, docker run)",
                        "bad": ".gitlab-ci.yml has no `{job}` job that builds and runs the container; this "
                               "archetype's floor has one"}),
        check("FC-D08", ".gitlab-ci.yml includes plinth's GitLab pipeline at a commit, with a checksum",
              states=("pass", "fail", "unknown"), handoff="agent", docs=GITLAB_DOCS, hosts=("gitlab",),
              needs=("files", "network"),
              fix="include plinth's gitlab/python-ci.yml at a full commit SHA with its integrity checksum, as the "
                  "template renders it",
              messages={"rule": "{msg}",
                        "norule": "{what} not verified: the rule in {pipeline}'s floor-check job could not be read",
                        "nopython": "{what} not verified: {why}",
                        "norun": "{what} not verified: the rule did not run ({error})",
                        "printed": "{what} not verified: the rule printed {line}",
                        "silent": "{what} not verified: the rule printed no verdict ({why})"}),
    )


WALL_DOCS = f"{DOCS}#the-ruleset-flags"
PUSH_DOCS = f"{DOCS}#push-protection"
ALLOWLIST_DOCS = f"{DOCS}#the-actions-allowlist-and-private-vulnerability-reporting"
BESIDE_DOCS = f"{DOCS}#what-the-door-sets-beside-the-wall-and-the-projects-own-answers"
PRIVATE_DOCS = f"{DOCS}#a-private-repository"
ALERTS_DOCS = f"{DOCS}#dependabot-alerts-secret-scanning-and-registry-tokens"
# The rule types the door's ruleset carries on the default branch, each its own check (#1103).
WALL_RULES = (("FC-E13", "deletion"), ("FC-E14", "non_fast_forward"), ("FC-E15", "pull_request"),
              ("FC-E16", "required_status_checks"))
WALL_IS_THE_RULES = "an unprotected default branch lets a push or merge reach everyone, and a pushed commit stays"


def _wall() -> tuple[dict, ...]:
    """Area E: the wall, the repository settings read live with --repo."""
    gh, gl = ("github",), ("gitlab",)
    net, admin = ("network",), ("network", "admin")
    rule_baseline = {"deletion": ("OSPS-AC-03.02",), "pull_request": ("OSPS-AC-03.01",),
                     "required_status_checks": ("OSPS-QA-03.01",)}
    return (
        check("FC-E01", "the GitLab default branch is protected", states=("pass", "fail", "unknown", "info"),
              handoff="admin", docs=GITLAB_DOCS, hosts=gl, needs=net, baseline=("OSPS-AC-03.01",),
              not_keepable=WALL_IS_THE_RULES,
              fix="protect the default branch: no one pushes, Maintainers merge, no force push",
              messages={"unread": "the GitLab wall of {repo} not verified: {why}",
                        "nobranch": "{repo} has no default branch GitLab names; its protection, merge checks and "
                                    "include not verified",
                        "norepo": "no --repo: wall not checked",
                        "offline": "--no-network: the GitLab wall not checked",
                        "rules": "the protection of {branch} not verified: protected branches are not readable with "
                                 "this login (it needs the Maintainer role on GitLab.com), or an API error",
                        "none": "{branch} is not a protected branch on {repo}: anyone with Developer can push to it",
                        "create": "  glab api --hostname {host} -X POST projects/{enc}/protected_branches -f "
                                  "name={branch} -F push_access_level=0 -F merge_access_level=40 -F "
                                  "allow_force_push=false   (a Maintainer)",
                        "weak": "{branch}'s protection on {repo} is weaker than the door's (rules that apply: "
                                "{names}): {bad}",
                        "edit": "  {edit}#js-protected-branches-settings   (each rule that matches {branch}: Allowed "
                                "to push and merge: No one; Allowed to merge: Maintainers; Allowed to force push: off)",
                        "good": "{branch} is protected on {repo}: no one pushes, Maintainers merge, no force push "
                                "(rules that apply: {names})"}),
        check("FC-E02", "a GitLab merge request merges only on a green pipeline",
              states=("pass", "fail", "unknown", "info"), handoff="admin", docs=GITLAB_DOCS, hosts=gl, needs=net,
              baseline=("OSPS-QA-03.01",), not_keepable=WALL_IS_THE_RULES,
              fix="turn on \"Pipelines must succeed\" and do not count skipped pipelines",
              messages={"bad": "the merge checks of {repo} let a merge request merge without a green pipeline: {off}",
                        "hint": "  glab api --hostname {host} -X PUT projects/{enc} -F "
                                "only_allow_merge_if_pipeline_succeeds=true -F allow_merge_on_skipped_pipeline=false"
                                "   (a Maintainer; or {url})",
                        "absent": "{fields} of {repo} not verified: GitLab did not return {them} to this login (a "
                                  "project member reads them)",
                        "good": "{repo} merges only on a green pipeline (\"Pipelines must succeed\" on, skipped "
                                "pipelines not counted)"}),
        check("FC-E03", "a GitLab merge request is squashed and fast-forwarded",
              states=("pass", "fail", "unknown", "info"), handoff="admin", docs=GITLAB_DOCS, hosts=gl, needs=net,
              not_keepable=WALL_IS_THE_RULES, fix="set squash to always and the merge method to fast-forward",
              messages={"bad": "{repo} merges other than squash and fast-forward: {off}; main gains commits that are "
                               "not one squash per merge request",
                        "hint": "  glab api --hostname {host} -X PUT projects/{enc} -f squash_option=always -f "
                                "merge_method=ff   (a Maintainer; or {url})",
                        "absent": "{fields} of {repo} not verified: GitLab did not return {them} to this login (a "
                                  "project member reads them)",
                        "good": "{repo} squashes every merge request and fast-forwards"}),
        check("FC-E04", "the default branch carries the GitLab pipeline definition", states=("fail", "unknown"),
              handoff="agent", docs=GITLAB_DOCS, hosts=gl, needs=net,
              fix="commit .gitlab-ci.yml, as the template renders it, to the default branch",
              messages={"outside": "the include on {branch} not verified: the pipeline definition is {cfg}, outside "
                                   "this project",
                        "absent": "no {cfg} on {branch} of {repo}: no pipeline runs, so \"Pipelines must succeed\" "
                                  "holds nothing back",
                        "error": "the include on {branch} not verified: {cfg} could not be read (an API error)"}),
        check("FC-E05", "every label the door creates is present", states=("pass", "warn", "unknown", "info"),
              handoff="agent", docs=WALL_DOCS, needs=net, fix="create each missing label, as the fix line says",
              messages={"nofile": "labels.txt not found next to the checker; labels not checked",
                        "unread": "labels not verified (offline, not logged in, or API error)",
                        "good": "every label the door creates is present ({count})",
                        "bad": "labels the door creates that are missing: {missing}",
                        "gh": "  gh label create {name} --repo {repo} --color {colour}",
                        "glab": "  glab label create --name {name} --color '#{colour}' --repo {repo}"}),
        check("FC-E06", "the repository is read for the wall", states=("fail", "unknown", "info"), handoff="person",
              docs=WALL_DOCS, hosts=gh, needs=net, fix="pass --repo owner/name, online, with a login that can read it",
              messages={"norepo": "no --repo: wall not checked",
                        "offline": "wall not checked (offline)",
                        "absent": "repos/{repo} not found (404)",
                        "error": "could not read repos/{repo} (API error)",
                        "expect": "wall expectation: checks {expected}, merge methods {methods}"}),
        check("FC-E07", "the default branch is main", states=("warn", "unknown", "info"), handoff="admin",
              docs=WALL_DOCS, hosts=gh, needs=net, fix="make main the default branch",
              messages={"nobranch": "default branch not verified (the API did not report one); reading the wall on main",
                        "where": "the wall is checked on {branch}, the repository's default branch",
                        "notmain": "the default branch is {branch}, not main: the rules below govern {branch}. "
                                   "If main is where the work happens, main is unprotected",
                        "hint": "  gh api repos/{repo} -X PATCH -f default_branch=main   (then run this again)"}),
        check("FC-E08", "squash commits carry the pull request title and description",
              states=("pass", "fail", "unknown", "review"), handoff="admin", docs=WALL_DOCS, hosts=gh, needs=net,
              fix="set the squash commit title to PR_TITLE and its message to PR_BODY",
              messages={"review": "squash commit settings not visible with this token; /plinth:floor-check reads them "
                                  "with a login that administers the repository",
                        "unread": "squash commit settings not visible with this token (a push-access token sees them)",
                        "good": "squash commits carry the pull request title and description",
                        "bad": "squash commit settings drifted: title={title}, message={msg} (expected PR_TITLE, "
                               "PR_BODY)"}),
        check("FC-E09", "push protection is on", states=("pass", "warn", "unknown", "review", "info"),
              handoff="admin", docs=PUSH_DOCS, hosts=gh, needs=admin, baseline=("OSPS-BR-07.01",),
              not_keepable="a pushed secret reaches everyone who can read the repository, and stays in its history",
              fix="turn on secret scanning and push protection",
              messages={"review": "push protection is not read here: the Actions token does not get the repository's "
                                  "security settings; /plinth:floor-check reads it with a person's login",
                        "plan": "push protection not verified (GitHub answers no security settings for this private "
                                "repository to a login that administers it, with a token that reads its Actions "
                                "permissions: GitHub Secret Protection (a paid product for Team and Enterprise) not "
                                "on its plan. In its place: `ci / secrets`, which finds a secret after the push)",
                        "token": "push protection not verified (GitHub answers no security settings for this private "
                                 "repository to a login that administers it, and this token was not shown to read an "
                                 "administration setting: a token without the Administration permission, or GitHub "
                                 "Secret Protection (a paid product for Team and Enterprise) not on its plan)",
                        "admin": "{line}",
                        "unread": "push protection not verified (this token does not read the repository's security "
                                  "settings; one with repository administration does)",
                        "good": "push protection is on: GitHub refuses a push that carries a secret in a format it "
                                "knows; anyone with write access can still push it past the block by giving a reason",
                        "gap": "push protection is not expected here: GitHub Secret Protection is not enabled on this "
                               "private repository (a paid product for Team and Enterprise), so a push that carries a "
                               "secret is not refused. In its place: `ci / secrets`, which finds a secret after the "
                               "push, when it has to be revoked. {turn_on}",
                        "nostatus": "push protection not verified (it is off, and GitHub reports no secret scanning "
                                    "status for this private repository: whether GitHub Secret Protection is enabled "
                                    "there was not read)",
                        "bad": "push protection is off: a push that carries a secret reaches GitHub, and "
                               "`ci / secrets` reports it only afterwards",
                        "hint": "  gh api -X PATCH repos/{repo} --input - <<<'{body}'   (needs repository "
                                "administration; on a private repository, GitHub Secret Protection too)",
                        "bypass": "  once on, anyone with write access can still push a secret past it by giving a "
                                  "reason, and GitHub records who and why",
                        "none": "push protection not verified (GitHub reports no push protection status for this "
                                "repository)"}),
        check("FC-E10", "SECURITY.md names a route this repository takes", states=("warn", "info"), handoff="agent",
              docs=ALLOWLIST_DOCS, hosts=gh, fix="re-render SECURITY.md with the repository's visibility",
              messages={"form": "SECURITY.md sends a reporter to Security → Report a vulnerability, which a private "
                                "repository is not offered: a report has nowhere to go",
                        "form_fix": "  re-render it with the issue route: copier update --defaults --data "
                                    "visibility=private (or /plinth:template-update with that answer), then commit "
                                    "SECURITY.md and .copier-answers.yml",
                        "issue": "SECURITY.md tells a reporter to open an issue, and this repository is public: the "
                                 "report is public too",
                        "issue_fix": "  re-render it with the form: copier update --defaults --data visibility=public, "
                                     "then turn private vulnerability reporting on"}),
        check("FC-E11", "private vulnerability reporting is on", states=("pass", "warn", "unknown", "review", "info"),
              handoff="admin", docs=ALLOWLIST_DOCS, hosts=gh, needs=admin, baseline=("OSPS-VM-03.01",),
              fix="turn private vulnerability reporting on",
              messages={"private": "private vulnerability reporting is not offered on a private repository",
                        "good": "private vulnerability reporting is on: SECURITY.md's Security → Report a "
                                "vulnerability works",
                        "bad": "private vulnerability reporting is off: SECURITY.md sends a reporter to Security → "
                               "Report a vulnerability, which this repository does not show",
                        "hint": "  gh api -X PUT repos/{repo}/private-vulnerability-reporting   (needs repository "
                                "administration)",
                        "review": "private vulnerability reporting is not read here: /plinth:floor-check reads it with "
                                  "a login that administers the repository",
                        "unread": "private vulnerability reporting not verified (GitHub gave no answer this checker "
                                  "reads; a login with repository administration reads it)"}),
        check("FC-E12", "rules govern the default branch", states=("fail", "unknown", "info"), handoff="admin",
              docs=WALL_DOCS, hosts=gh, needs=net, baseline=("OSPS-AC-03.01",), not_keepable=WALL_IS_THE_RULES,
              fix="apply the door's ruleset to the default branch",
              messages={"unread": "could not read the rules of {branch} (API error)",
                        "none": "no rules govern {branch}: the wall is down",
                        # .plinth-adoption.yml's wall_due (#1112): the adopt order puts the
                        # ruleset after the first green run on the default branch.
                        "later": "the wall: later, after the first green run on {branch} (until {due}, "
                                 ".plinth-adoption.yml's wall_due)"}),
        *(check(cid, f"the default branch has a {t} rule", states=TWO_WAY, handoff="admin", docs=WALL_DOCS,
                hosts=gh, needs=net, baseline=rule_baseline.get(t, ()), not_keepable=WALL_IS_THE_RULES,
                fix=f"add the {t} rule of the door's ruleset to the default branch",
                messages={"good": "{branch}: " + t + " rule active", "bad": "{branch}: " + t + " rule missing"})
          for cid, t in WALL_RULES),
        check("FC-E17", "merge methods stay within the ruleset's", states=TWO_WAY, handoff="admin", docs=WALL_DOCS,
              hosts=gh, needs=net, not_keepable=WALL_IS_THE_RULES,
              fix="set the pull_request rule's allowed merge methods to the ruleset's",
              messages={"good": "{branch}: merge methods within {allowed}",
                        "bad": "{branch}: merge methods widened to {methods}"}),
        check("FC-E18", "required checks are strict", states=TWO_WAY, handoff="admin", docs=WALL_DOCS, hosts=gh,
              needs=net, not_keepable=WALL_IS_THE_RULES,
              fix="require branches to be up to date before merging in the required-checks rule",
              messages={"good": "{branch}: required checks are strict (branch must be current)",
                        "bad": "{branch}: required checks are not strict"}),
        check("FC-E19", "every expected check is required",
              states=("pass", "fail", "unknown", "info", "not_applicable"), handoff="admin", docs=WALL_DOCS,
              hosts=gh, needs=net, baseline=("OSPS-QA-03.01",), not_keepable=WALL_IS_THE_RULES,
              fix="require the dropped checks again, as the fix line says",
              messages={"na": "{branch}: requiring {checks} does not apply: python-ci.yml runs those checks, and a "
                              "JavaScript or TypeScript repository does not call it",
                        "held": "{branch}: required check {check} not required yet: this checkout records the "
                                "{archetype} archetype, which runs it, and {branch} records {old}, which does not (an "
                                "archetype move). Once it is merged and {check} has run on {branch}, a person "
                                "requires it (repository administration): scripts/with-admin-token.sh "
                                "scripts/require-check.sh --repo {repo} '{check}'",
                        "good": "{branch}: all {count} expected checks are required",
                        "bad": "{branch}: required checks dropped: {missing}",
                        "hint": "  require them again (repository administration): scripts/with-admin-token.sh "
                                "scripts/upgrade-ruleset.sh {repo} {pairs}"}),
        check("FC-E20", "each required check comes from its expected app", states=("pass", "fail", "unknown", "info"),
              handoff="admin", docs=WALL_DOCS, hosts=gh, needs=net, not_keepable=WALL_IS_THE_RULES,
              fix="pin each required check to the app the door's ruleset names",
              messages={"nocompare": "{branch}: the source of each required check is not compared (no --ruleset)",
                        "unknown": "{branch}: the expected app for required check {check} is not known (not pinned in "
                                   "--ruleset); its source is not compared",
                        "any": "{branch}: required check {check} accepts a status from any source (expected app "
                               "{want}); anyone with write access can satisfy it",
                        "other": "{branch}: required check {check} comes from app {got}, not {want}",
                        "good": "{branch}: required checks come from the expected {label} ({apps})"}),
        check("FC-E21", "CodeQL is enforced on the default branch",
              states=("pass", "fail", "unknown", "review", "info"), handoff="admin", docs=PRIVATE_DOCS, hosts=gh,
              needs=admin, baseline=("OSPS-VM-06.02",), not_keepable=WALL_IS_THE_RULES,
              fix="add the door's code_scanning rule for CodeQL (scripts/add-ruleset-rule.sh <repo> code-scanning)",
              messages={"good": "{branch}: CodeQL enforced ({how})",
                        "bad": "{branch}: CodeQL not enforced: no code_scanning rule for CodeQL and no CodeQL check "
                               "name",
                        "gap": "{branch}: CodeQL is not expected here: GitHub Code Security is not enabled on this "
                               "private repository (a paid product for Team and Enterprise), so no code_scanning rule "
                               "for CodeQL and no scan. In its place: `ci / lint`'s security rules. {turn_on}",
                        "review": "{branch}: CodeQL is not judged here: no code_scanning rule for CodeQL and no CodeQL "
                                  "check name, which on a private repository is a defect only where GitHub Code "
                                  "Security is enabled, and the Actions token does not get the repository's security "
                                  "settings. The licence state is judged when /plinth:floor-check is run with a login "
                                  "that administers the repository",
                        "plan": "{branch}: CodeQL not verified: no code_scanning rule for CodeQL and no CodeQL check "
                                "name, which on a private repository is a defect only where GitHub Code Security is "
                                "enabled (GitHub answers no security settings for this private repository to a login "
                                "that administers it, with a token that reads its Actions permissions: GitHub Code "
                                "Security (a paid product for Team and Enterprise) not on its plan. In its place: "
                                "`ci / lint`'s security rules)",
                        "token": "{branch}: CodeQL not verified: no code_scanning rule for CodeQL and no CodeQL check "
                                 "name, which on a private repository is a defect only where GitHub Code Security is "
                                 "enabled (GitHub answers no security settings for this private repository to a login "
                                 "that administers it, and this token was not shown to read an administration "
                                 "setting: a token without the Administration permission, or GitHub Code Security not "
                                 "on its plan)",
                        "admin": "{line}",
                        "unread": "{branch}: CodeQL not verified: no code_scanning rule for CodeQL and no CodeQL check "
                                  "name, which on a private repository is a defect only where GitHub Code Security is "
                                  "enabled ({why})"}),
        check("FC-E22", "CodeQL's alert thresholds are the ruleset's", states=("pass", "fail", "unknown", "info"),
              handoff="admin", docs=WALL_DOCS, hosts=gh, needs=net, baseline=("OSPS-VM-06.02",),
              not_keepable=WALL_IS_THE_RULES, fix="set the CodeQL rule's alert thresholds back to the ruleset's",
              messages={"nopolicy": "{branch}: CodeQL alert thresholds not compared (no --ruleset)",
                        "bad": "{branch}: CodeQL alert thresholds weakened: {weak}",
                        "edit": "  the rule is edited in https://github.com/{repo}/settings/rules/{rid}",
                        "unread": "{branch}: CodeQL alert thresholds not verified: {fields} unreadable",
                        "good": "{branch}: CodeQL alert thresholds {alerts} / {security} (expected {want_alerts} / "
                                "{want_security})",
                        "name": "{branch}: CodeQL alert thresholds not verified: a check name does not set them; the "
                                "door's code_scanning rule does (scripts/add-ruleset-rule.sh {repo} code-scanning)"}),
        check("FC-E23", "CodeQL default setup analyses the project's language",
              states=("pass", "warn", "unknown", "review", "info"), handoff="admin", docs=WALL_DOCS, hosts=gh,
              needs=admin, fix="add the project's language to CodeQL default setup",
              messages={"review": "CodeQL default setup languages not read here: the Actions token cannot read "
                                  "code-scanning/default-setup; /plinth:floor-check reads them with a login that "
                                  "administers the repository",
                        "plan": "CodeQL default setup languages not verified (code-scanning/default-setup gave no "
                                "answer on a private repository whose plan answers no security settings to its "
                                "administrator)",
                        "unread": "CodeQL default setup languages not verified (the token cannot read "
                                  "code-scanning/default-setup)",
                        "good": "CodeQL default setup analyses {langs}",
                        "bad": "CodeQL default setup analyses {langs}, not {code}",
                        "hint": "  gh api -X PATCH repos/{repo}/code-scanning/default-setup -f 'languages[]=actions' "
                                "-f 'languages[]={lang}'"}),
        check("FC-E24", "no ruleset has a bypass actor", states=("pass", "fail", "unknown", "review"),
              handoff="admin", docs=WALL_DOCS, hosts=gh, needs=admin, not_keepable=WALL_IS_THE_RULES,
              fix="remove the bypass actors from the ruleset",
              messages={"review": "ruleset {rid}: bypass actors not visible with this token; /plinth:floor-check "
                                  "reads them with a login that administers the repository",
                        "unread": "ruleset {rid}: bypass actors not visible with this token (an admin-read token sees "
                                  "them)",
                        "good": "ruleset {rid}: no bypass actors",
                        "bad": "ruleset {rid}: bypass actors present: {actors}"}),
        check("FC-E25", "a ruleset reserves the merge to the repository admin",
              states=("pass", "fail", "warn", "unknown", "review", "info"), handoff="admin", docs=WALL_DOCS,
              hosts=gh, needs=admin, not_keepable=WALL_IS_THE_RULES,
              fix="apply the door's merge ruleset (scripts/create-merge-ruleset.sh)",
              messages={"nocompare": "{branch}: the ruleset that reserves the merge to an admin is not compared (no "
                                     "--merge-ruleset)",
                        "outside": "{branch}: the merge ruleset not verified: the update rule comes from a ruleset "
                                   "outside this repository, whose bypass actors are not read here",
                        "unlisted": "{branch}: the merge ruleset not verified: no ruleset in effect carries update, "
                                    "and this repository's rulesets could not be listed",
                        "idle": "{branch}: the merge ruleset is not in effect: {idle}. Any account with write access "
                                "can merge; expected enforcement {enforcement} on {conditions}",
                        "missing": "{branch}: no ruleset reserves the merge to an admin: any account with write "
                                   "access, an agent's own account included, can merge a pull request",
                        "create": "  scripts/with-admin-token.sh scripts/create-merge-ruleset.sh {repo}   (from a "
                                  "plinth checkout)",
                        "types": "{branch}: ruleset {rid} carries {types}, not {want} alone: a bypass actor on it "
                                 "would reach every one of those rules",
                        "scope": "ruleset {rid}: the merge ruleset applies to {scope}, expected {want}",
                        "review": "ruleset {rid}: the merge ruleset's bypass actors not visible with this token; "
                                  "/plinth:floor-check reads them with a login that administers the repository",
                        "unread": "ruleset {rid}: the merge ruleset's bypass actors not visible with this token (an "
                                  "admin-read token sees them)",
                        "actors": "ruleset {rid}: the merge ruleset's bypass actors are {actors}, expected {want}",
                        "noscope": "ruleset {rid}: the merge ruleset's scope (target, enforcement, conditions) not read",
                        "good": "ruleset {rid}: the merge is reserved to the repository admin (update, the admin role "
                                "exempt)"}),
        check("FC-E26", "the merge is a boundary for this login", states=("pass", "unknown", "review", "info"),
              handoff="person", docs=WALL_DOCS, hosts=gh, needs=net,
              fix="leave no admin login where the agent can reach it",
              messages={"review": "the merge: not verified here: the Actions token is not the agent's login; "
                                  "/plinth:floor-check decides guidance or boundary with the login the agent inherits",
                        "role": "the merge: not verified: whether this login is the repository's admin could not be "
                                "read",
                        "readonly": "the merge: boundary. This login cannot write to the repository, so it cannot "
                                    "merge; you merge. It holds while no login with write access is left where the "
                                    "agent can reach it",
                        "write": "the merge: not verified: whether this login can write to the repository could not "
                                 "be read",
                        "admin": "the merge: guidance. This login is the repository's admin, and GitHub lets the admin "
                                 "merge, so an agent working under it can merge too; it is asked to wait for your "
                                 "word, not stopped",
                        "stands": "the merge: boundary. This login is not the repository's admin and the merge ruleset "
                                  "stands on {branch}, so GitHub refuses its merge; you merge, with the button or your "
                                  "own login. It holds while no admin login is left where the agent can reach it",
                        "never": "the merge: boundary. This login is not the repository's admin, and GitHub says it "
                                 "can never bypass the merge ruleset on {branch}, so GitHub refuses its merge. It "
                                 "holds while no admin login is left where the agent can reach it. Whether the admin "
                                 "is still exempt, so that your own merge goes through, is not read with this login: "
                                 "run /plinth:floor-check with yours",
                        "missing": "the merge: guidance. This login is not the repository's admin, but no ruleset "
                                   "reserves the merge to the admin, so it can merge; the WARN above adds that ruleset",
                        "norules": "the merge: guidance. This login is not the repository's admin, but no rules "
                                   "govern {branch}, so nothing reserves the merge to the admin and it can merge; the "
                                   "FAIL above is the wall to restore",
                        "unread": "the merge: not verified: this login is not the repository's admin, and the rules of "
                                  "{branch} could not be read, so whether a ruleset reserves the merge is not known",
                        "shape": "the merge: not verified: this login is not the repository's admin, but the merge "
                                 "ruleset above was not found in its shape"}),
        check("FC-E27", "the Actions allowlist lets every action the workflows use start",
              states=("pass", "warn", "unknown", "review", "info"), handoff="admin", docs=ALLOWLIST_DOCS, hosts=gh,
              needs=("files", "network", "admin"), fix="allow each refused action, as the fix line says",
              messages={"review": "the Actions allowlist is not read here: /plinth:floor-check reads it with a login "
                                  "that administers the repository",
                        "unread": "the Actions allowlist not verified (this token does not read the repository's "
                                  "Actions permissions; one with repository administration does)",
                        "off": "GitHub Actions is turned off on this repository: no workflow runs",
                        "docker": "{file}: line {line} {value}: whether the Actions allowlist lets an image run is not "
                                  "judged here",
                        "form": "{file}: the Actions allowlist not verified for line {lines}: it mentions uses in a "
                                "form this checker does not read",
                        "blocking": "the Actions allowlist not verified: it carries the blocking pattern{s} "
                                    "{patterns}, and GitHub documents no order between blocking and allowing patterns",
                        "good": "the Actions allowlist lets every action the workflows use start ({count} uses)",
                        "bad": "the Actions allowlist refuses: {refused}. A run that uses one ends in startup_failure, "
                               "with no job and no message saying why",
                        "select": "  gh api -X PUT repos/{repo}/actions/permissions -F enabled=true -f "
                                  "allowed_actions=selected   (needs repository administration; then run this again "
                                  "for the allowlist)",
                        "allow": "  gh api -X PUT repos/{repo}/actions/permissions/selected-actions --input - "
                                 "<<<{body}   (needs repository administration)"}),
        check("FC-E28", "the Actions token reads only and cannot approve a pull request",
              states=("pass", "warn", "unknown", "review", "info"), handoff="admin", docs=BESIDE_DOCS, hosts=gh,
              needs=admin, baseline=("OSPS-AC-04.01",),
              fix="set default_workflow_permissions to read and can_approve_pull_request_reviews to false",
              messages={"review": "the Actions token's default permissions are not read here: /plinth:floor-check "
                                  "reads them with a login that administers the repository",
                        "unread": "the Actions token's default permissions not verified (this token does not read the "
                                  "repository's Actions settings; one with repository administration does)",
                        "good": "the Actions token reads only by default and cannot approve a pull request",
                        "bad": "the Actions settings: {off}",
                        "hint": "  gh api -X PUT repos/{repo}/actions/permissions/workflow -f "
                                "default_workflow_permissions=read -F can_approve_pull_request_reviews=false   (needs "
                                "repository administration)"}),
        check("FC-E29", "a tag ruleset keeps released tags from being moved or deleted",
              states=("pass", "warn", "unknown", "review", "info"), handoff="admin", docs=BESIDE_DOCS, hosts=gh,
              archetypes=RELEASING, needs=admin,
              not_keepable="a moved or deleted release tag changes what a release names for everyone who installs it",
              fix="add the door's tag ruleset, as the fix line says",
              messages={"good": "the tag ruleset keeps {tags} tags from being moved or deleted, with no bypass actor "
                                "(ruleset {rid})",
                        "review": "the tag ruleset (ruleset {rid}) covers {tags} tags, and its bypass actors are not "
                                  "read here: /plinth:floor-check reads them with a login that administers the "
                                  "repository",
                        "actors": "the tag ruleset (ruleset {rid}) covers {tags} tags, and its bypass actors are not "
                                  "read here: this token does not get them; one with repository administration does",
                        "unread": "the tag ruleset not verified: a tag ruleset is listed and could not be read",
                        "member": "{why}: [tool.plinth.release] own-tags in pyproject.toml releases {name} on {tags} "
                                  "tags, so anyone with write access can move or delete a released tag of it",
                        "bad": "{why}: for a {archetype}, which releases from a v* tag, anyone with write access can "
                               "move or delete a released tag",
                        "create": "  gh api -X POST repos/{repo}/rulesets --input - <<<{body}   (needs repository "
                                  "administration)",
                        "unlisted": "the tag ruleset not verified: this repository's rulesets could not be listed",
                        "members": "the tag ruleset for members released on their own tags not verified: "
                                   "[tool.plinth.release] own-tags in pyproject.toml could not be read here"}),
        check("FC-E35", "the approvals required match who can merge", states=("pass", "warn", "review", "info"),
              handoff="admin", docs=WALL_DOCS, hosts=gh, needs=net, lifecycle="experimental",
              fix="the two-person rules, or back to one: scripts/add-ruleset-rule.sh <repo> two-people or one-person",
              messages={"good": "{branch}: {required} required, and {people} can merge ({who})",
                        "none": "{branch}: {people} can merge ({who}) and no approval is required: nothing makes one "
                                "of them look at the other's change",
                        "alone": "{branch}: {required} required, and only {approvers} can give one that counts{how}: "
                                 "a pull request of theirs cannot merge, as an author cannot approve their own",
                        "teams": "{branch}: {required} required, with code owners' review on, and CODEOWNERS names "
                                 "{teams}, whose members are not read here: who can give an approval that counts is "
                                 "not counted",
                        "hint": "  scripts/with-admin-token.sh scripts/add-ruleset-rule.sh {repo} {preset}   (from a "
                                "plinth checkout; its docs/how-to/add-a-second-person.md says when)",
                        "review": "who can merge is not read here: /plinth:floor-check reads the collaborators with a "
                                  "login that administers the repository",
                        "unread": "{branch}: the approvals required are not compared with who can merge: the "
                                  "collaborators could not be read (that needs push access)",
                        "nobody": "{branch}: the approvals required are not compared with who can merge: no person "
                                  "with {role} access is among the collaborators read"}),
        check("FC-E30", "the repository has a description", states=("pass", "info"), handoff="admin",
              docs=BESIDE_DOCS, hosts=gh, needs=net, fix="set one with gh repo edit <repo> --description '<one line>'",
              messages={"good": "the repository has a description",
                        "none": "the repository has no description: GitHub's community profile counts one; set it "
                                "with gh repo edit {repo} --description '<one line>'"}),
        check("FC-E31", "Dependabot alerts are on, and none is open", states=("pass", "warn", "unknown", "review", "info"),
              handoff="admin", docs=ALERTS_DOCS, hosts=gh, needs=admin,
              fix="turn Dependabot alerts on, and fix or dismiss each open alert",
              messages={"good": "Dependabot alerts are on, and none is open",
                        "open": "{count} open Dependabot alert(s) ({severities}): a dependency this repository uses "
                                "has a published vulnerability",
                        "list": "  https://github.com/{repo}/security/dependabot lists them",
                        "off": "Dependabot alerts are off: GitHub does not say when a dependency this repository uses "
                               "has a published vulnerability",
                        "hint": "  gh api -X PUT repos/{repo}/vulnerability-alerts   (needs repository administration)",
                        "unread": "Dependabot alerts not verified ({what}: a token with the {permission} permission "
                                  "(read) reads it)",
                        "review": "Dependabot alerts are not read here: /plinth:floor-check reads them with a login "
                                  "that administers the repository"}),
        check("FC-E32", "Dependabot security updates are on", states=("pass", "warn", "unknown", "review", "info"),
              handoff="admin", docs=ALERTS_DOCS, hosts=gh, needs=admin,
              fix="turn Dependabot security updates on",
              messages={"good": "Dependabot security updates are on: Dependabot opens a pull request that moves a "
                                "vulnerable dependency to a fixed version",
                        "off": "Dependabot security updates are off: an open Dependabot alert gets no pull request "
                               "with the fix",
                        "paused": "Dependabot security updates are paused (GitHub pauses them after a run of pull "
                                  "requests nobody merges): an open alert gets no pull request with the fix",
                        "hint": "  gh api -X PUT repos/{repo}/automated-security-fixes   (needs repository "
                                "administration; it needs Dependabot alerts on)",
                        "unread": "Dependabot security updates not verified (no answer this checker reads: a token "
                                  "with the Administration permission (read) reads it)",
                        "review": "Dependabot security updates are not read here: /plinth:floor-check reads them with "
                                  "a login that administers the repository"}),
        check("FC-E33", "secret scanning is on, and no alert is open",
              states=("pass", "warn", "unknown", "review", "info"), handoff="admin", docs=ALERTS_DOCS, hosts=gh,
              needs=admin, baseline=("OSPS-BR-07.01",),
              not_keepable="an open alert is a secret on GitHub that everyone who can read the repository can use "
                           "until it is revoked",
              fix="turn secret scanning on; revoke each secret an open alert names, then close the alert",
              messages={"good": "secret scanning is on, and no alert is open",
                        "open": "{count} open secret scanning alert(s): {where}. Each is a secret on GitHub until "
                                "it is revoked at its provider; closing the alert does not revoke it",
                        "list": "  https://github.com/{repo}/security/secret-scanning lists them",
                        "off": "secret scanning is off: GitHub does not say when a secret in a format it knows is "
                               "in this repository",
                        "hint": "  gh api -X PATCH repos/{repo} --input - <<<'{body}'   (needs repository "
                                "administration)",
                        "gap": "secret scanning is not on this private repository: it needs GitHub Secret Protection, "
                               "a paid product for Team and Enterprise. In its place: `ci / secrets`. {turn_on}",
                        "unread": "secret scanning not verified ({what}: a token with the {permission} permission "
                                  "(read) reads it)",
                        "review": "secret scanning and its open alerts are not read here: /plinth:floor-check reads "
                                  "them with a login that administers the repository"}),
        check("FC-E34", "no registry token among the secrets while release.yml publishes through OIDC",
              states=("pass", "warn", "unknown", "review", "info"), handoff="person", docs=ALERTS_DOCS, hosts=gh,
              needs=admin, lifecycle="experimental",
              fix="delete the registry token secrets once the trusted publisher works",
              messages={"good": "release.yml publishes through OIDC, and no secret is named like a registry token",
                        "bad": "release.yml publishes through OIDC, and these secrets are named like a token for "
                               "that registry: {names}. A long-lived token is a second way to publish, and it never "
                               "expires on its own",
                        "hint": "  {line}   (once a release has published through OIDC and no other workflow "
                                "reads it)",
                        "unread": "the secret names not verified ({what}: a token with the {permission} permission "
                                  "(read) lists them; values are never read)",
                        "review": "the secret names are not read here: /plinth:floor-check lists them (names only) "
                                  "with a login that administers the repository"}),
    )


DRIFT_DOCS = f"{DOCS}#template-drift"
ADOPTION_DOCS = f"{DOCS}#the-adoption-record"


# The answers that rely on a file in the owner's .github repository, one
# check each: (id, answer, the file GitHub inherits).
OWNER_COPIES = (("FC-F05", "owner_has_code_of_conduct", "CODE_OF_CONDUCT.md"),
                ("FC-F08", "owner_has_pr_template", "PULL_REQUEST_TEMPLATE.md"))


def _plinth() -> tuple[dict, ...]:
    """Area F: plinth, the template this repository was made from, its recorded answers and its plinth pins."""
    gh = ("github",)
    net = ("files", "network")
    again = "  /plinth:template-update looks at the owner's .github again and passes what it finds"
    return (
        check("FC-F01", "the recorded template tag is the one plinth is tested with",
              states=("pass", "warn", "unknown", "info"), handoff="person", docs=DRIFT_DOCS, needs=net,
              fix="run /plinth:template-update to move the repository to the target tag",
              messages={"unread": "template drift not verified ({reason})",
                        "ahead": "template: the recorded tag {recorded} is ahead of {target}, the tag plinth is "
                                 "tested with",
                        "moved": "template: the recorded tag is the target tag ({target}), but {target} now names "
                                 "commit {now}, not {sha}, the commit plinth was tested with",
                        "good": "template: the recorded tag is the target tag ({target})",
                        "tag": "  not verified that {target} still names {sha}, the commit plinth was tested with "
                               "({why})",
                        "behindunread": "template: {recorded} is behind {target}, the tag plinth is tested with; the "
                                        "changed files could not be read ({why})",
                        "behind": "template: {recorded} is behind {target}, the tag plinth is tested with; changed in "
                                  "the template: {names}",
                        "own": "  the template's own change between the two tags, not this repository's diff: another "
                               "archetype, inherited forms or a hand-made edit can mean some of it was never rendered "
                               "here",
                        "file": "  {name}:",
                        "patch": "    {line}",
                        "nocmd": "  no update command: {why}",
                        "pins": "  the \"workflow pins disagree\" WARN below names each file and the line that makes "
                                "them one",
                        "line": "  {line}",
                        "movedcmd": "{line}",
                        "cmdtag": "  not verified that {target} still names {sha}, the commit plinth was tested with "
                                  "({why}); the template-update skill checks it before it runs this line:",
                        "raise": "  no update command until the plinth pin is raised to the one the target tag was "
                                 "tested with:",
                        "uncompared": "  the template-update skill stops before it runs this line until the two are "
                                      "compared"}),
        check("FC-F02", "this installed plinth targets the newest template tag", states=("warn", "info"),
              handoff="person", docs=DRIFT_DOCS, needs=net, ci_visible=False,
              fix="update the plinth plugin, then run /plinth:template-update",
              messages={"bad": "template: {head}",
                        "step": "  {step}",
                        "unreleased": "  {line}",
                        "unread": "template: {line}",
                        "note": "template: {note}"}),
        check("FC-F03", "third_party_review: true has its workflow", states=("pass", "warn", "info"),
              handoff="agent", docs=BESIDE_DOCS, hosts=gh,
              fix="bring back .github/workflows/third-party.yml, or record third_party_review: false",
              messages={"good": "third_party_review: true, and .github/workflows/third-party.yml is there",
                        "bad": "third_party_review: true, and .github/workflows/third-party.yml is missing: no pull "
                               "request gets the third-party / review check the project was made with",
                        "hint": "  bring it back from the commit that removed it (git log --diff-filter=D -- "
                                ".github/workflows/third-party.yml), or record third_party_review: false with "
                                "/plinth:template-update if the reviewer is no longer wanted"}),
        check("FC-F04", "code_of_conduct: true has its CODE_OF_CONDUCT.md", states=("pass", "warn", "info"),
              handoff="agent", docs=BESIDE_DOCS, fix="bring back CODE_OF_CONDUCT.md, or record code_of_conduct: false",
              messages={"good": "code_of_conduct: true, and CODE_OF_CONDUCT.md is there",
                        "bad": "code_of_conduct: true, and CODE_OF_CONDUCT.md is missing",
                        "hint": "  bring it back from the commit that removed it (git log --diff-filter=D -- "
                                "CODE_OF_CONDUCT.md), or record code_of_conduct: false with /plinth:template-update"}),
        *(check(cid, f"the owner's .github still publishes {name} (answered {key})",
              states=("pass", "warn", "unknown", "info"), handoff="person", docs=BESIDE_DOCS, hosts=gh, needs=net,
              fix="publish the file from a public <owner>/.github, or add the repository's own",
              messages={"own": "{name} is the repository's own, which applies in place of the owner's",
                        "norepo": "{key}: true; whether the owner's .github repository still publishes {name} not "
                                  "verified (no --repo)",
                        "visibility": "{key}: true; whether {owner}/.github is public not verified ({why}), and "
                                      "GitHub inherits only from a public one",
                        "private": "{key}: true, and {owner}/.github is private or gone: GitHub inherits {name} only "
                                   "from a public .github repository, so this repository has none in effect",
                        "again": again,
                        "good": "{key}: true, and the owner's .github repository publishes {name}",
                        "unread": "{key}: true; whether the owner's .github repository still publishes it not "
                                  "verified (offline or API error)",
                        "gone": "{key}: true, and the owner's .github repository no longer publishes {name}: this "
                                "repository has none in effect"})
          for cid, key, name in OWNER_COPIES),
        check("FC-F06", "every plinth workflow pin names one commit", states=("warn", "unknown", "info"),
              handoff="agent", docs=STATIC, hosts=gh,
              fix="move every plinth uses: to the SHA the ci job calls, as the fix line says",
              messages={"unread": "plinth workflow pins not compared: {where} mentions uses in a form this checker "
                                  "does not read, and could pin coolbress/plinth at another commit",
                        "bad": "{line}",
                        "one": "  set every {repo} uses: to the one commit the ci job should call",
                        "fix": "  {line}   (moves it to the SHA the ci job calls)"}),
        check("FC-F09", "the adoption record is read", states=("info", "fail"), handoff="person", docs=ADOPTION_DOCS,
              not_keepable="an adoption record that keeps itself could keep anything it names, unread",
              fix="write .plinth-adoption.yml in the form the reference describes, or take the entry out",
              messages={"read": "{file} read: step {step}, {kept} kept by choice{due}",
                        "capped": "{file}: wall_due {due} is more than {days} days after started {started}; read as "
                                  "{cap}",
                        "unreadable": "{file} cannot be read ({why}): nothing in it is applied",
                        "invalid": "{file} is not valid: {why}; nothing in it is applied",
                        "unknown_id": "{file} keeps {id}, which names no check: that entry is not applied",
                        "not_keepable": "{file} keeps {id}, which cannot be kept ({why}): it is reported as found",
                        "expired": "{file} kept {id} until {until}, which has passed: it is reported as found"}),
        check("FC-F07", "the recorded host is one this checker reads", states=("unknown",), handoff="person",
              docs=GITLAB_DOCS, fix="pass --host github or --host gitlab",
              messages={"other": ".copier-answers.yml says host: {host}, which this checker does not read; read as "
                                 "github (pass --host to choose)"}),
    )


MACHINE_DOCS = f"{DOCS}#the-machines-items-and-the-merge-line"
# What none_found() prints: finding nothing is not a pass.
NONE_FOUND = "{what}; no other credential found by these rules; best effort, see the guide's list"


def _machine() -> tuple[dict, ...]:
    """Area G: this machine, read only when the skill asks (--sandbox, --plugins, --credentials)."""
    m = ("machine",)
    creds = "--credentials runs it; it reads this machine's logins, variables and git configuration, not the repository"

    def machine(cid: str, name: str, **kw) -> dict:
        kw.setdefault("needs", m)
        kw.setdefault("view_why", creds)
        return check(cid, name, docs=MACHINE_DOCS, view="opt-in:machine", ci_visible=False, **kw)
    return (
        machine("FC-G01", "this machine's Claude Code sandbox setting", states=("unknown", "info"), handoff="person",
                view_why="--sandbox runs it; it reads this machine's Claude Code settings, not the repository",
                fix="read the measured lines before turning the sandbox on; nothing in the repository changes it",
                messages={"on": "sandbox.enabled is true in {path}",
                          "unset": "sandbox not verified: sandbox.enabled is not true in {conf}/settings.json or "
                                   "settings.local.json, and /sandbox (Claude Code 2.1.278) does not write it there, "
                                   "so this cannot tell on from off",
                          "off": "  off: a `bash -c`, a `$(head -1 .env)`, a `grep -r` that names no file, or a script "
                                 "that opens `.env` itself still reads it; the sandbox is what closes those",
                          "gh": "  on, macOS (measured on Claude Code 2.1.278): `gh` stops working, because the sandbox "
                                "enforces the floor's deny `Read(~/.config/gh/**)` against `gh` itself; its fix, mask "
                                "mode, is ignored in a repository's .claude/settings.json and on macOS blocks like deny "
                                "even from user settings, so no project setting fixes it: anthropics/claude-code#95135 "
                                "and anthropics/claude-code#67105 track it upstream",
                          "uvx": "  on, macOS: /plinth:new-project stops at `uvx --from copier copier`: ~/.cache/uv is "
                                 "not writable, and with UV_CACHE_DIR moved to a writable path uv panics reading the "
                                 "system proxy configuration",
                          "other": "  Linux, WSL2 and native Windows: not measured"}),
        machine("FC-G02", "each plugin from the plinth marketplace is at its pin", states=("warn", "unknown", "info"),
                handoff="person",
                view_why="--plugins runs it; it reads this machine's installed Claude Code plugins, not the repository",
                fix="run the claude plugin update line the WARN names",
                messages={"unread": "plugins not checked: {path} not read ({err})",
                          "shape": "plugins not checked: {path} is not in the shape read here (version 2 with a "
                                   "plugins map)",
                          "market": "plugins not checked: the plinth marketplace's copy and its marketplace.json not "
                                    "read through {path} ({err})",
                          "norecord": "{pid} not checked: no install record read",
                          "nopin": "{pid} ({where}) not checked: {how}",
                          "noinstall": "{pid} ({where}) not checked: its install records no full {how}",
                          "bad": "{pid} ({where}) is behind its pin: installed {how} {have}, the plinth marketplace "
                                 "pins {want}; its skills may report \"Path not found\". fix: {fix}",
                          "current": "at the plinth marketplace's pin: {names}",
                          "other": "plugins from another marketplace, outside what plinth compares: {names}"}),
        machine("FC-G03", "the agent's login lists no scope that changes the workflows",
                states=("warn", "unknown", "info"), handoff="person", needs=("machine", "gh"),
                fix="once the first pull request is merged, give the agent a token without the workflow scope",
                messages={"noactive": "the permissions of the agent's gh login not verified: `gh auth status --json "
                                      "hosts` could not be read or names no active github.com account",
                          "unread": "the permissions of the agent's gh login ({login}) not verified: the scopes `gh "
                                    "auth status` lists for it could not be read{aside}",
                          "none": "the permissions of the agent's gh login ({login}) not verified: `gh auth status` "
                                  "lists no scopes for it (a fine-grained token lists none){aside}",
                          "bad": "the agent's gh login ({login}) holds `workflow`: it can push a change to "
                                 "`.github/workflows/`, the checks included{aside}",
                          "hint": "  once the first pull request is merged, give the agent a token without it: "
                                  "docs/how-to/give-the-agent-a-token.md",
                          "good": "the agent's gh login ({login}) lists its scopes without `workflow`{aside}",
                          "glab": "the permissions of the agent's glab login not verified: glab's token scopes are "
                                  "not read here"}),
        machine("FC-G04", "no token variable is set in this environment", states=("warn", "info"), handoff="person",
                fix="remove the variable where it is set, then restart Claude Code",
                messages={"bad": "{var} is set in this environment: {cli}, and the git push it serves, use it before "
                                 "any stored login",
                          "hint": "  remove {var} where it is set (a shell startup file), then restart Claude Code"}),
        machine("FC-G05", "no variable moves the gh or git configuration read", states=("unknown",), handoff="agent",
                fix="unset the variable, then run the check again",
                messages={"set": "{var} is set: the gh or git configuration read without it was not read, and the "
                                 "agent can unset it"}),
        machine("FC-G06", "the CLI stores one login for the host", states=("warn", "unknown", "info"),
                handoff="person", needs=("machine", "gh"),
                fix="keep only the account that holds the agent's token; log out each of the others",
                messages={"glab": "the login glab stores for gitlab.com not verified: glab's configuration is not "
                                  "read here; `glab auth status --hostname gitlab.com` shows it",
                          "unread": "accounts stored in gh not verified: `gh auth status --json hosts` could not be "
                                    "read",
                          "many": "gh stores {n} accounts for github.com (active: {active}): each is one `gh auth "
                                  "switch` away",
                          "keep": "  keep only the account that holds the agent's token; log out each of the others:",
                          "logout": "  gh auth logout --hostname github.com --user {login}",
                          "beside": "gh stores 1 account for github.com ({login}) besides {vars}: unsetting the "
                                    "variable uses it",
                          "keepone": "  keep one: the agent's token stored in gh with the variable removed, or gh auth "
                                     "logout --hostname github.com --user {login}",
                          "none": NONE_FOUND}),
        machine("FC-G07", "git asks no credential helper but the CLI's for the host",
                states=("warn", "unknown", "info"), handoff="person", needs=("machine", "files"),
                fix="delete the other helper's entry for the host, then clear the list with an empty helper before "
                    "the CLI's",
                messages={"unread": "git credential helpers not verified: `git config` could not be read",
                          "url": "git config [{section} \"{shown}\"] not verified: its URL could not be parsed, so "
                                 "whether it applies to {name} is unknown",
                          "bad": "git has {n} credential helper{s} for {name} besides {cli}'s: {others} (`git config "
                                 "--show-origin --get-regexp 'credential.*helper'` shows where)",
                          "hint": "  one listed before {cli}'s, or any while {cli} has no login, answers the push; one "
                                  "listed after {cli}'s was seen storing the credential a push succeeded with. Delete "
                                  "its {name} entry, then clear the list with an empty `helper =` before {cli}'s under "
                                  "`[credential \"https://{name}\"]` in ~/.gitconfig",
                          "none": NONE_FOUND}),
        machine("FC-G08", "git config sends no Authorization header to the host", states=("warn",), handoff="person",
                needs=("machine", "files"), fix="remove the http.extraHeader entry that names the host",
                messages={"bad": "git config sends an Authorization header to {name} (http.extraHeader): `git config "
                                 "--show-origin --get-regexp extraheader` shows where"}),
        machine("FC-G09", "~/.netrc holds no login for the host", states=("warn", "unknown", "info"), handoff="person",
                fix="delete the host's entry (or the default one) from ~/.netrc",
                messages={"unread": "{netrc} not verified: it exists and could not be read",
                          "quote": "{netrc} not verified: a quoted token is not closed",
                          "shape": "{netrc} not verified: a token sequence this reader does not place (a stray word, "
                                   "a keyword without its value, or macdef)",
                          "bad": "{netrc} holds a login for {name} (or a default one): git over HTTPS uses it",
                          "none": NONE_FOUND}),
        machine("FC-G10", "the SSH keys that push", states=("unknown", "info"), handoff="person",
                fix="read the host's SSH key and deploy key settings; this machine cannot tell which keys push",
                messages={"github": "SSH keys not verified here: GitHub's Settings → SSH and GPG keys, and the "
                                    "repository's Deploy keys, say which keys push; see "
                                    "docs/how-to/give-the-agent-a-token.md",
                          "gitlab": "SSH keys not verified here: GitLab's Preferences → SSH Keys, and the project's "
                                    "Deploy keys, say which keys push",
                          "askpass": "  not read either: a program named by GIT_ASKPASS or core.askPass, a token saved "
                                     "in any other file"}),
        machine("FC-G11", "no production database URL is within the agent's reach",
                states=("warn", "unknown", "info"), handoff="person", needs=("machine", "files"),
                view_why="--credentials runs it; it reads this machine's environment and Claude Code settings beside "
                         "the repository's .env* files and .claude settings",
                not_keepable="a command run against a production database can change or delete its data, which "
                             "cannot be undone and reaches every user of it",
                fix="keep the production URL only in the host's settings and use a local database for work",
                messages={"bad": "a production database URL is within the agent's reach: {where}",
                          "hint": "  {fix}; {db}",
                          "unread": "{rel} not verified: it could not be read",
                          "json": "{shown} not verified: it could not be read as JSON",
                          "env": "{shown} not verified: its env is not an object",
                          "none": "no production database URL found in this environment, the repository's .env* "
                                  "files or the env of .claude/settings*.json (the repository's and the user's); best "
                                  "effort: shell profile files, other files and schemes other than postgres:// and "
                                  "postgresql:// are not read"}),
        machine("FC-G12", "no plugin from the plinth marketplace is one it no longer lists",
                states=("warn",), handoff="person",
                view_why="--plugins runs it; it reads this machine's installed Claude Code plugins, not the repository",
                fix="run the claude plugin uninstall line the WARN names",
                messages={"replaced": "{pid} ({where}) left the plinth marketplace in {left}, replaced by {replaced}; "
                                      "Claude Code reports it \"not found in marketplace\" until it is uninstalled. "
                                      "fix: {fix}",
                          "retired": "{pid} ({where}) left the plinth marketplace in {left}; Claude Code reports it "
                                     "\"not found in marketplace\" until it is uninstalled. fix: {fix}",
                          "gone": "{pid} ({where}) is not in the plinth marketplace; Claude Code reports it \"not "
                                  "found in marketplace\" until it is uninstalled. fix: {fix}"}),
    )


REGISTRY = _registry(
    *_documents(),
    *_agent(),
    *_project(),
    *_ci(),
    *_wall(),
    *_plinth(),
    *_machine(),
)

# The run, as emit() records it: one result per line printed, in order, and
# the --verdicts lines they make (tests/check-messages.sh reads the last one).
results: list[dict] = []
verdicts: list[str] = []
TRACE = os.environ.get("FLOOR_CHECK_TRACE")   # the tests: one `<id> <state>\t<printed line>` line per result
HERE = "cannot be read here"                   # an unknown no change to this machine or repository clears (#1002)
ADMIN_READER = "/plinth:floor-check with a login that administers the repository"   # who reads a review


def emit(cid: str, state: str, msg_key: str, values: dict | None = None, *,
         reason: str | None = None, reader: str | None = None) -> None:
    """Report one result of check `cid`: `state` one it declares, the message
    its entry's `msg_key` with `values` filled in. An unknown says why (`reason`; HERE marks one
    no change clears), a review who reads it (`reader`)."""
    e = REGISTRY[cid]
    assert state in e["states"], (cid, state)
    assert (state == "unknown") == (reason is not None), (cid, state, reason)
    assert (state == "review") == (reader is not None), (cid, state, reader)
    msg = e["messages"][msg_key].format(**(values or {}))
    k = kept.get(cid) if state in ("fail", "warn") else None
    # A finding the adoption record keeps (#1112) is said, as an INFO, and not counted.
    if k is not None:
        msg = f"kept by choice ({k['reason']}): {msg}"
    r = {"id": cid, "state": "info" if k else state, "msg": msg, "reason": reason, "reader": reader, "key": msg_key,
         "kept": None if k is None else {"reason": k["reason"], "why": k["why"], "path": k["path"],
                                         "until": k.get("until"), "was": state}}
    results.append(r)
    verdicts.extend(verdict_lines(r))
    line = render_text(r)
    if out_format == "text":
        print(line)
    if TRACE:
        with open(TRACE, "a", encoding="utf-8") as t:
            t.write(f"{cid} {'kept' if k else state}\t{line.splitlines()[0]}\n")


def verdict(cid: str, cond: bool, values: dict | None = None, bad: str = "fail") -> bool:
    """A two-way check: `good` when cond holds, else `bad` (fail, or warn)."""
    emit(cid, "pass" if cond else bad, "good" if cond else "bad", values)
    return cond


# --- Renderers: what the results print as -----------------------------------
def render_text(r: dict) -> str:
    """The report's line. A FAIL or WARN carries the next action where CI
    shows it; an unknown no change clears is marked as such."""
    kind = SHOWN[r["state"]]
    shown = f"{r['msg']}; {next_action}" if next_action and kind in ("FAIL", "WARN") else r["msg"]
    if r["reason"] == HERE:
        shown = f"{r['msg']} {UNREADABLE}"
    return f"  {kind:5} {shown}"


def render_summary(rs: list[dict]) -> str:
    """The last line: unknowns no change clears counted apart inside the not
    verified (#1002), reviews outside it (#303, #436), and what does not
    apply (#681)."""
    n = {s: sum(r["state"] == s for r in rs) for s in STATES}
    here = sum(r["reason"] == HERE for r in rs)
    return (f"-- {n['fail']} failed, {n['unknown']} not verified" + (f" ({here} cannot be read here)" if here else "")
            + (f", {n['review']} left to /plinth:floor-check" if n["review"] else "")
            + (f", {n['not_applicable']} do not apply" if n["not_applicable"] else ""))


def verdict_lines(r: dict) -> list[str]:
    """The --verdicts lines one result makes (#437), in the three forms of
    docs/reference/required-checks.md: a fail, an unknown, a review. They
    keep the message without the unreadable-here mark, so `ci / floor-check`
    reads the same."""
    if r["state"] == "fail":
        return [f"fail: {r['msg']}; {next_action}" if next_action else f"fail: {r['msg']}"]
    if r["state"] == "unknown":
        # The SKIP's own text says why; what reads it differs per item (an
        # admin login, the network, a file the door writes), so the line says
        # only what is true of all of them.
        msg, room = r["msg"], 300 - len("not yet confirmed: ") - len(SKIP_NEXT)
        return [f"not yet confirmed: {msg if len(msg) <= room else msg[:room - 3] + '...'}{SKIP_NEXT}"]
    if r["state"] == "review":
        # The fixed ending is how `ci / floor-check` tells these from the
        # per-commit lines it annotates (#441).
        return [f"not yet confirmed: {r['msg']}{LEFT_TO_SKILL}"]
    return []


def render_verdicts(rs: list[dict]) -> str:
    """The --verdicts file: each result's lines, after a pass line when
    nothing failed."""
    lines = [line for r in rs for line in verdict_lines(r)]
    if not any(r["state"] == "fail" for r in rs):
        lines.insert(0, "pass: the floor, no FAIL in what this run read")
    return "".join(f"{line}\n" for line in lines)


SCHEMA = Path(__file__).resolve().parent / "floor-check.schema.json"
SCHEMA_ID = "floor-check/1"


def run_record(rs: list[dict], run: dict | None = None, crashed: dict | None = None) -> dict:
    """The run as --format json prints it, in the shape of
    scripts/floor-check.schema.json: each result with its entry's area, name,
    hand-off and view; the registered checks that reported nothing (not
    evaluated: another host, archetype or flag); the summary's counts; and,
    when the run raised, after which result."""
    seen = {r["id"] for r in rs}
    n = {s: sum(r["state"] == s for r in rs) for s in STATES}
    results = []
    for r in rs:
        e = REGISTRY[r["id"]]
        results.append({"id": r["id"], "state": r["state"], "shown": SHOWN[r["state"]], "message": r["msg"],
                        "reason": r["reason"], "cannot_be_read_here": r["reason"] == HERE, "reader": r["reader"],
                        "key": r["key"], "area": AREAS[e["area"]], "name": e["name"], "handoff": e["handoff"],
                        "fix": e["fix"], "keepable": e["keepable"], "kept": r["kept"],
                        "lifecycle": e["lifecycle"], "view": e["view"], "ci_visible": e["ci_visible"]})
    return {"schema": SCHEMA_ID, **(run or {}), "results": results,
            "not_evaluated": [{"id": i, "name": e["name"], "area": AREAS[e["area"]]}
                              for i, e in REGISTRY.items() if i not in seen],
            "summary": {**n, "cannot_be_read_here": sum(r["reason"] == HERE for r in rs)},
            "exit": 1 if n["fail"] or crashed else 0, "crashed": crashed}


def print_json(rs: list[dict], crashed: dict | None = None) -> None:
    print(json.dumps(run_record(rs, run_info, crashed), indent=2, ensure_ascii=False))


run_info: dict = {}   # the run's root, project, host and repository, for --format json


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


# ── network ──────────────────────────────────────────────────────────────


ABSENT = object()   # 404: the resource does not exist
ERROR = object()    # anything else went wrong: do not conclude


def json_pages(text: str):
    """The answer `gh api --paginate` prints: one JSON value per page, one
    after another ("Each page is a separate JSON array or object", gh api
    --help). One value is returned as it is; several arrays are one list. A
    value that is not an array among several pages is a ValueError: no page
    of it is guessed at."""
    dec, i, pages = json.JSONDecoder(), 0, []
    while True:
        while i < len(text) and text[i].isspace():
            i += 1
        if i == len(text):
            break
        value, i = dec.raw_decode(text, i)
        pages.append(value)
    if len(pages) == 1:
        return pages[0]
    if pages and all(isinstance(p, list) for p in pages):
        return [x for p in pages for x in p]
    raise ValueError(f"{len(pages)} pages, not all of them arrays")


NEXT_LINK = re.compile(r'<([^>]+)>;\s*rel="next"')


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
            # A 204 has no body (repos/{r}/vulnerability-alerts answers so when on): an empty object.
            if not r.stdout.strip():
                return {}
            try:
                return json_pages(r.stdout) if paginate else json.loads(r.stdout)
            except ValueError:
                return ERROR
        if r is not None and "HTTP 404" in r.stderr:
            return ABSENT
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    url: str | None = f"https://api.github.com/{path}"
    pages: list = []
    try:
        # With paginate, each page's `Link: <…>; rel="next"` is followed, as
        # gh does; a page that is not an array ends it as an ERROR.
        while url is not None and len(pages) < 100:
            req = urllib.request.Request(url)
            req.add_header("Accept", "application/vnd.github+json")
            if token:
                req.add_header("Authorization", f"Bearer {token}")
            with urllib.request.urlopen(req, timeout=20) as resp:
                body = resp.read().decode()
                link = NEXT_LINK.search(resp.headers.get("Link") or "") if paginate else None
            value = json.loads(body) if body.strip() else {}
            if not paginate or (link is None and not pages):
                return value
            if not isinstance(value, list):
                return ERROR
            pages.append(value)
            url = link.group(1) if link else None
        return ERROR if url is not None else [x for p in pages for x in p]
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
    for cid, name in (("FC-A01", "LICENSE"), ("FC-A02", "README.md"), ("FC-A03", "CHANGELOG.md"), ("FC-A04", "AGENTS.md")):
        p = root / name
        verdict(cid, p.is_file() and p.stat().st_size > 0)

    # CONTRIBUTING: present is not adequate. A third of the ones in the wild
    # are stubs with no build/test command and no way to land a change.
    c = root / "CONTRIBUTING.md"
    if verdict("FC-A05", c.is_file()):
        text = read(c)
        verdict("FC-A06", re.search(r"uv run pytest|uv sync|pytest|npm test|make test|tests?/\S+\.(sh|py)", text,
                                    re.IGNORECASE) is not None)
        verdict("FC-A07", re.search(r"pull request|\bPR\b|fork|merge", text, re.IGNORECASE) is not None)
        body = [ln for ln in text.splitlines() if ln.strip()]
        verdict("FC-A08", len(body) >= 10, {"lines": len(body)})

    if (root / "SECURITY.md").is_file():
        emit("FC-A09", "pass", "local")
    elif host == "gitlab":
        # GitLab has no owner-level `.github` repository to inherit from (#547 review, round 3).
        emit("FC-A09", "fail", "gitlab")
    else:
        got = inherited_file(owner, "SECURITY.md", network)
        if got is ERROR:
            emit("FC-A09", "unknown", "unread", reason="offline or API error")
        else:
            emit("FC-A09", *(("pass", "inherited") if got is not ABSENT else ("fail", "absent")))

    if host == "gitlab":
        check_gitlab_templates(root)
        emit("FC-A19", "info", "info")
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
        emit("FC-A11", "info", "info")
    else:
        listing = api(f"repos/{owner}/.github/contents/.github/ISSUE_TEMPLATE", network) if owner else ERROR
        if listing is ERROR or (listing is not ABSENT and not isinstance(listing, list)):
            emit("FC-A10", "unknown", "unread", reason="offline or API error")
        elif listing is ABSENT:
            emit("FC-A10", "fail", "absent")
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
                emit("FC-A10", "unknown", "content", {"names": ", ".join(sorted(unread))}, reason="content unreadable")
            # Absence is concluded only when every candidate was actually read.
            if files or not unread:
                check_issue_forms(files, "inherited")

    verdict("FC-A18", (root / ".github" / "dependabot.yml").is_file())

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
    verdict("FC-A10", bool(forms), {"where": where, "names": ", ".join(sorted(forms))})
    alias_trap = re.compile(r"^\s*[\w-]+:\s+[*&]")
    usable = 0
    for name, text in sorted(forms.items()):
        # `.yml` was already checked before this file started reading `.yaml`
        # and `.md`; those two are new ground. A defect found only because the
        # net widened is reported, not made to fail a build that passed
        # yesterday. Promoting one is a later decision, taken once consumers
        # have had a release to see it.
        known = name.endswith(".yml")
        bad = "fail" if known else "warn"
        if name.endswith(".md"):
            # A legacy Markdown template is front matter and prose. GitHub reads
            # its `name:` from that front matter; the key alone is not a name,
            # and without a value there is no title to list the template under.
            good = bool(md_front_matter_name(text))
            verdict("FC-A12", good, {"name": name}, "warn")   # a `.md` is new ground: never a FAIL
            usable += good
            continue
        keys = [k for k in ("name:", "description:", "body:") if not re.search(rf"^{k}", text, re.MULTILINE)]
        verdict("FC-A13", not keys, {"name": name, "keys": keys}, bad)
        # A value starting with `*` or `&` is read as a YAML alias and breaks the whole form.
        trap = [n for n, ln in enumerate(text.splitlines(), 1) if alias_trap.match(ln)]
        verdict("FC-A14", not trap, {"name": name, "lines": trap}, bad)
        # `labels:` is plinth's policy, not GitHub's syntax: forms are valid
        # without it, so it does not decide whether GitHub can offer the file.
        labelled = re.search(r"^labels:\s*\[.+\]", text, re.MULTILINE) or re.search(r"^labels:\s*\n\s+- ", text, re.MULTILINE)
        verdict("FC-A15", labelled is not None, {"name": name}, bad)
        # `body:` holding a scalar is a form GitHub rejects. This check is new
        # ground for every extension, so it never fails on its own; it decides
        # `usable` only for the extensions this file did not read before, where
        # no repository can have been passing on the strength of it.
        listed = yaml_body_is_list(text)
        if not keys:
            verdict("FC-A16", listed, {"name": name}, "warn")
        usable += not keys and not trap and (listed or known)
    # An invalid extra is a WARN because the repository passed without it being
    # read. A repository whose every template is invalid never passed: it failed
    # the old filename check too, so leaving it green would be a loosening, not
    # compatibility.
    if forms:
        verdict("FC-A17", usable > 0, {"where": where})


def check_gitlab_templates(root: Path) -> None:
    """GitLab offers every `.md` under .gitlab/issue_templates/ and
    .gitlab/merge_request_templates/ by file name; no front matter. An issue
    template labels its issues with a `/label ~name` quick action, as
    plinth-template renders them; one without it is a WARN, as on GitHub."""
    for cid, where in (("FC-A20", ".gitlab/issue_templates"), ("FC-A21", ".gitlab/merge_request_templates")):
        d = root / where
        found = sorted(p.name for p in d.iterdir() if p.is_file() and p.suffix == ".md" and p.stat().st_size > 0) \
            if d.is_dir() else []
        verdict(cid, bool(found), {"names": ", ".join(found)})
        if cid == "FC-A20":
            for name in found:
                verdict("FC-A22", re.search(r"^/label\s+~\S", read(d / name), re.MULTILINE) is not None,
                        {"name": name}, "warn")


def check_gitattributes(root: Path) -> None:
    p = root / ".gitattributes"
    if not verdict("FC-A23", p.is_file()):
        return
    rules: list[tuple[str, list[str]]] = []
    for line in read(p).splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            pattern, *attrs = line.split()
            rules.append((pattern, attrs))
    verdict("FC-A24", any(pat == "*" and "text=auto" in attrs for pat, attrs in rules))
    if any(root.rglob("uv.lock")):
        verdict("FC-A25", any(pat == "uv.lock" and "linguist-generated" in attrs for pat, attrs in rules))
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
    verdict("FC-A26", not local_only, {"rules": local_only})


def check_agent_settings(root: Path, host: str = "github") -> None:
    p = root / ".claude" / "settings.json"
    if not verdict("FC-B01", p.is_file()):
        return
    try:
        deny = json.loads(read(p)).get("permissions", {}).get("deny", [])
    except json.JSONDecodeError:
        emit("FC-B02", "fail", "bad")
        return
    def bash_rule_stops(cmd: str, d: str) -> bool:
        """A `*` in a Bash rule matches any text and nothing else is special
        (fnmatch would read `?` and `[...]` too). `Bash(source .env*` is not a
        rule: without the closing parenthesis `d[5:-1]` would drop the `*`."""
        if not (d.startswith("Bash(") and d.endswith(")")):
            return False
        return re.fullmatch(".*".join(map(re.escape, d[5:-1].split("*"))), cmd) is not None

    wants = {
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
    check_force_push_deny(deny)
    ids = {what: cid for cid, what, _ in AGENT_DENIES}
    for what, match in wants.items():
        verdict(ids[what], any(match(d) for d in deny))


# The spellings of a force push an agent writes, each with the command probed
# and the template's rule that denies it (plinth-template, #942). The first two
# are the floor; the rest were added after an agent in auto mode pushed
# `--force-with-lease`, which `Bash(git push --force:*)` does not match.
FORCE_PUSH_SPELLINGS = [
    ("`git push --force`", "git push --force", "Bash(git push --force:*)"),
    ("`git push -f`", "git push -f", "Bash(git push -f:*)"),
    ("`--force-with-lease`", "git push --force-with-lease", "Bash(git push *--force*)"),
    ("`--force` after other arguments", "git push origin b --force", "Bash(git push *--force*)"),
    ("`-f` after other arguments", "git push origin b -f", "Bash(git push * -f)"),
    ("a `+` refspec", "git push origin +b", "Bash(git push *+*)"),
    ("`git -C <dir> push --force`", "git -C d push --force", "Bash(git * push *--force*)"),
    ("`git -C <dir> push -f`", "git -C d push -f", "Bash(git * push -f)"),
    ("`git -C <dir> push <b> -f`", "git -C d push origin b -f", "Bash(git * push * -f)"),
    ("`git -C <dir> push +<b>`", "git -C d push origin +b", "Bash(git * push *+*)"),
    ("`-f` between other arguments", "git push origin -f b", "Bash(git push * -f *)"),
    ("`git -C <dir> push -f <b>`", "git -C d push -f origin b", "Bash(git * push -f *)"),
]


def deny_rule_matches(rule: str, cmd: str) -> bool:
    """Claude Code's documented Bash matching: a trailing `:*` is a trailing
    ` *`, whose space is part of the rule; it also matches the bare command
    only when it is the rule's only wildcard (`Bash(git push * -f *)` does
    not match `git push origin b -f`); any other `*` matches any text;
    nothing else is special."""
    if not (rule.startswith("Bash(") and rule.endswith(")")):
        return False
    body, tail = rule[5:-1], ""
    if body.endswith(":*"):
        body = body[:-2] + " *"
    if body.endswith(" *") and body.count("*") == 1:
        body, tail = body[:-2], "(?: .*)?"
    return re.fullmatch(".*".join(map(re.escape, body.split("*"))) + tail, cmd, re.DOTALL) is not None


def check_force_push_deny(deny: list) -> None:
    """Names the spellings the rules deny, not only that one rule starts with
    `Bash(git push --force` (#942). Neither of the first two denied is a FAIL,
    as before; a wider spelling missing is new ground, so a WARN."""
    rules = [d for d in deny if isinstance(d, str)]
    stops = {label: any(deny_rule_matches(r, cmd) for r in rules) for label, cmd, _ in FORCE_PUSH_SPELLINGS}
    denied = [label for label, hit in stops.items() if hit]
    floor = [label for label, _, _ in FORCE_PUSH_SPELLINGS[:2]]
    if not any(stops[label] for label in floor):
        emit("FC-B03", "fail", "bad")
        return
    missing = [(label, rule) for label, _, rule in FORCE_PUSH_SPELLINGS if not stops[label]]
    if not missing:
        emit("FC-B03", "pass", "good", {"denied": ", ".join(denied)})
        return
    emit("FC-B03", "warn", "partly", {"denied": ", ".join(denied), "missing": ", ".join(label for label, _ in missing)})
    adds = list(dict.fromkeys(rule for _, rule in missing))
    emit("FC-B03", "info", "add", {"rules": ", ".join(json.dumps(r) for r in adds)})


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
        emit("FC-A28", "unknown", "unread", reason="git could not list the tracked files")
        return
    tracked = [f for f in r.stdout.split("\0") if f]
    found = sorted(f for f in tracked if (n := f.rsplit("/", 1)[-1]) not in DOTENV_PLACEHOLDERS
                   and (n == ".env" or n.startswith(".env.")))
    if not found:
        emit("FC-A28", "pass", "good", {"count": len(tracked)})
    for f in found:
        emit("FC-A28", "warn", "bad", {"file": f})
        emit("FC-A28", "info", "untrack", {"quoted": shlex.quote(f)})


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
        emit("FC-D01", "info", "none")
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
            emit("FC-D01", "warn", "bad", {"rel": rel, "lines": ", ".join(f"line {n} {v}" for n, v in unpinned)})
            for v in sorted({v for _, v in unpinned}):
                m = re.fullmatch(r"([^/@]+/[^/@]+)(?:/[^@]*)?@(.+)", v)
                if v.startswith("docker://"):
                    emit("FC-D01", "info", "docker", {"value": v})
                elif m:
                    # Quoted: the line is pasted into a shell, and a ref may hold `$(...)` or `;`.
                    emit("FC-D01", "info", "sha", {"path": shlex.quote(f"repos/{m.group(1)}/commits/{m.group(2)}")})
                else:
                    emit("FC-D01", "info", "form", {"value": v})
        if unread:
            clean = False
            emit("FC-D01", "unknown", "unread", {"rel": rel, "lines": ", ".join(map(str, unread))},
                 reason="uses in a form not read")
    if clean:
        emit("FC-D01", "pass", "good", {"count": len(files), "s": "s" * (len(files) != 1), "total": total})


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
# python-ci.yml's diff-size-exclude default; tests/floor-check-cases.sh holds the two in step.
DEFAULT_DIFF_SIZE_EXCLUDE = "*.md *.lock *lock.json *lock.yaml *lock.yml LICENSE"
DEFAULT_SEVERITY = "high"


def check_inputs(inputs: dict[str, str | None], where: str) -> None:
    """A WARN for each of the two inputs the `with:` loosens past plinth's
    default, a SKIP for each it passes in a form not read, and a SKIP for a
    line that could pass either."""
    if UNREAD_LINE in inputs:
        emit("FC-D03", "unknown", "line", {"where": where, "line": inputs[UNREAD_LINE]}, reason="a with: line not read")
    for name in ("max-diff-lines", "deps-fail-on-severity"):
        if name not in inputs:
            continue
        value = inputs[name]
        if value is None or "${{" in value:
            emit("FC-D03" if name == "max-diff-lines" else "FC-D04", "unknown", "value", {"where": where, "name": name},
                 reason="a value not read")
            continue
        if name == "max-diff-lines":
            try:
                n = float(value)
            except ValueError:
                n = math.nan
            if not math.isfinite(n) or n != int(n):
                emit("FC-D03", "unknown", "number", {"where": where, "value": value}, reason="not a whole number")
                continue
            if n <= 0:
                emit("FC-D03", "warn", "off", {"where": where, "value": value, "default": DEFAULT_MAX_DIFF_LINES})
            elif n > DEFAULT_MAX_DIFF_LINES:
                emit("FC-D03", "warn", "above", {"where": where, "value": value, "default": DEFAULT_MAX_DIFF_LINES})
        elif value == "critical":
            emit("FC-D04", "warn", "critical", {"where": where, "value": value, "default": DEFAULT_SEVERITY})
        elif value not in {"high", "moderate", "low"}:
            emit("FC-D04", "unknown", "severity", {"where": where, "value": value}, reason="not a severity")


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
        emit("FC-D05", "pass", "good", {"where": where})
        return
    seen = "no web: line" if "web" not in inputs else f"web: {value}" if value is not None else "a web: line this checker does not read"
    emit("FC-D05", "fail", "bad", {"where": where, "seen": seen})
    emit("FC-D05", "info", "add")


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
                emit("FC-D02", "unknown", "repo", {"repo": repo}, reason="the repository could not be read")
            else:
                emit("FC-D02", "fail", "nofile", {"rel": rel, "repo": repo, "workflow": CALLER_WORKFLOW})
            return
        text = None
        if isinstance(data, dict) and data.get("encoding") == "base64" and isinstance(data.get("content"), str):
            try:
                text = base64.b64decode(data["content"]).decode("utf-8", errors="replace")
            except ValueError:
                text = None
        if text is None:
            emit("FC-D02", "unknown", "notfile", {"rel": rel}, reason="not returned as a file")
            return
    else:
        why = "--caller-from-checkout" if from_checkout else "--no-network" if not network else "no --repo"
        where = f"in the checkout ({why})" if from_checkout else f"in the checkout, not the default branch ({why})"
        p = root / rel
        if not p.is_file():
            emit("FC-D02", "unknown", "nocheckout", {"rel": rel, "why": why}, reason="no ci.yml in the checkout")
            return
        text = read(p)
    kind, value, inputs = caller_job(text)
    if kind == "unread":
        emit("FC-D02", "unknown", "unread", {"where": where, "value": value}, reason="the ci job not read")
        return
    then = f"then set the ci job's uses: to {CALLER_WORKFLOW}@<that SHA>"
    latest = (f'gh api "repos/{PLINTH_REPO}/commits/$(gh api repos/{PLINTH_REPO}/releases/latest --jq .tag_name)" '
              f"--jq .sha   (plinth's latest release; {then})")
    if kind == "missing":
        emit("FC-D02", "fail", "missing", {"rel": rel, "where": where, "value": value, "workflow": CALLER_WORKFLOW})
        emit("FC-D02", "info", "hint", {"command": latest})
        return
    if kind == "skippable":
        emit("FC-D02", "fail", "skippable", {"where": where, "value": value})
        emit("FC-D02", "info", "remove", {"value": value})
        return
    if repo and repo.lower() == PLINTH_REPO and value == PLINTH_OWN_CALLER:
        emit("FC-D02", "pass", "own", {"where": where, "value": value, "repo": PLINTH_REPO})
        check_inputs(inputs, where)
        check_web_input(inputs, where, archetype)
        return
    m = re.fullmatch(r"([^/@]+/[^/@]+)(/[^@]*)@(.*)", value)
    if m and m.group(1).lower() == PLINTH_REPO and m.group(2) == CALLER_WORKFLOW[len(PLINTH_REPO):]:
        if re.fullmatch(r"[0-9a-fA-F]{40}", m.group(3)):
            emit("FC-D02", "pass", "good", {"where": where, "value": value})
        else:
            emit("FC-D02", "fail", "ref", {"where": where, "value": value})
            # Quoted: the line is pasted into a shell, and a ref may hold `$(...)` or `;`.
            emit("FC-D02", "info", "hint",
                 {"command": f"gh api {shlex.quote(f'repos/{PLINTH_REPO}/commits/{m.group(3)}')} --jq .sha   ({then})"})
        check_inputs(inputs, where)
        check_web_input(inputs, where, archetype)
    else:
        emit("FC-D02", "fail", "other", {"where": where, "value": value, "workflow": CALLER_WORKFLOW})
        emit("FC-D02", "info", "hint", {"command": latest})


def plinth_pins(root: Path) -> dict:
    """The coolbress/plinth `uses:` of the checkout's workflow files (#447),
    read once for the pin-agreement item and the update's stop (#793).
    `by_file` maps each file to its (owner/repository, ref) pairs as written,
    in order, once each; `unread` names each `uses:` it cannot read; `names`
    puts the ci job's file first; `target` is the SHA the ci job calls, or
    None when that job does not call plinth's caller workflow at a full SHA;
    `fix` is the sed line for each plinth reference not at `target`. A plinth
    `uses:` not on a full SHA is not counted here."""
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
    by_file = {f: pins for f, pins in by_file.items() if pins}
    names = sorted(by_file, key=lambda f: (f != "ci.yml", f))
    target = None
    ci = root / ".github" / "workflows" / "ci.yml"
    if ci.is_file():
        kind, value, _ = caller_job(read(ci))
        m = re.fullmatch(r"([^/@]+/[^/@]+)(/[^@]*)@([0-9a-fA-F]{40})", value) if kind == "uses" else None
        if m and m.group(1).lower() == PLINTH_REPO and m.group(2) == CALLER_WORKFLOW[len(PLINTH_REPO):]:
            target = m.group(3)
    fix = []
    for f in names if target is not None else []:
        for repo, old in by_file[f]:
            if target is not None and old.lower() != target.lower():
                path = shlex.quote(f".github/workflows/{f}")
                # Only `<owner/repository>/<path>@<old>`: the same SHA elsewhere in the file is left alone.
                repo_re = repo.replace(".", r"\.")
                fix.append(f"sed -i.bak 's|{repo_re}/\\([^@]*\\)@{old}|{repo}/\\1@{target}|g' {path} && rm {path}.bak")
    shas = {ref.lower() for pins in by_file.values() for _, ref in pins}
    parts = [f"{f} at {' and '.join(dict.fromkeys(ref.lower() for _, ref in by_file[f]))}" for f in names]
    warn = (f"workflow pins disagree: {names[0]} calls plinth{parts[0][len(names[0]):]}"
            + "".join(f", {x}" for x in parts[1:])) if len(shas) > 1 else None
    return {"by_file": by_file, "unread": unread, "names": names, "target": target, "fix": fix, "warn": warn}


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
    pins = plinth_pins(root)
    if pins["warn"] is None:
        if pins["unread"]:
            emit("FC-F06", "unknown", "unread", {"where": ", ".join(pins["unread"])},
                 reason="a uses: line not read")
        return
    # The ci job's file first: the fix moves the others to the SHA it calls.
    emit("FC-F06", "warn", "bad", {"line": pins["warn"]})
    if pins["target"] is None:
        emit("FC-F06", "info", "one", {"repo": PLINTH_REPO})
        return
    for line in pins["fix"]:
        emit("FC-F06", "info", "fix", {"line": line})


def pins_disagree_stop(root: Path, network: bool) -> list[str]:
    """What the update's "workflow pins disagree" stop adds (#793): each
    file with the plinth commit it calls, which of two is the newer when
    GitHub's compare says one is behind the other, and the fix lines the
    pin-agreement item prints. The update cannot pick one of two pins; the
    person makes them one, merges that, and runs the update again."""
    pins = plinth_pins(root)
    if pins["warn"] is None:
        return []
    out = [f"  {f}: {PLINTH_REPO} at {' and '.join(dict.fromkeys(ref.lower() for _, ref in pins['by_file'][f]))}"
           for f in pins["names"]]
    target = pins["target"]
    if target is None:
        out.append(f"set every {PLINTH_REPO} uses: line (ci.yml and label.yml) to the one commit the ci job "
                   "should call, merge that, and run the update again")
        return out
    target = target.lower()
    for other in dict.fromkeys(ref.lower() for f in pins["names"] for _, ref in pins["by_file"][f]):
        if other == target:
            continue
        cmp = api(f"repos/{PLINTH_REPO}/compare/{target}...{other}", network)
        status = cmp.get("status") if isinstance(cmp, dict) else None
        if status == "behind":
            out.append(f"newer: {target}, the ci job's; {other} is behind it")
        elif status == "ahead":
            out.append(f"newer: {other}; the ci job's {target} is behind it, so the line below moves {other} "
                       f"back: to keep the newer one, raise the ci job's uses: to {other} instead")
        else:
            why = ("the two have diverged" if status == "diverged"
                   else "offline or API error" if cmp in (ABSENT, ERROR) else "an unexpected compare response")
            out.append(f"newer: not known for {target} and {other} ({why})")
    out.append("to make them one, move every plinth uses: to the ci job's commit (the line floor-check's "
               "\"Plinth pins agree\" item prints), merge that, and run the update again:")
    out += [f"  {line}" for line in pins["fix"]]
    return out


def pins_forward(root: Path, network: bool) -> list[tuple[str, str, str]]:
    """When the workflows call plinth at two or more commits and every one
    but the ci job's is an ancestor of the ci job's (#793): (file, from, to)
    for each file the update moves forward, `to` being the ci job's commit,
    which the update then carries. Empty otherwise: the ci job not calling
    plinth's caller workflow at a full SHA, another file newer than the ci
    job's, two commits neither of which is behind the other, or a compare not
    read. It never moves the ci job's own pin: that is a person's choice."""
    pins = plinth_pins(root)
    target = pins["target"].lower() if pins["target"] else None
    if pins["warn"] is None or target is None:
        return []
    moves: list[tuple[str, str, str]] = []
    verdict: dict[str, bool] = {}
    for f in pins["names"]:
        for _, ref in pins["by_file"][f]:
            ref = ref.lower()
            if ref == target:
                continue
            if ref not in verdict:
                cmp = api(f"repos/{PLINTH_REPO}/compare/{target}...{ref}", network)
                verdict[ref] = isinstance(cmp, dict) and cmp.get("status") == "behind"
            if not verdict[ref]:
                return []
            moves.append((f, ref, target))
    return moves


def print_diff_size(root: Path) -> int:
    """--print-diff-size (#795): what ci / diff-size counts against in this
    checkout, read from the ci job's `with:` as check_caller reads it, each
    input it does not pass taking plinth's default. Three lines on stdout,
    `max=<n>`, `exclude=<patterns>` and `root=<working-directory>`, exit 0;
    otherwise why it is not read on stderr, exit 1: no ci job calling plinth
    at a full SHA, or one of the three passed as an expression or in a form
    this reader does not take. template-update.sh measures its own diff with
    it before opening the pull request."""
    ci = root / ".github" / "workflows" / "ci.yml"
    if not ci.is_file():
        print("no .github/workflows/ci.yml", file=sys.stderr)
        return 1
    kind, value, inputs = caller_job(read(ci))
    if kind != "uses" or not value.lower().startswith(f"{PLINTH_REPO}/"):
        print(f"the ci job does not call plinth's workflow ({kind}: {value})", file=sys.stderr)
        return 1
    if UNREAD_LINE in inputs:
        print(f"the ci job has a with: line this checker does not read: {inputs[UNREAD_LINE]}", file=sys.stderr)
        return 1
    got = {"max-diff-lines": str(DEFAULT_MAX_DIFF_LINES), "diff-size-exclude": DEFAULT_DIFF_SIZE_EXCLUDE,
           "working-directory": "."}
    for name in got:
        if name not in inputs:
            continue
        v = inputs[name]
        if v is None or "${{" in v:
            print(f"the ci job passes {name} in a form not read (an expression, or one this checker does not read)",
                  file=sys.stderr)
            return 1
        got[name] = v
    if not re.fullmatch(r"-?\d+", got["max-diff-lines"]):
        print(f"the ci job passes max-diff-lines: {got['max-diff-lines']}: not read as a whole number", file=sys.stderr)
        return 1
    print(f"max={got['max-diff-lines']}")
    print(f"exclude={got['diff-size-exclude']}")
    print(f"root={got['working-directory']}")
    return 0


# The heading coolbress/plinth-template#359 gives each release section of the
# template's CHANGELOG: the rendered files the release changes and the copier
# questions it adds. The update plan quotes it (#1184); a section without it
# is printed by its own heading alone.
TEMPLATE_CHANGES_HEADING = "### Files and questions"


def semver(tag: str) -> tuple[int, int, int] | None:
    m = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)", tag)
    return (int(m.group(1)), int(m.group(2)), int(m.group(3))) if m else None


def print_template_changes(root: Path, network: bool) -> int:
    """--print-template-changes (#1184): what the template changed between
    the tag .copier-answers.yml records and the one this plinth targets, from
    the target tag's own CHANGELOG.md (read at the commit new-project.sh
    pins): the heading of each release section after the recorded tag, up to
    and including the target, newest first, each followed by its
    TEMPLATE_CHANGES_HEADING block, indented, where it has one. Exit 0.
    Otherwise the compare link alone on stdout, why on stderr, exit 1: the
    CHANGELOG not read, a tag that is not a version, or no section between."""
    pin = new_project_pin()
    recorded = (copier_answers(root) or {}).get("_commit", "")
    if not pin or not recorded:
        print("no template tag recorded in .copier-answers.yml, or no pin beside this script", file=sys.stderr)
        return 1
    template_repo, target, target_sha = pin[0], pin[1], pin[2]
    link = f"https://github.com/{template_repo}/compare/{recorded}...{target}"
    after, upto = semver(recorded), semver(target)
    if not after or not upto:
        print(link)
        print(f"{recorded} or {target} is not a version tag", file=sys.stderr)
        return 1
    data = api(f"repos/{template_repo}/contents/CHANGELOG.md?ref={target_sha}", network)
    text = None
    if isinstance(data, dict):
        try:
            text = base64.b64decode(data["content"]).decode()
        except (TypeError, KeyError, ValueError):
            text = None
    if text is None:
        print(link)
        print(f"{template_repo} CHANGELOG.md at {target}: {'not found' if data is ABSENT else 'offline or API error'}",
              file=sys.stderr)
        return 1
    sections: list[tuple[str, list[str]]] = []
    for line in text.splitlines():
        if line.startswith("## "):
            sections.append((line.rstrip(), []))
        elif sections:
            sections[-1][1].append(line.rstrip())
    out: list[str] = []
    for heading, body in sections:
        m = re.match(r"## \[(\d+\.\d+\.\d+)\]", heading)
        v = semver(m.group(1)) if m else None
        if not v or not after < v <= upto:
            continue
        out.append(heading)
        if TEMPLATE_CHANGES_HEADING in body:
            block: list[str] = []
            for line in body[body.index(TEMPLATE_CHANGES_HEADING):]:
                if block and line.startswith("### "):
                    break
                block.append(line)
            while block and not block[-1]:
                block.pop()
            out += [f"  {line}" if line else "" for line in block]
    if not out:
        print(link)
        print(f"{template_repo} CHANGELOG.md at {target} has no release section after {recorded}", file=sys.stderr)
        return 1
    print("\n".join(out))
    return 0


def print_plinth_pins(root: Path) -> int:
    """--print-plinth-pins (#793): every coolbress/plinth `uses:` of the
    workflow files, read as the pin items read them (iter_uses: comments and
    the interior of a `run: |` block skipped), one `<file> <ref>` line each,
    the ref as written; a `uses:` it cannot read is `<file> unread line <n>`,
    since it could be one. template-update.sh checks with it, after copier,
    that every plinth pin names the one its command carried."""
    for p in workflow_files(root):
        for n, value, readable in iter_uses(read(p)):
            if not readable:
                print(f"{p.name} unread line {n}")
            elif value.lower().startswith(f"{PLINTH_REPO}/"):
                print(f"{p.name} {value.rpartition('@')[2]}")
    return 0


def print_plinth_comments(root: Path) -> int:
    """--print-plinth-comments (#1045): each coolbress/plinth `uses:` of the
    workflow files that carries a trailing comment (`@<sha> # v2.41.0`, as
    Dependabot writes it), one `<file> <ref>` line each, read as
    --print-plinth-pins reads them. The template renders the line with no
    comment, so copier's three-way merge sees this repository's line changed;
    template-update.sh says, before --apply, where that conflicts."""
    for p in workflow_files(root):
        for _, _, line in yaml_lines(read(p)):
            m = USES_LINE.match(line)
            if m and m.group(2).lower().startswith(f"{PLINTH_REPO}/") and "#" in line[m.end(2):]:
                print(f"{p.name} {m.group(2).rpartition('@')[2]}")
    return 0


def moves_lines(d: dict) -> list[str]:
    """One line per file the update moves forward to the ci job's commit (#793)."""
    return [f"moves: {f} from {old} to {new}, the commit the ci job calls ({old} is an ancestor of it)"
            for f, old, new in d.get("moves", [])]


def question_help(text: str, key: str) -> list[str] | None:
    """The `help:` of the top-level question <key> in a copier.yml, as lines:
    a plain or quoted scalar, or a `|` or `>` block (dedented; `>` folded into
    one line). None when the question or its help is not there. Not a YAML
    parser: the `help:` line one level inside the top-level `<key>:` block."""
    m = re.search(rf"^{re.escape(key)}:[ \t]*\n((?:[ \t]+.*\n|[ \t]*\n)*)", text + "\n", re.MULTILINE)
    if not m:
        return None
    lines = m.group(1).splitlines()
    inner = min((len(x) - len(x.lstrip()) for x in lines if x.strip()), default=0)
    for i, line in enumerate(lines):
        if len(line) - len(line.lstrip()) != inner or not line.lstrip().startswith("help:"):
            continue
        v = line.lstrip()[len("help:"):].strip()
        if v[:1] in ("|", ">"):
            block: list[str] = []
            for x in lines[i + 1:]:
                if x.strip() and len(x) - len(x.lstrip()) <= inner:
                    break
                block.append(x)
            while block and not block[-1].strip():
                block.pop()
            deeper = min((len(x) - len(x.lstrip()) for x in block if x.strip()), default=0)
            block = [x[deeper:] for x in block]
            return [" ".join(x.strip() for x in block if x.strip())] if v[0] == ">" else block
        if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
            v = v[1:-1]
        return [v] if v else None
    return None


def print_question_help(names: list[str], network: bool) -> int:
    """--print-question-help (#1185): for each named question, its name on a
    line, then its help from the copier.yml of the tag this plinth targets
    (read at the commit new-project.sh pins), each line indented by two; a
    question with no help there is followed by `  (no help in copier.yml)`;
    a blank line of help is printed as two spaces, so only a name starts a line.
    Exit 0; exit 1 with the reason on stderr when copier.yml is not read."""
    pin = new_project_pin()
    if not pin:
        print("no template pin beside this script", file=sys.stderr)
        return 1
    template_repo, target, target_sha = pin[0], pin[1], pin[2]
    data = api(f"repos/{template_repo}/contents/copier.yml?ref={target_sha}", network)
    text = None
    if isinstance(data, dict):
        try:
            text = base64.b64decode(data["content"]).decode()
        except (TypeError, KeyError, ValueError):
            text = None
    if text is None:
        print(f"{template_repo} copier.yml at {target}: {'not found' if data is ABSENT else 'offline or API error'}",
              file=sys.stderr)
        return 1
    for name in names:
        print(name)
        # A blank line of the help stays indented: only a name starts a line.
        for line in question_help(text, name) or ["(no help in copier.yml)"]:
            print(f"  {line}".rstrip() or "  ")
    return 0


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


# --- The adoption record (#1112) ----------------------------------------------
ADOPTION_FILE = ".plinth-adoption.yml"
ADOPTION_STEPS = ("files", "ci", "wall", "done")
KEEP_REASONS = ("not-applicable", "deliberately-different", "later")
ADOPTION_TOP = ("schema", "plinth", "origin", "archetype", "started", "step", "wall_due", "kept")
ADOPTION_REQUIRED = ("schema", "plinth", "origin", "archetype", "started", "step")
KEPT_KEYS = ("id", "path", "reason", "why", "until")
KEPT_REQUIRED = ("id", "path", "reason", "why")
WALL_DUE_DAYS = 30   # a starting value, chosen without evidence (#1112's Decisions)
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
adoption: dict | None = None   # the record as read, when it is valid
kept: dict[str, dict] = {}     # id -> its kept entry, the ones applied


def today() -> datetime.date:
    """The date the record's dates are compared with: UTC, or FLOOR_CHECK_TODAY (the tests)."""
    given = os.environ.get("FLOOR_CHECK_TODAY")
    return datetime.date.fromisoformat(given) if given else datetime.datetime.now(datetime.timezone.utc).date()


# A quoted value, then nothing or a ` #` comment: the comment is taken off
# outside the quotes, so a `#` inside them stays in the value.
SINGLE_QUOTED = re.compile(r"'((?:[^']|'')*)'(?:\s+#.*)?")
DOUBLE_QUOTED = re.compile(r'("(?:[^"\\]|\\.)*")(?:\s+#.*)?')


def yaml_scalar(text: str, n: int) -> str:
    """One value of the record's form, on line `n`: quoted ('…' or "…"), with
    or without a ` #` comment after the closing quote, or plain up to a ` #`
    comment. A quote that does not close, or anything but a comment after
    it, is a ValueError naming the line, never a value with its quotes."""
    t = text.strip()
    if t[:1] == "'":
        m = SINGLE_QUOTED.fullmatch(t)
        if m:
            return m.group(1).replace("''", "'")
    elif t[:1] == '"':
        m = DOUBLE_QUOTED.fullmatch(t)
        if m:
            return json.loads(m.group(1))
    else:
        # A comment is a `#` at the start or after a space: `key: # note` is empty.
        return re.sub(r"(?:^|\s+)#.*$", "", t)
    raise ValueError(f"line {n}: a quoted value with more than a comment after it, or not closed: {t}")


def read_adoption(text: str) -> dict:
    """.plinth-adoption.yml in the form the adopt pull request writes: top-level
    `key: value` lines, and `kept:` as a list of `- key: value` mappings (or
    `kept: []`). Not a YAML parser (standard library only): any other line is
    a ValueError naming it, never a guess."""
    out: dict = {}
    item: dict | None = None
    in_kept = False
    for n, line in enumerate(text.splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        top = re.match(r"^([a-z_]+):(?:\s+(.*))?$", line)
        if top:
            key, value = top.group(1), (top.group(2) or "").strip()
            if key in out:
                raise ValueError(f"line {n}: {key} given twice")
            # The list's header is read with its comment off: `kept: # why`
            # opens the list, `kept: [] # none` is the empty one.
            head = yaml_scalar(value, n) if key == "kept" and not value.startswith(("'", '"')) else value
            in_kept = key == "kept" and head in ("", "[]")
            out[key] = [] if in_kept else yaml_scalar(value, n)
            if in_kept and head == "[]":
                in_kept = False
            item = None
            continue
        entry = re.match(r"^  (- |  )([a-z_]+):(?:\s+(.*))?$", line)
        if in_kept and entry and (entry.group(1) == "- " or item is not None):
            if entry.group(1) == "- ":
                item = {}
                out["kept"].append(item)
            assert item is not None
            if entry.group(2) in item:
                raise ValueError(f"line {n}: {entry.group(2)} given twice in one kept entry")
            item[entry.group(2)] = yaml_scalar(entry.group(3) or "", n)
            continue
        raise ValueError(f"line {n} is not in the form this checker reads")
    return out


def adoption_errors(d: dict) -> list[str]:
    """What makes the record invalid, in the shape of scripts/plinth-adoption.schema.json."""
    errs = [f"unknown field {k}" for k in d if k not in ADOPTION_TOP]
    errs += [f"no {k}" for k in ADOPTION_REQUIRED if k not in d]
    if "schema" in d and d["schema"] != "1":
        errs.append(f"schema {d['schema']} is not 1")
    if "plinth" in d and not re.fullmatch(r"v\d+\.\d+\.\d+", str(d["plinth"])):
        errs.append(f"plinth {d['plinth']} is not a release tag")
    if "origin" in d and not (d["origin"] == "none" or re.fullmatch(r"other-template:\S+", str(d["origin"]))):
        errs.append(f"origin {d['origin']} is neither none nor other-template:<source>")
    if "archetype" in d and not re.fullmatch(r"[a-z][a-z-]*", str(d["archetype"])):
        errs.append(f"archetype {d['archetype']} is not an archetype name")
    if "step" in d and d["step"] not in ADOPTION_STEPS:
        errs.append(f"step {d['step']} is not one of {', '.join(ADOPTION_STEPS)}")
    for k in ("started", "wall_due"):
        if k in d and not valid_date(d[k]):
            errs.append(f"{k} {d[k] or '(empty)'} is not a date (YYYY-MM-DD)")
    if not isinstance(d.get("kept", []), list):
        errs.append("kept is not a list")
        return errs
    for i, e in enumerate(d.get("kept", []), 1):
        errs += [f"kept entry {i}: unknown field {k}" for k in e if k not in KEPT_KEYS]
        errs += [f"kept entry {i}: no {k}" for k in KEPT_REQUIRED if not e.get(k)]
        if e.get("id") and not re.fullmatch(r"FC-[A-Z]\d\d", e["id"]):
            errs.append(f"kept entry {i}: id {e['id']} is not a check id")
        if e.get("reason") and e["reason"] not in KEEP_REASONS:
            errs.append(f"kept entry {i}: reason {e['reason']} is not one of {', '.join(KEEP_REASONS)}")
        if e.get("reason") == "later" and "until" not in e:
            errs.append(f"kept entry {i}: reason later with no until")
        if "until" in e and not valid_date(e["until"]):
            errs.append(f"kept entry {i}: until {e['until'] or '(empty)'} is not a date (YYYY-MM-DD)")
    return errs


def valid_date(v: object) -> bool:
    if not isinstance(v, str) or not DATE.match(v):
        return False
    try:
        datetime.date.fromisoformat(v)
    except ValueError:
        return False
    return True


def adoption_json(d: dict) -> dict:
    """The record as the schema types it: schema an integer, the rest strings."""
    return {**d, "schema": 1} if d.get("schema") == "1" else d


def wall_due(d: dict) -> datetime.date | None:
    """The record's wall_due, at most WALL_DUE_DAYS after started; None without one."""
    if "wall_due" not in d:
        return None
    due, started = datetime.date.fromisoformat(d["wall_due"]), datetime.date.fromisoformat(d["started"])
    return min(due, started + datetime.timedelta(days=WALL_DUE_DAYS))


def wall_later() -> str | None:
    """The date the wall is due by, when the record holds it off today (#1112):
    a valid record not at step done, on or before its (capped) wall_due.
    check_wall asks only when the default branch has no rules: wall_due has
    no effect on a repository that has a ruleset."""
    if adoption is None or adoption["step"] == "done":
        return None
    due = wall_due(adoption)
    return due.isoformat() if due is not None and today() <= due else None


def check_adoption(root: Path) -> None:
    """Reads .plinth-adoption.yml at the repository root (#1112). With no file
    nothing is printed and nothing changes. A file that cannot be read or is
    not valid is a FAIL naming it, and nothing in it applies. Each kept entry
    applies unless it names no check, its check cannot be kept, or its
    `until` has passed: then a FAIL says so and the finding stands. A `later`
    entry with no `until` makes the file invalid, as the schema says."""
    global adoption
    p = root / ADOPTION_FILE
    if not p.exists() and not p.is_symlink():
        return
    f = ADOPTION_FILE
    try:
        d = read_adoption(p.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError) as exc:
        emit("FC-F09", "fail", "unreadable", {"file": f, "why": type(exc).__name__})
        return
    except (ValueError, json.JSONDecodeError) as exc:
        emit("FC-F09", "fail", "invalid", {"file": f, "why": str(exc)})
        return
    errs = adoption_errors(d)
    # The 30 days count from started: a started after today would move the
    # cap as far as it is written, so it makes the record invalid.
    if not errs and datetime.date.fromisoformat(d["started"]) > today():
        errs.append(f"started {d['started']} is after today ({today().isoformat()})")
    if errs:
        emit("FC-F09", "fail", "invalid", {"file": f, "why": "; ".join(errs)})
        return
    adoption = d
    aliases = {a: i for i, e in REGISTRY.items() for a in e["aliases"]}
    now = today()
    for e in d.get("kept", []):
        cid = aliases.get(e["id"], e["id"])
        if cid not in REGISTRY:
            emit("FC-F09", "fail", "unknown_id", {"file": f, "id": e["id"]})
        elif not REGISTRY[cid]["keepable"]:
            emit("FC-F09", "fail", "not_keepable", {"file": f, "id": cid, "why": REGISTRY[cid]["not_keepable"]})
        elif "until" in e and datetime.date.fromisoformat(e["until"]) < now:
            emit("FC-F09", "fail", "expired", {"file": f, "id": cid, "until": e["until"]})
        else:
            kept[cid] = e
    due = wall_due(d)
    if due is not None and due.isoformat() != d["wall_due"]:
        emit("FC-F09", "info", "capped", {"file": f, "due": d["wall_due"], "days": WALL_DUE_DAYS,
                                          "started": d["started"], "cap": due.isoformat()})
    emit("FC-F09", "info", "read", {"file": f, "step": d["step"], "kept": len(kept),
                                    "due": f"; the wall due by {due.isoformat()}" if due and d["step"] != "done" else ""})


def print_adoption(root: Path) -> int:
    """--print-adoption: the record as the schema reads it, or why it is not read."""
    try:
        d = read_adoption((root / ADOPTION_FILE).read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, ValueError) as exc:
        print(f"{ADOPTION_FILE} not read: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(adoption_json(d), indent=2, ensure_ascii=False))
    return 0


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


def template_drift(root: Path, host: str | None = None, network: bool = False, move: bool = False) -> dict:
    """Where this repository stands against the template tag plinth is
    tested with, and the one `copier update` command that moves it there
    (#219). Offline but for the one compare named at the end. The drift item below prints it; --print-update-command
    prints the command alone for the template-update skill (#232), so the
    command that runs is the one this item prints, never a second
    construction of it. `state` is skip, ahead, current or behind; `reason`
    says why a skip was not verified; `cmd` is set only when behind and the
    plinth pin is established, and `why_not` says why it is not. At the
    target tag on GitHub with an owner answer recorded true, `state` is
    current and `cmd` a same-tag line, which owner_shared keeps only when
    that answer turns false (#770); the drift item does not print it. `host` is
    the host the run resolved (--host first, then the answers); without it,
    the answers' `host:` (#547 review). When the workflows call plinth at two
    commits and every other one is an ancestor of the ci job's, `cmd` carries
    the ci job's and `moves` names each file the update moves forward (#793);
    that needs GitHub's compare, so `network` (or fixtures) decides it."""
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
    state = "behind"
    if recorded == target:
        # At the target tag there is nothing to update, unless an owner
        # answer recorded true may no longer hold (#770): the owner's shared
        # templates were removed after this repository was made. copier
        # update at the same tag renders what the answer changed (measured,
        # copier 9.18.2); owner_shared decides whether it changed.
        # An archetype move (#1004) is a same-tag line too.
        if not move and ((host or answers.get("host")) == "gitlab"
                         or not any(answers.get(k) == "true" for k in OWNER_KEYS)):
            return {**out, "state": "current"}
        state = "current"
    out["move"] = move

    integrity = None
    if (host or answers.get("host")) == "gitlab":
        sha, integrity, why_not = resolve_gitlab_pin(root)
    else:
        sha, why_not = resolve_plinth_pin(root)
        if sha is None and str(why_not).startswith("workflow pins disagree"):
            moves = pins_forward(root, network)
            if moves:
                sha, why_not, out["moves"] = moves[0][2], None, moves
    # --defaults: without a terminal copier update stops at "Interactive
    # session required" (measured, copier 9.18.2), and the skill that runs
    # this line has none. It answers each question with the recorded answer.
    out.update(copier_version=copier_version, copier_newer=copier_newer)
    out["integrity"] = integrity
    out["host"] = host or answers.get("host")
    return {**out, "state": state, "cmd": update_line(out, sha, integrity) if sha else None, "why_not": why_not, "live": sha}


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
OWNER_KEYS = ("owner_has_pr_template", "owner_has_issue_forms")


def shared_fetched(data, text) -> str:
    """An `api` answer as new-project.sh's gh_read writes it, for the
    functions in scripts/lib/shared-github.sh."""
    if data is ABSENT:
        return "err:HTTP 404 Not Found"
    if data is ERROR:
        return "err:offline or API error"
    got = text(data)
    return "err:an unexpected response" if got is None else "ok:" + got


def shared_decide(fn: str, *answers: str) -> str:
    """One decision of scripts/lib/shared-github.sh, run with bash, so the
    checker and the door decide alike; `unknown: <why>` when it cannot run."""
    try:
        r = subprocess.run(["bash", "-c", '. "$0" && "$@"', str(SHARED_GITHUB), fn, *answers],
                           capture_output=True, text=True, check=False)
    except OSError as e:
        return f"unknown: {fn} did not run ({e})"
    out = r.stdout.strip()
    return out if r.returncode == 0 and out else f"unknown: {fn} gave no answer ({r.stderr.strip()})"


def owner_dotgithub_public(owner: str, network: bool) -> str:
    """`shared_repo_public` on `<owner>/.github`: yes, no (private or none),
    or `unknown: <why>`. GitHub inherits from a public one only."""
    if not SHARED_GITHUB.is_file():
        return f"unknown: {SHARED_GITHUB} not found beside the checker"
    return shared_decide("shared_repo_public", shared_fetched(
        api(f"repos/{owner}/.github", network),
        lambda j: j.get("visibility") if isinstance(j, dict) and isinstance(j.get("visibility"), str) else None))


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
        if d["state"] == "current" and not d.get("move"):  # its own files: a recorded true changes nothing here
            d["cmd"] = None
        return
    if not owner:
        withdraw("no --repo, so whether the owner's .github publishes a pull-request template or issue forms was "
                 "not read; without that answer the update reads both as false and can write a form that hides "
                 "the owner's shared ones")
        return
    if not SHARED_GITHUB.is_file():
        withdraw(f"{SHARED_GITHUB} not found beside the checker, so the owner's .github could not be judged")
        return

    fetched, decide = shared_fetched, shared_decide

    def why(answer: str) -> str:
        return answer.removeprefix("unknown: ")

    shared = f"repos/{owner}/.github"
    vis = owner_dotgithub_public(owner, network)
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
    # A recorded true whose files the owner no longer publishes, in a
    # repository with none of its own: the update renders the template's
    # copies and records false (#770). The plan names it before it runs.
    recorded = copier_answers(root) or {}
    gone = [f"recorded {key}: true, but {owner}/.github no longer publishes {what} and this repository has none; "
            f"the update renders the template's {path} and records false"
            for key, has, own, what, path in (
                ("owner_has_pr_template", has_pr, own_pr, "a pull-request template", ".github/PULL_REQUEST_TEMPLATE.md"),
                ("owner_has_issue_forms", has_forms, own_forms, "issue forms", ".github/ISSUE_TEMPLATE"))
            if recorded.get(key) == "true" and has != "yes" and not own]
    notes.extend(gone)
    d["owner_data"] = (f" --data owner_has_pr_template={'true' if pr else 'false'}"
                       f" --data owner_has_issue_forms={'true' if forms else 'false'}")
    d["cmd"] = update_line(d, d["live"], d.get("integrity"))
    if d["state"] == "current" and not gone and not d.get("move"):
        d["cmd"] = None


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
    against the one the target tag was tested with (#511). The update
    always carries the live pin, so it never overwrites what Dependabot set
    (#219); a live pin older than the tested one is raised first, in a pull
    request of its own, and the update waits for it (#1183). `state` is
    behind (the tested pin is newer: the update waits), equal, live-ahead or
    unread (not compared: the update waits too, never proceeding as if the
    pin were current); `note` is the one line that says so, naming both SHAs
    when read. When behind, `tested` is the pin to raise to, `integrity` its
    GitLab checksum (or None, said in `note`), and `url` the compare."""
    live = d["live"].lower()
    calls = "the include is at" if d.get("integrity") else "the workflows call"
    target = d["target"]
    tested, why = tested_plinth_pin(d["template_repo"], target, network, at=d["target_sha"])
    if tested is None:
        return {"state": "unread", "note": f"plinth pin: the one {target} was tested with was not read ({why}), "
                                           f"so whether {live} is older was not read"}
    if tested == live:
        return {"state": "equal", "tested": tested,
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
        integrity, gap = None, ""
        if d.get("integrity"):
            # On GitLab the pin moves with the checksum the same tag was tested with.
            integrity, why = tested_plinth_pin(d["template_repo"], target, network,
                                               "plinth_gitlab_integrity", r"[A-Za-z0-9+/]{43}=", d["target_sha"])
            gap = "" if integrity else f" (its checksum was not read: {why})"
        return {"state": "behind", "tested": tested, "integrity": integrity, "url": url, "name": name(tested),
                "gitlab": bool(d.get("integrity")),
                "note": f"plinth pin: {calls} {name(live)}; {target} was tested with "
                        f"{name(tested)}{by}{tag_gap}{gap}: {url}"}
    if status == "behind":
        return {"state": "live-ahead", "tested": tested,
                "note": f"plinth pin: {calls} {name(live)}, newer than {name(tested)} that {target} "
                        f"was tested with; the update keeps it{tag_gap}: {url}"}
    why = ("the two commits have diverged" if status == "diverged"
           else "offline or API error" if cmp in (ABSENT, ERROR) else "an unexpected compare response")
    return {"state": "unread", "tested": tested,
            "note": f"plinth pin: {calls} {live}; {target} was tested with {tested}, but the two "
                    f"were not compared ({why})"}


def pin_pulls(repo: str, network: bool) -> tuple[list[tuple[int, str]] | None, str | None]:
    """The open pull requests of `repo` that change a coolbress/plinth
    `uses:` line in a workflow file (#1183): Dependabot's, or one a person
    opened. Read from each open pull request's files, the added lines of a
    `.github/workflows/` patch. Returns ([(number, title)], None), or
    (None, why) when a read failed: never an empty list for an unread one."""
    pulls = api(f"repos/{repo}/pulls?state=open&per_page=100", network, paginate=True)
    if not isinstance(pulls, list):
        return None, ("offline or API error" if pulls in (ABSENT, ERROR) else "an unexpected pulls response")
    found: list[tuple[int, str]] = []
    added = re.compile(r"^\+[ \t]*(-[ \t]*)?uses:[ \t]*[\"']?" + re.escape(PLINTH_REPO) + "/", re.MULTILINE | re.IGNORECASE)
    for p in pulls:
        n = p.get("number") if isinstance(p, dict) else None
        if not isinstance(n, int):
            return None, "an unexpected pulls response"
        files = api(f"repos/{repo}/pulls/{n}/files?per_page=100", network, paginate=True)
        if not isinstance(files, list):
            return None, f"the files of #{n}: " + ("offline or API error" if files in (ABSENT, ERROR) else "an unexpected response")
        if any(isinstance(f, dict) and str(f.get("filename", "")).startswith(".github/workflows/")
               and added.search(str(f.get("patch") or "")) for f in files):
            found.append((n, str(p.get("title") or "")))
    return found, None


def raise_first(root: Path, choice: dict, repo: str | None, network: bool) -> list[str]:
    """What to merge before the update, when the live pin is older than the
    tested one (#1183): the open pull request that changes the plinth
    `uses:` lines, by number, when `repo` is given and one is open; else the
    change to make in one pull request, every file that calls plinth moved
    to the same SHA (#793), or on GitLab the include's ref and checksum.
    Nothing here opens or changes anything."""
    tested = choice["tested"]
    out: list[str] = []
    if repo and not choice.get("gitlab"):
        found, why = pin_pulls(repo, network)
        if found:
            for n, title in found:
                out.append(f"merge first: #{n} {title}".rstrip() + f" (https://github.com/{repo}/pull/{n}), which changes "
                           f"the {PLINTH_REPO} uses: lines; if it raises them to an older commit than {tested}, raise them further")
            out.append("then plan the update again")
            return out
        out.append("no open pull request changes the plinth uses: lines" if why is None
                   else f"the open pull requests were not read ({why})")
    if choice.get("gitlab"):
        checksum = choice.get("integrity") or "(the checksum the tag was tested with, not read)"
        out.append(f"raise it first in one merge request of its own: .gitlab-ci.yml's {PLINTH_REPO} include to ref "
                   f"{tested} and integrity {checksum}; merge it, then plan the update again")
        return out
    files = plinth_pins(root)["names"] or ["ci.yml", "label.yml"]
    where = ", ".join(f".github/workflows/{f}" for f in files)
    out.append(f"raise it first in one pull request of its own: every {PLINTH_REPO} uses: line in {where} "
               f"to {choice['name']}, all at that one SHA; merge it, then plan the update again")
    return out


def check_template_drift(root: Path, network: bool, host: str | None = None, owner: str | None = None) -> None:
    """#219 stage 1: has the template plinth is tested with today moved past
    the tag this repository was rendered from? Reports the drift and an
    update command; runs nothing that writes. A PASS means only that the
    recorded tag is the target tag -- not that this repository's own render
    matches it file for file: another archetype, inherited forms or a
    hand-made edit can mean a changed template file was never rendered here."""
    d = template_drift(root, host, network)
    if d["state"] == "skip":
        emit("FC-F01", "unknown", "unread", {"reason": d["reason"]}, reason="template drift not read")
        return
    template_repo, target = d["template_repo"], d["target"]
    recorded = d["recorded"]
    if d["state"] == "ahead":
        emit("FC-F01", "info", "ahead", {"recorded": recorded, "target": target})
        return
    if d["state"] == "current":
        # A tag moved since this repository was rendered from it (#519).
        tag, now = target_tag(d, network)
        if tag == "moved":
            emit("FC-F01", "warn", "moved", {"target": target, "now": now, "sha": d["target_sha"]})
            return
        # The PASS claims the tags only; whether the tag still names its
        # commit is said beside it when unread, not counted: every offline
        # run would otherwise count it as not verified.
        emit("FC-F01", "pass", "good", {"target": target})
        if tag == "unread":
            emit("FC-F01", "info", "tag", {"target": target, "sha": d["target_sha"], "why": now})
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
        emit("FC-F01", "warn", "behindunread", {"recorded": recorded, "target": target, "why": unread_reason})
    else:
        names = sorted(f["filename"][len("template/"):] for f in changed)
        emit("FC-F01", "warn", "behind", {"recorded": recorded, "target": target,
                                          "names": ", ".join(names) if names else "(nothing under template/)"})
        emit("FC-F01", "info", "own")
        by_name = {f["filename"][len("template/"):]: f for f in changed}
        for name in TEMPLATE_DRIFT_DIFF_FILES:
            # Its source as named or with .jinja; a rename git did not pair
            # reads as the old one removed and the new one added: the added.
            found = [by_name[n] for n in (name, f"{name}.jinja") if isinstance(by_name.get(n), dict)]
            entry = next((e for e in found if e.get("status") != "removed"), found[0] if found else None)
            patch = entry.get("patch") if isinstance(entry, dict) else None
            if patch:
                emit("FC-F01", "info", "file", {"name": name})
                for pline in patch.splitlines():
                    emit("FC-F01", "info", "patch", {"line": pline})

    owner_shared(d, owner, network, root)
    if not d["cmd"]:
        emit("FC-F01", "info", "nocmd", {"why": d["why_not"]})
        if str(d["why_not"]).startswith("workflow pins disagree"):
            emit("FC-F01", "info", "pins")
        return
    for note in d.get("owner_notes", []):
        emit("FC-F01", "info", "line", {"line": note})
    tag, why = target_tag(d, network)
    if tag == "moved":
        emit("FC-F01", "warn", "movedcmd", {"line": moved_note(d, why)})
        return
    if tag == "unread":
        emit("FC-F01", "info", "cmdtag", {"target": target, "sha": d["target_sha"], "why": why})
    # A live pin older than the tested one is raised first, in a pull
    # request of its own (#1183): no line until then.
    choice = plinth_pin_choice(d, network)
    if choice["state"] == "behind":
        emit("FC-F01", "info", "line", {"line": choice["note"]})
        emit("FC-F01", "info", "raise")
        for line in raise_first(root, choice, None, network):
            emit("FC-F01", "info", "line", {"line": line})
        return
    emit("FC-F01", "info", "line", {"line": d["cmd"]})
    for line in moves_lines(d):
        emit("FC-F01", "info", "line", {"line": line})
    if choice["state"] == "equal":
        return
    emit("FC-F01", "info", "line", {"line": choice["note"]})
    if choice["state"] == "unread":
        emit("FC-F01", "info", "uncompared")


PLUGIN_UPDATE_STEPS = ("claude plugin marketplace update plinth", "claude plugin update plinth@plinth",
                       "/reload-plugins (or start a new session)", "/plinth:template-update")


def template_ref_at(ref: str, network: bool) -> tuple[str | None, str | None]:
    """The `template_ref` of scripts/new-project.sh at a plinth tag or commit,
    read as tested_plinth_pin reads a file at a ref: (tag, None), or (None,
    reason) when it is not read (#843)."""
    where = f"scripts/new-project.sh at {ref}"
    data = api(f"repos/{PLINTH_REPO}/contents/scripts/new-project.sh?ref={ref}", network)
    if data is ABSENT:
        return None, f"{where}: not found"
    if data is ERROR:
        return None, f"{where}: offline or API error"
    try:
        text = base64.b64decode(data["content"]).decode()
    except (TypeError, KeyError, ValueError):
        return None, f"{where}: an unexpected contents response"
    m = re.search(r'^template_ref="(v\d+\.\d+\.\d+)"$', text, re.MULTILINE)
    return (m.group(1), None) if m else (None, f"{where} has no template_ref that is a release tag")


def plugin_skew(root: Path, network: bool, host: str | None = None) -> dict:
    """The installed plinth against the newest template tag this project could
    move to (#843): the latest release's template_ref, or the tag its CI's
    plinth pin was tested with, whichever is newer. A project behind the first
    hears "nothing to do" from an older plugin. `state` is skip (not a door-made
    project), older (`newest`, `where`; `unreleased` when only the pin carries
    that tag, which updating the plugin cannot bring), same-or-newer or unread
    (`why`: the release was not read and the pin named nothing newer); `note`
    says the pin was not compared beside a release that was."""
    d = template_drift(root, host, network)
    if d["state"] == "skip":
        return {"state": "skip"}
    gitlab = (host or (copier_answers(root) or {}).get("host")) == "gitlab"
    out: dict = {"target": d["target"]}

    def key(tag: str) -> tuple[int, ...]:
        return tuple(int(x) for x in tag[1:].split("."))

    found: list[tuple[str, str]] = []
    released = None
    release = api(f"repos/{PLINTH_REPO}/releases/latest", network)
    tag = release.get("tag_name") if isinstance(release, dict) else None
    why = None
    if release is ABSENT:
        why = "not found"
    elif release is ERROR:
        why = "offline or API error"
    elif not isinstance(tag, str) or not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        why = "an unexpected release response"
    else:
        ref, why = template_ref_at(tag, network)
        if ref:
            found.append((ref, f"the latest plinth release, {tag}"))
            released = (tag, ref)

    if gitlab:
        pin, _, pin_unread = resolve_gitlab_pin(root)
    else:
        pin, pin_unread = resolve_plinth_pin(root)
    if not pin and not why:
        out["note"] = f"the CI pin was not compared ({pin_unread}); compared with the latest release alone"
    if pin:
        ref, pin_why = template_ref_at(pin, network)
        if ref:
            found.append((ref, f"the tag this repository's plinth pin {pin} was tested with"))
        elif not why:
            out["note"] = f"the tag the plinth pin {pin} was tested with was not read ({pin_why}); compared with the latest release alone"

    newest = max(found, key=lambda f: key(f[0]), default=None)
    if newest and key(newest[0]) > key(d["target"]):
        if released and key(newest[0]) > key(released[1]):
            out["unreleased"] = (f"{newest[0]} is in no release yet (the latest, {released[0]}, targets {released[1]}): "
                                 "if these find no new version, run /plinth:template-update again after the next release")
        return {**out, "state": "older", "newest": newest[0], "where": newest[1]}
    if why:
        return {**out, "state": "unread", "why": why}
    return {**out, "state": "same-or-newer"}


def plugin_skew_head(s: dict) -> str:
    return (f"this plinth targets template {s['target']}, but {s['newest']} is out ({s['where']}): "
            f"update the plugin first. Type these yourself, in order:")


def plugin_skew_unread(s: dict) -> str:
    return f"the latest plinth release was not read ({s['why']}); going on with the template tag this plinth targets, {s['target']}"


def check_plugin_skew(root: Path, network: bool, host: str | None = None) -> None:
    """Beside the template drift item: the same stop the template-update skill
    makes (#843). Not in `ci / floor-check`, whose checker is the pin's, not a
    plugin anyone installed."""
    s = plugin_skew(root, network, host)
    if s["state"] == "older":
        emit("FC-F02", "warn", "bad", {"head": plugin_skew_head(s)})
        # template-update.sh serves GitLab too (#1012), so the last step is the same on both hosts.
        for step in PLUGIN_UPDATE_STEPS:
            emit("FC-F02", "info", "step", {"step": step})
        if s.get("unreleased"):
            emit("FC-F02", "info", "unreleased", {"line": s["unreleased"]})
    elif s["state"] == "unread":
        emit("FC-F02", "info", "unread", {"line": plugin_skew_unread(s)})
    if s.get("note"):
        emit("FC-F02", "info", "note", {"note": s["note"]})


def print_plugin_skew(root: Path, network: bool = True, host: str | None = None) -> int:
    """--print-plugin-skew: for the template-update skill (#843). Exit 3 with
    the stop on stdout when the installed plinth targets an older tag; exit 0
    otherwise, a read that failed said on stderr."""
    s = plugin_skew(root, network, host)
    if s["state"] == "older":
        print(plugin_skew_head(s))
        for step in PLUGIN_UPDATE_STEPS:
            print(f"  {step}")
        if s.get("unreleased"):
            print(s["unreleased"])
        return 3
    if s["state"] == "unread":
        print(plugin_skew_unread(s), file=sys.stderr)
    if s.get("note"):
        print(s["note"], file=sys.stderr)
    return 0


def print_behind(root: Path, network: bool = True, host: str | None = None) -> int:
    """--print-behind: for /plinth:guide (#904), two lines, exit 0. The
    template line is the drift item's comparison (template_drift): the
    recorded tag against the tag this plinth targets, read from files. The
    pin line is the plinth commit the CI calls (resolve_plinth_pin, or the
    GitLab include) against plinth's latest release, by GitHub's compare. A
    read that fails, or a run without the network, is `not read (<why>)`,
    never a guess."""
    d = template_drift(root, host, network)
    target = d.get("target")
    if d["state"] == "skip":
        print(f"template: not read ({d['reason']})")
    elif d["state"] == "behind":
        print(f"template: {d['recorded']}, behind {target}, the tag this plinth targets")
    elif d["state"] == "ahead":
        print(f"template: {d['recorded']}, ahead of {target}, the tag this plinth targets")
    else:
        print(f"template: {d['recorded']}, the tag this plinth targets")

    if (host or (copier_answers(root) or {}).get("host")) == "gitlab":
        pin, _, why = resolve_gitlab_pin(root)
    else:
        pin, why = resolve_plinth_pin(root)
    if pin is None:
        print(f"plinth pin: not read ({why})")
        return 0
    pin = pin.lower()
    if not network:
        print(f"plinth pin: {pin}, not read against the latest release (no network read)")
        return 0
    release = api(f"repos/{PLINTH_REPO}/releases/latest", network)
    tag = release.get("tag_name") if isinstance(release, dict) else None
    if not isinstance(tag, str) or not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
        why = ("not found" if release is ABSENT else "offline or API error" if release is ERROR
               else "an unexpected release response")
        print(f"plinth pin: {pin}, not read against the latest release (the release: {why})")
        return 0
    # Page 2 of one commit: the status and counts without the file list,
    # which page 1 carries (half a megabyte across a few releases, measured).
    cmp = api(f"repos/{PLINTH_REPO}/compare/{pin}...{tag}?per_page=1&page=2", network)
    status = cmp.get("status") if isinstance(cmp, dict) else None
    if status == "ahead":
        n = cmp.get("ahead_by")
        by = f", {n} commit(s) behind" if isinstance(n, int) else ""
        print(f"plinth pin: {pin}, behind {tag}, the latest plinth release{by}")
    elif status == "identical":
        print(f"plinth pin: {pin}, at {tag}, the latest plinth release")
    elif status == "behind":
        print(f"plinth pin: {pin}, ahead of {tag}, the latest plinth release")
    else:
        why = ("the two have diverged" if status == "diverged" else "the compare was not found" if cmp is ABSENT
               else "offline or API error" if cmp is ERROR else "an unexpected compare response")
        print(f"plinth pin: {pin}, not read against {tag}, the latest plinth release ({why})")
    return 0


def print_update_command(root: Path, network: bool = True, host: str | None = None,
                         repo: str | None = None) -> int:
    """--print-update-command: the drift item's command line alone on
    stdout, exit 0; otherwise why there is none on stderr, exit 1. The line
    carries the live pin, and is printed only when that pin is not older
    than the one the target tag was tested with, read and compared (#1183):
    behind, stderr names the open pull request that raises it (with --repo)
    or the change to make; unread, it says what was not read. The
    comparison is a `plinth pin:` line on stderr whenever it was made. Each
    file the line moves forward to the ci job's commit is a `moves:` line on
    stderr (#793)."""
    owner = repo.split("/")[0] if repo else None
    d = template_drift(root, host, network)
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
    if d.get("cmd"):
        # Fail closed as well: a template tag never lands on a plinth older
        # than the one it was tested with (#511), by order (#1183).
        choice = plinth_pin_choice(d, network)
        if choice["state"] == "behind":
            print(f"no update command: the plinth pin is behind; {choice['note'][len('plinth pin: '):]}", file=sys.stderr)
            for line in raise_first(root, choice, repo, network):
                print(line, file=sys.stderr)
            return 1
        if choice["state"] == "unread":
            print(f"no update command: whether the plinth pin is older than the one {d['target']} was tested with "
                  f"was not read; {choice['note'][len('plinth pin: '):]}", file=sys.stderr)
            # A failed read may pass; a pin GitHub cannot order against the
            # tested one (diverged, or not a plinth commit) never will.
            to = f" to {choice['tested']} or a later plinth release" if choice.get("tested") else ""
            print(f"run it again if a read failed; otherwise raise the plinth pin{to} in a pull request of its own, "
                  "merge it, then plan the update again", file=sys.stderr)
            return 1
        print(choice["note"], file=sys.stderr)
        for line in moves_lines(d):
            print(line, file=sys.stderr)
        print(d["cmd"])
        return 0
    why = {
        "skip": lambda: f"template drift not verified ({d['reason']})",
        "ahead": lambda: f"the recorded tag {d['recorded']} is ahead of {d['target']}, the tag plinth is tested with",
        "current": lambda: f"the recorded tag is the target tag ({d['target']})" + (
            f"; a recorded owner answer is true, and no line re-renders for it: {d['why_not']}" if d.get("why_not")
            else ": nothing to update"),
        "behind": lambda: f"{d['recorded']} is behind {d['target']}, but there is no update command: {d['why_not']}",
    }[d["state"]]()
    print(f"no update command: {why}", file=sys.stderr)
    if d["state"] == "behind" and str(d.get("why_not", "")).startswith("workflow pins disagree"):
        for line in pins_disagree_stop(root, network):
            print(line, file=sys.stderr)
    return 1


def required_extra(archetype: str) -> set[str]:
    """The required checks an archetype adds to ruleset.json's, as
    ruleset_for adds them (web aside, which a move refuses)."""
    return {IMAGE_CHECK} if archetype in CONDITIONAL_ARCHETYPES else set()


def archetype_gained(repo: str, branch: str, archetype: str | None, answers: str, network: bool) -> tuple[set[str], str | None]:
    """The required checks the archetype this checkout records runs and the
    one <branch> records does not, with <branch>'s archetype (#1017): an
    archetype move under way, whose new check cannot be required before it
    has run on <branch> (require-check.sh refuses a name that never reported
    there). Empty when the two are the same or <branch>'s answers cannot be
    read: a missing check then stays a FAIL."""
    if not archetype:
        return set(), None
    data = api(f"repos/{repo}/contents/{answers}?ref={urllib.parse.quote(branch, safe='')}", network)
    if not (isinstance(data, dict) and data.get("encoding") == "base64" and isinstance(data.get("content"), str)):
        return set(), None
    try:
        text = base64.b64decode(data["content"]).decode("utf-8", errors="replace")
    except ValueError:
        return set(), None
    m = re.search(r"^archetype:\s*(\S+)", text, re.MULTILINE)
    old = m.group(1).strip("'\"") if m else None
    if not old or old == archetype:
        return set(), old
    return required_extra(archetype) - required_extra(old), old


# How a move's plan tells whether the plinth a project calls has the rule
# above: its floor-check.py at that commit carries this line (#1017).
GAINED_RULE = re.compile(r"^def archetype_gained\(", re.MULTILINE)


def gained_rule_at(cmd: str, network: bool) -> str:
    """Whether the move's own `ci / floor-check` passes a check the move adds
    (#1017): it runs the floor-check.py of the plinth commit the workflows
    call, which the line carries as plinth_sha. `held <sha>` when that file
    has the rule, `fails <sha>` when it does not, `unread <sha or ?> <why>`."""
    m = re.search(r"--data plinth_sha=([0-9a-fA-F]{40})\b", cmd)
    if not m:
        return "unread ? the line carries no plinth_sha"
    pin = m.group(1).lower()
    data = api(f"repos/{PLINTH_REPO}/contents/scripts/floor-check.py?ref={pin}", network)
    text = None
    if isinstance(data, dict) and data.get("encoding") == "base64" and isinstance(data.get("content"), str):
        try:
            text = base64.b64decode(data["content"]).decode("utf-8", errors="replace")
        except ValueError:
            text = None
    if text is None:
        return f"unread {pin} scripts/floor-check.py at that commit could not be read"
    return f"{'held' if GAINED_RULE.search(text) else 'fails'} {pin}"


# How a move's plan tells whether the python-ci.yml a project calls leaves
# release.yml out of ci / diff-size's count of an archetype move (#1044): the
# comment opening that rule in its Measure step.
SIZE_RULE = re.compile(r"^\s*# An archetype move \(#1044\)", re.MULTILINE)


def size_rule_at(cmd: str, network: bool) -> str:
    """Whether the move's own `ci / diff-size` leaves release.yml out of the
    count (#1044): it runs the python-ci.yml of the plinth commit the
    workflows call, which the line carries as plinth_sha. `held <sha>`,
    `fails <sha>` or `unread <sha or ?> <why>`, as gained_rule_at says."""
    m = re.search(r"--data plinth_sha=([0-9a-fA-F]{40})\b", cmd)
    if not m:
        return "unread ? the line carries no plinth_sha"
    pin = m.group(1).lower()
    data = api(f"repos/{PLINTH_REPO}/contents/.github/workflows/python-ci.yml?ref={pin}", network)
    text = None
    if isinstance(data, dict) and data.get("encoding") == "base64" and isinstance(data.get("content"), str):
        try:
            text = base64.b64decode(data["content"]).decode("utf-8", errors="replace")
        except ValueError:
            text = None
    if text is None:
        return f"unread {pin} .github/workflows/python-ci.yml at that commit could not be read"
    return f"{'held' if SIZE_RULE.search(text) else 'fails'} {pin}"


def print_move_command(root: Path, new: str, network: bool = True, host: str | None = None,
                       owner: str | None = None) -> int:
    """--print-update-command --move-archetype <new> (#1004): the line that
    re-renders this repository under another archetype at the tag it
    records, which must be the target tag: the drift item's same-tag line,
    the live plinth pin and the owner's answers as an update carries them,
    then `--data archetype=<new>`. copier update deletes the old archetype's
    files, changed by the project or not, with no conflict for a changed one
    (#1016), and keeps the project's own (measured, copier 9.18.2 and 9.19.1,
    data-ml to cli); template-update.sh stops on a changed one until the
    person says which to keep. On stderr, a `check-drop:`
    line for each required check the move stops and a `check-add:` line for
    each it starts, then one `check-add-floor:` line saying whether the
    plinth the workflows call passes the move's own floor check (#1017), and
    a `diff-size-move:` line saying whether its ci / diff-size leaves
    release.yml out of the move's count (#1044). Exit 1 with the reason when there is no line."""
    def no(why: str) -> int:
        print(f"no move command: {why}", file=sys.stderr)
        return 1

    answers = copier_answers(root)
    if not answers:
        return no("no .copier-answers.yml: not made by the door, so there is no recorded archetype to move from")
    old = answers.get("archetype")
    if not old:
        return no(".copier-answers.yml records no archetype to move from")
    # Which values are archetypes is the template's to say (its copier.yml),
    # so the line carries the value as given and copier judges it. Here only
    # the shape is held, so the value stays one word in the line.
    if not re.fullmatch(r"[a-z][a-z0-9-]*", new):
        return no(f"{new!r} is not an archetype's name (lower-case letters, digits and hyphens)")
    # `web` is left out both ways: a move to or from it also changes the
    # hosting answers, its two checks and the tag ruleset, none of it measured.
    # A move into `web` will also need --data custom_user_model=true, as
    # /plinth:new-project passes for a new web project (#1092): lifting this
    # refusal without it would start the moved project on Django's auth.User.
    if "web" in (old, new):
        return no("web is not moved to or from here: its hosting answers, its two checks and its tag ruleset "
                  "change with it, and that move was not measured; a move into web will also need custom_user_model=true (#1092)")
    # `dashboard` likewise (#1069): its `hosting` answer (local or render)
    # and the tag ruleset change with it, and that move was not measured.
    if "dashboard" in (old, new):
        return no("dashboard is not moved to or from here: its hosting answer (local or render) and the tag ruleset "
                  "change with it, and that move was not measured")
    if old == new:
        return no(f"the recorded archetype is already {new}")
    d = template_drift(root, host, network, move=True)
    if d["state"] == "skip":
        return no(f"template drift not verified ({d['reason']})")
    if d["state"] == "ahead":
        return no(f"the recorded tag {d['recorded']} is newer than {d['target']}, the tag plinth targets; "
                  f"move with the plinth that targets {d['recorded']}")
    if d["state"] != "current":
        return no(f"the recorded tag {d['recorded']} is not {d['target']}, the tag plinth targets; update the "
                  f"template first (/plinth:template-update), then move")
    owner_shared(d, owner, network, root)
    for note in d.get("owner_notes", []):
        print(note, file=sys.stderr)
    if not d.get("cmd"):
        return no(str(d.get("why_not") or "no line"))
    tag, why = target_tag(d, network)
    if tag != "pinned":
        return no(moved_note(d, why) if tag == "moved" else
                  f"not verified that {d['target']} still names {d['target_sha']}, the commit plinth was tested with ({why})")
    for line in moves_lines(d):
        print(line, file=sys.stderr)
    if (d.get("host") or "github") != "gitlab":
        for c in sorted(required_extra(old) - required_extra(new)):
            print(f"check-drop: {c}", file=sys.stderr)
        added = sorted(required_extra(new) - required_extra(old))
        for c in added:
            print(f"check-add: {c}", file=sys.stderr)
        if added:
            print(f"check-add-floor: {gained_rule_at(d['cmd'], network)}", file=sys.stderr)
        print(f"diff-size-move: {size_rule_at(d['cmd'], network)}", file=sys.stderr)
    print(f"{d['cmd']} --data archetype={new}")
    return 0


def check_doc_links(root: Path) -> None:
    link = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
    fenced = re.compile(r"```.*?```", re.DOTALL)
    inline = re.compile(r"`[^`\n]*`")
    docs = [p for p in root.rglob("*.md") if not (set(p.relative_to(root).parts) & SKIP_DIRS)]
    if not docs:
        emit("FC-A27", "fail", "none")
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
    verdict("FC-A27", not broken and not dangling, {"count": len(docs), "why": "; ".join(why)})


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
    for key in ("pyproject", "uvlock", "service"):
        emit("FC-C05", "not_applicable", key)
    bun = [n for n in BUN_LOCKFILES if (project / n).is_file()]
    if bun and not any((project / n).is_file() for n in NODE_LOCKFILES):
        emit("FC-C06", "info", "info", {"name": bun[0]})
    # What Render deploys does not depend on the language (#811 review).
    if (project / "render.yaml").is_file():
        check_render_blueprint(project / "render.yaml")


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
        emit("FC-C01", "fail", "found", {"one": one, "flag": flag})
    else:
        verdict("FC-C01", present)
        if below:
            emit("FC-C01", "info", "below", {"dirs": ", ".join(f"{d}/" for d in below)})
    # Once a project has been found below the root, both items speak about it.
    # The root holds no pyproject.toml, so a uv.lock sitting there is not that
    # project's lockfile: reporting it as one passed an item for a file that
    # belongs to nothing this run checks, while sending the reader to a project
    # where `--project=` reports it missing straight away (#238 review).
    if one:
        if (root / one / "uv.lock").is_file():
            emit("FC-C02", "fail", "found", {"one": one, "flag": flag})
        else:
            emit("FC-C02", "fail", "below", {"one": one})
    else:
        verdict("FC-C02", (project / "uv.lock").is_file())

    answers = copier_answers(project) or {}
    # A dashboard is on Render only when its answers say so: its default is
    # its own computer (plinth-template's `hosting: local`, #1069).
    on_render = (archetype == "web" and answers.get("hosting") != "elsewhere") or (
        archetype == "dashboard" and answers.get("hosting") == "render")
    # A render.yaml outside a Render web instance (another archetype, no
    # template, a hand-written one) is still what Render deploys from (#811):
    # read it when it is there, and say nothing when it is not.
    if not on_render and (project / "render.yaml").is_file():
        check_render_blueprint(project / "render.yaml")
    if archetype is None:
        emit("FC-C03", "unknown", "none", reason="no archetype")
        return
    if archetype not in CONDITIONAL_ARCHETYPES:
        emit("FC-C03", "info", "plain", {"archetype": archetype})
        if on_render:
            check_render_yaml(project, archetype)
        if archetype in PACKAGE_ARCHETYPES:
            # A repository-level file: GitHub reads workflows at the root, not
            # under --project, and the host is the one the run resolved,
            # --host before the answers (#720 review).
            check_release_workflow(root, host, archetype)
        return
    emit("FC-C03", "info", "service", {"archetype": archetype, "render": ", and render.yaml" if on_render else ""})
    check_dockerfile(project)
    check_env_example(project)
    check_json_logs(project)
    if on_render:
        check_render_yaml(project, archetype)
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
        emit("FC-C07", "pass", "good")
    else:
        emit("FC-C07", "warn", "bad")
        emit("FC-C07", "info", "update", {"since": RELEASES["data-ml"][1]})


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
        emit("FC-C08", "info", "gitlab", {"workflow": RELEASE_WORKFLOW})
        return
    p = root / RELEASE_WORKFLOW
    if not p.is_file():
        emit("FC-C08", "warn", "bad", {"workflow": RELEASE_WORKFLOW, "what": what})
        emit("FC-C08", "info", "update", {"since": since})
        return
    emit("FC-C08", "pass", "good", {"workflow": RELEASE_WORKFLOW})
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
        emit("FC-C09", "pass", "good", {"workflow": RELEASE_WORKFLOW})
    else:
        unread = next((line.strip() for line in lines if not re.fullmatch(r"  push:|    tags:.*|      - .*", line)),
                      None) if lines else "no on: block this checker reads"
        seen = unread or "push: without tags:"
        emit("FC-C09", "warn", "bad", {"workflow": RELEASE_WORKFLOW, "seen": seen})
    # secrets.GITHUB_TOKEN is the run's own token, made for the run and not stored.
    stored = [x for x in re.findall(r"secrets\.\w+|^\s*password:", text, re.MULTILINE) if x != "secrets.GITHUB_TOKEN"]
    if stored:
        emit("FC-C10", "warn", "bad", {"workflow": RELEASE_WORKFLOW, "instead": instead,
                                       "secrets": ", ".join(sorted({s.strip() for s in stored}))})
    else:
        emit("FC-C10", "pass", "good", {"workflow": RELEASE_WORKFLOW})
    if archetype == "data-ml":
        # The template names what a release uploads once, in `env: ASSETS:`.
        found = list(re.finditer(r"^([ \t]*)ASSETS:[ \t]*(.*)$", text, re.MULTILINE))
        if not found:
            emit("FC-C11", "unknown", "none", {"workflow": RELEASE_WORKFLOW}, reason="no ASSETS line")
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
            emit("FC-C11", "unknown", "form", {"workflow": RELEASE_WORKFLOW, "assets": m.group(2).strip()},
                 reason="ASSETS in a form not read")
            return
        pickles = [f for f in names if f.lower().endswith(PICKLE_SUFFIXES)]
        if pickles:
            emit("FC-C11", "warn", "bad", {"workflow": RELEASE_WORKFLOW, "pickles": ", ".join(pickles)})
        else:
            emit("FC-C11", "pass", "good", {"workflow": RELEASE_WORKFLOW, "assets": m.group(2).strip()})


def check_render_yaml(project: Path, archetype: str = "web") -> None:
    """The web archetype's Render Blueprint (plinth-template v1.20.0): the
    deploy that waits for the checks (#615). Asked of a `hosting: render`
    instance and of one with no hosting answer, rendered before the question
    existed (plinth-template#128); and of a dashboard whose answers say
    `hosting: render` (#1069)."""
    present = (project / "render.yaml").is_file()
    if archetype == "dashboard" and not present:
        emit("FC-C12", "fail", "dashboard")
        emit("FC-C12", "info", "restore")
        return
    if not verdict("FC-C12", present):
        emit("FC-C12", "info", "restore")
        return
    check_render_blueprint(project / "render.yaml")


class Unreadable(Exception):
    """A YAML form the block reader below does not read."""


def drop_comment(line: str) -> str:
    """The line without a trailing comment: a `#` after whitespace, outside a
    quoted value. A value is quoted only when its quote opens it, after `: `
    or `- ` (an apostrophe inside a word, `don't`, opens nothing), and `''`
    inside single quotes is an escaped quote."""
    quote, i = None, 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == quote and quote == "'" and line[i + 1:i + 2] == "'":
                i += 1
            elif c == quote:
                quote = None
            elif c == "\\" and quote == '"':
                i += 1
        elif c in "'\"" and re.fullmatch(r"\s*(- )*([^\s].*:\s+)?", line[:i]):
            quote = c
        elif c == "#" and (i == 0 or line[i - 1] in " \t"):
            return line[:i].rstrip()
        i += 1
    return line


def read_block_yaml(text: str):
    """The block-style YAML a Render Blueprint is written in: mappings, lists
    and plain or quoted scalars, standard library only. Anything else (a flow
    collection other than `[]` or `{}`, a block scalar, an anchor, an alias,
    a tag, a merge key, a nested list, a tab, a second document, a backslash
    escape in double quotes, key or value) raises Unreadable rather than being
    read as something it is not.

    Unreadable names the line number and the form, never what the line holds:
    the message becomes a SKIP line, which `ci / floor-check` publishes as an
    annotation and in the job summary, and the line may hold a secret."""
    lines: list[tuple[int, str, int]] = []
    for n, raw in enumerate(text.splitlines(), 1):
        if "\t" in raw[:len(raw) - len(raw.lstrip())]:
            raise Unreadable(f"line {n}: a tab in the indentation")
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped in ("---", "..."):
            if lines:
                raise Unreadable(f"line {n}: a second document")
            continue
        body = drop_comment(raw.rstrip())
        # Double quotes take escapes (`\u0065` is `e`), in a key as in a
        # value, which this reader does not decode.
        if '"' in body and "\\" in body:
            raise Unreadable(f"line {n}: a backslash escape in double quotes")
        lines.append((len(body) - len(body.lstrip()), body.strip(), n))

    def scalar(v: str, n: int):
        if v in ("[]", "{}"):
            return [] if v == "[]" else {}
        if v[0] in "[{|>&*!%@`":
            raise Unreadable(f"line {n}: a flow collection, block scalar, anchor, alias or tag")
        if v.startswith("- "):
            raise Unreadable(f"line {n}: a nested list")
        if v[0] not in "'\"" and ": " in v:
            raise Unreadable(f"line {n}: a plain value holding a colon and a space")
        if len(v) >= 2 and v[0] == v[-1] == '"':
            return v[1:-1]
        # Inside single quotes `''` is one quote.
        if len(v) >= 2 and v[0] == v[-1] == "'":
            return v[1:-1].replace("''", "'")
        if v[0] in "'\"":
            raise Unreadable(f"line {n}: a quote left open")
        return v

    def block(i: int, indent: int):
        if lines[i][1].startswith("- ") or lines[i][1] == "-":
            items = []
            while i < len(lines) and lines[i][0] == indent and (lines[i][1].startswith("- ") or lines[i][1] == "-"):
                n = lines[i][2]
                rest = lines[i][1][1:].lstrip()
                if not rest:
                    if i + 1 < len(lines) and lines[i + 1][0] > indent:
                        node, i = block(i + 1, lines[i + 1][0])
                    else:
                        node, i = None, i + 1
                elif re.match(r"""^([\w.-]+|"[^"]*"|'[^']*'):(\s|$)""", rest):
                    # `- key: v` opens a mapping whose keys sit where `key` does.
                    lines[i] = (indent + len(lines[i][1]) - len(rest), rest, n)
                    node, i = block(i, lines[i][0])
                else:
                    node, i = scalar(rest, n), i + 1
                items.append(node)
            return items, i
        mapping = {}
        while i < len(lines) and lines[i][0] == indent and not lines[i][1].startswith("- "):
            n = lines[i][2]
            m = re.fullmatch(r"""([\w.-]+|"[^"]*"|'[^']*'):(?:\s+(.*))?""", lines[i][1])
            if not m:
                raise Unreadable(f"line {n}: a line that is not `key: value` or `- item`")
            key = m.group(1).strip("'\"")
            if key in mapping:
                raise Unreadable(f"line {n}: a key given twice")
            i += 1
            if m.group(2):
                mapping[key] = scalar(m.group(2), n)
            elif i < len(lines) and (lines[i][0] > indent
                                     or (lines[i][0] == indent and lines[i][1].startswith("-"))):
                mapping[key], i = block(i, lines[i][0])
            else:
                mapping[key] = None
        return mapping, i

    if not lines:
        return {}
    if lines[0][0] != 0:
        raise Unreadable(f"line {lines[0][2]}: an indented first line")
    doc, end = block(0, 0)
    if end != len(lines):
        raise Unreadable(f"line {lines[end][2]}: indentation this reader does not follow")
    return doc


# An envVars key whose name says it holds a secret (#811). A literal `value:`
# for one sits in the repository, and in every clone of it.
SECRET_NAME = re.compile(r"SECRET|PASSWORD|PASSWD|TOKEN|API_?KEY|PRIVATE_?KEY|CREDENTIAL|DATABASE_URL|_DSN$",
                         re.IGNORECASE)


def check_render_blueprint(path: Path) -> None:
    """What a Render Blueprint says about the deploy (#811): every web service
    has a health check and deploys only after the checks pass, every database
    is on a paid plan (Render deletes a free Postgres after 30 days, and it
    has no backups), and no secret-named variable carries a literal value.
    plinth-template's render.yaml sets all four; this catches a file edited
    away from them, or one not made from the template. Each gap is a WARN with
    one fix line, never a FAIL; a file this reader does not read is a SKIP.
    Dashboard-only settings (Blueprint Auto Sync, monitors, spend) are not in
    the file and not read."""
    try:
        doc = read_block_yaml(read(path))
    except Unreadable as e:
        emit("FC-C13", "unknown", "form", {"why": e}, reason="a form not read")
        return
    if not isinstance(doc, dict):
        emit("FC-C13", "unknown", "mapping", reason="not a mapping")
        return
    # Resources can also sit under projects[].environments[] and ungrouped
    # (Render's root-level fields), which this reads no further: a file
    # using either is not read at all, rather than passed for what it left
    # out (#817 review).
    nested = [k for k in ("projects", "ungrouped") if k in doc]
    if nested:
        emit("FC-C13", "unknown", "layout", {"keys": " and ".join(nested)}, reason="a layout not read")
        return

    def entries(key: str) -> list:
        value = doc.get(key)
        return [e for e in value if isinstance(e, dict)] if isinstance(value, list) else []

    def name(entry: dict, i: int) -> str:
        given = entry.get("name")
        return given if isinstance(given, str) else f"#{i + 1}"

    webs = [(name(s, i), s) for i, s in enumerate(entries("services")) if s.get("type") == "web"]
    if not webs:
        emit("FC-C14", "info", "none")
    for svc, s in webs:
        path_ = s.get("healthCheckPath")
        if isinstance(path_, str) and path_.startswith("/"):
            emit("FC-C14", "pass", "good", {"svc": svc, "path": path_})
        else:
            emit("FC-C14", "warn", "bad", {"svc": svc})
            emit("FC-C14", "info", "add")
        trigger = s.get("autoDeployTrigger")
        if trigger == "checksPass":
            emit("FC-C15", "pass", "good", {"svc": svc})
        else:
            said = f"autoDeployTrigger: {trigger}" if isinstance(trigger, str) else "no autoDeployTrigger"
            emit("FC-C15", "warn", "bad", {"svc": svc, "said": said})
            emit("FC-C15", "info", "add")
    for i, d in enumerate(entries("databases")):
        db, plan = name(d, i), d.get("plan")
        if isinstance(plan, str) and plan and plan.lower() != "free":
            emit("FC-C16", "pass", "good", {"db": db, "plan": plan})
        else:
            said = f"is on plan {plan}" if isinstance(plan, str) and plan else "names no plan, so it is not read as a paid one"
            emit("FC-C16", "warn", "bad", {"db": db, "said": said})
            emit("FC-C16", "info", "add")
    # Under a service, or under a group several services share.
    env = [v for h in entries("services") + entries("envVarGroups")
           for v in (h.get("envVars") if isinstance(h.get("envVars"), list) else [])
           if isinstance(v, dict) and isinstance(v.get("key"), str)]
    literal = sorted({v["key"] for v in env if SECRET_NAME.search(v["key"]) and "value" in v})
    if not env:
        emit("FC-C17", "info", "none")
    elif literal:
        emit("FC-C17", "warn", "bad", {"keys": ", ".join(literal)})
        emit("FC-C17", "info", "add")
    else:
        emit("FC-C17", "pass", "good")


# The places whose README section tells a person to set up HTTPS, backups and
# closed ports themselves (plinth-template#128); no item here reads them.
SELF_RUN_PLACES = ("vps", "home")


def check_hosted_elsewhere(place: str | None) -> None:
    """`hosting: elsewhere` (#678): the template renders no render.yaml, and
    no item reads the chosen place's own setup."""
    emit("FC-C18", "info", "info", {"place": place or "no hosting_elsewhere answer"})
    if place in SELF_RUN_PLACES:
        emit("FC-C18", "info", "self", {"place": place})


def check_dockerfile(project: Path) -> None:
    d = project / "Dockerfile"
    if not verdict("FC-C19", d.is_file()):
        return
    text = read(d)
    froms = [re.sub(r"^--\S+\s+", "", f).split() for f in re.findall(r"^FROM\s+(.+)$", text, re.MULTILINE)]
    aliases = {parts[2] for parts in froms if len(parts) >= 3 and parts[1].upper() == "AS"}
    bases = [parts[0] for parts in froms if parts and parts[0] not in aliases and parts[0] != "scratch"]
    unpinned = [b for b in bases if "@sha256:" not in b]
    verdict("FC-C20", bool(froms) and not unpinned, {"unpinned": unpinned or "no FROM at all"})
    users = re.findall(r"^USER\s+(\S+)", text, re.MULTILINE)
    verdict("FC-C21", bool(users) and users[-1].split(":")[0] not in {"root", "0"})
    verdict("FC-C22", "uv sync --locked" in text)
    pkg = package_name(project)
    cmd = re.search(r"^CMD\s+\[(.+)\]", text, re.MULTILINE)
    parts = [p.strip().strip('"') for p in cmd.group(1).split(",")] if cmd else []
    entry = project / "src" / (pkg or "") / "__main__.py"
    verdict("FC-C23", parts[:2] == ["python", "-m"] and len(parts) > 2 and parts[2] == pkg and entry.is_file(),
            {"pkg": pkg, "parts": parts or "missing"})
    di = project / ".dockerignore"
    if verdict("FC-C24", di.is_file()):
        missing = [m for m in (".git", ".env", ".venv") if m not in read(di)]
        verdict("FC-C25", not missing, {"missing": missing})


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
        emit("FC-C26", "unknown", "nosrc", reason="no Python file under src/")
        return
    # Comments are dropped: `# TODO: add pythonjsonlogger` is not a setup. A string
    # is kept, because logging.config.dictConfig names its formatter in one.
    texts = {f.relative_to(project).as_posix(): re.sub(r"#.*", "", read(f)) for f in files}
    for rel, text in texts.items():
        for label, patterns in JSON_LOG_HINTS:
            if all(re.search(p, text) for p in patterns):
                emit("FC-C26", "pass", "good", {"rel": rel, "label": label})
                return
    logging_in = [rel for rel, text in texts.items()
                  if re.search(r"^\s*(?:import|from)\s+[^#\n]*\b(?:logging|structlog|loguru)\b", text, re.MULTILINE)]
    if logging_in:
        emit("FC-C26", "unknown", "unknown", {"files": ", ".join(logging_in)}, reason="logging not recognised")
        return
    entry = f"src/{package_name(project) or '<package>'}/__main__.py"
    emit("FC-C26", "warn", "bad", {"entry": entry})
    emit("FC-C26", "info", "add", {"entry": entry})


def check_image_job(root: Path) -> None:
    """The check the ruleset requires of a service archetype exists in the caller (#127)."""
    ci = root / ".github" / "workflows" / "ci.yml"
    text = read(ci) if ci.is_file() else ""
    m = re.search(r"^  image:\s*$", text, re.MULTILINE)
    # The job's own lines: up to the next two-space key. `buildx build` is a build too.
    block = re.split(r"^  \S", text[m.end():], maxsplit=1, flags=re.MULTILINE)[0] if m else ""
    verdict("FC-D06", m is not None and re.search(r"docker (buildx )?build", block) is not None and "docker run" in block)


def check_gitlab_image_job(root: Path) -> None:
    """A service archetype's .gitlab-ci.yml carries `docker-image`, the
    template's job that builds and runs the container (#127, #543)."""
    p = root / ".gitlab-ci.yml"
    text = read(p) if p.is_file() else ""
    m = re.search(rf"^{GITLAB_IMAGE_JOB}:\s*$", text, re.MULTILINE)
    block = re.split(r"^\S", text[m.end():], maxsplit=1, flags=re.MULTILINE)[0] if m else ""
    verdict("FC-D07", m is not None and re.search(r"docker (buildx )?build", block) is not None and "docker run" in block,
            {"job": GITLAB_IMAGE_JOB})


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
        emit("FC-D08", "unknown", "norule", {"what": what, "pipeline": GITLAB_PIPELINE.name}, reason="the rule not read")
        return
    with tempfile.TemporaryDirectory() as tmp:
        py, why = gitlab_rule_python(Path(tmp), network)
        if py is None:
            emit("FC-D08", "unknown", "nopython", {"what": what, "why": why}, reason="no python for the rule")
            return
        config = str(root / ".gitlab-ci.yml")
        if text is not None:
            config = str(Path(tmp) / "definition.yml")
            Path(config).write_text(text, encoding="utf-8")
        try:
            run = subprocess.run([py, "-c", rule], cwd=tmp, capture_output=True, text=True,
                                 env={**os.environ, "CONFIG": config}, timeout=60, check=False)
        except (OSError, subprocess.TimeoutExpired) as e:
            emit("FC-D08", "unknown", "norun", {"what": what, "error": e.__class__.__name__}, reason="the rule did not run")
            return
    lines = [ln.replace(config, shown) for ln in run.stdout.splitlines() if ln.strip()]
    states = {"pass": "pass", "fail": "fail", "not yet confirmed": "unknown"}
    for ln in lines:
        kind, _, msg = ln.partition(": ")
        if kind in states:
            emit("FC-D08", states[kind], "rule", {"msg": msg},
                 reason="the rule did not confirm it" if states[kind] == "unknown" else None)
        else:
            emit("FC-D08", "unknown", "printed", {"what": what, "line": repr(ln[:200])}, reason="the rule printed no verdict")
    if not lines:
        why = " ".join(run.stderr.split())[-200:] or f"exit {run.returncode}"
        emit("FC-D08", "unknown", "silent", {"what": what, "why": why}, reason="the rule printed no verdict")


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
        emit("FC-E01", "unknown", "unread", {"repo": repo, "why": why}, reason="the project not read")
        check_gitlab_include(root, network)
        return
    branch = project.get("default_branch")
    if not isinstance(branch, str) or not branch:
        emit("FC-E01", "unknown", "nobranch", {"repo": repo}, reason="no default branch named")
        return

    # Every rule whose name or wildcard pattern matches the branch applies, and
    # GitLab takes the most permissive of them (#548 review): a `*` rule that
    # lets Developers push opens `main` whatever its own rule says. On Premium
    # the list carries the parent group's rules too (`inherited: true`), and
    # they count the same way.
    rules = gl_api(f"projects/{enc}/protected_branches?per_page=100", network, paginate=True)
    if not isinstance(rules, list):
        emit("FC-E01", "unknown", "rules", {"branch": branch}, reason="protected branches not read")
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
        values = {"branch": branch, "repo": repo, "host": GITLAB_HOST, "enc": enc, "edit": edit, "names": names}
        if not applying:
            emit("FC-E01", "fail", "none", values)
            emit("FC-E01", "info", "create", values)
        else:
            if not push or any(a.get("access_level") != 0 for a in push) or named(push):
                bad.append(f"push allowed ({described(push)}), want No one")
            if not merge or any(not isinstance(a.get("access_level"), int) or a.get("access_level") < 40 for a in merge) or named(merge):
                bad.append(f"merge allowed to {described(merge)}, want Maintainers")
            force = [r.get("allow_force_push") for r in applying if r.get("allow_force_push") is not False]
            if force:
                bad.append(f"force push {force[0]!r}, want false")
            if bad:
                emit("FC-E01", "fail", "weak", {**values, "bad": "; ".join(bad)})
                emit("FC-E01", "info", "edit", values)
            else:
                emit("FC-E01", "pass", "good", values)

    # Each group is judged on the fields GitLab returned (#548 review, round 2):
    # a readable mismatch is a FAIL even when another field is missing, and
    # only the missing fields are a SKIP.
    merge_url = f"https://{GITLAB_HOST}/{repo}/-/settings/merge_requests"
    groups = (
        ("FC-E02", {"only_allow_merge_if_pipeline_succeeds": True, "allow_merge_on_skipped_pipeline": False}),
        ("FC-E03", {"squash_option": "always", "merge_method": "ff"}),
    )
    for cid, want in groups:
        off = {k: project[k] for k, v in want.items() if k in project and project[k] != v}
        absent = [k for k in want if k not in project]
        values = {"repo": repo, "host": GITLAB_HOST, "enc": enc, "url": merge_url}
        if off:
            emit(cid, "fail", "bad", {**values, "off": ", ".join(f"{k}={v!r}" for k, v in off.items())})
            emit(cid, "info", "hint", values)
        if absent:
            emit(cid, "unknown", "absent", {**values, "fields": ", ".join(absent),
                                            "them": "it" if len(absent) == 1 else "them"},
                 reason="not returned to this login")
        if not off and not absent:
            emit(cid, "pass", "good", values)

    # The definition GitLab runs: ci_config_path, .gitlab-ci.yml when empty.
    # One in another project or at a URL (`path@group/project`, http) is not read.
    cfg = project.get("ci_config_path") or ".gitlab-ci.yml"
    shown = f"{cfg} on {branch}"
    if "@" in cfg or "://" in cfg:
        emit("FC-E04", "unknown", "outside", {"branch": branch, "cfg": cfg}, reason="outside this project")
    else:
        text = gl_api(f"projects/{enc}/repository/files/{urllib.parse.quote(cfg, safe='')}/raw?ref="
                      f"{urllib.parse.quote(branch, safe='')}", network, raw=True)
        if text is ABSENT:
            emit("FC-E04", "fail", "absent", {"cfg": cfg, "branch": branch, "repo": repo})
        elif not isinstance(text, str):
            emit("FC-E04", "unknown", "error", {"branch": branch, "cfg": cfg}, reason="an API error")
        else:
            check_gitlab_include(root, network, text, shown)

    labels = gl_api(f"projects/{enc}/labels?per_page=100", network, paginate=True)
    f = labels_file()
    if f is None:
        emit("FC-E05", "unknown", "nofile", reason="labels.txt not found")
    elif not isinstance(labels, list):
        emit("FC-E05", "unknown", "unread", reason="labels not read")
    else:
        rows = [ln.split("|") for ln in read(f).splitlines() if ln.strip() and not ln.lstrip().startswith("#")]
        have = {e.get("name") for e in labels if isinstance(e, dict)}
        missing = [r for r in rows if r[0] not in have]
        if not missing:
            emit("FC-E05", "pass", "good", {"count": len(rows)})
        else:
            emit("FC-E05", "warn", "bad", {"missing": ", ".join(r[0] for r in missing)})
            for r in missing:
                emit("FC-E05", "info", "glab", {"name": shlex.quote(r[0]), "colour": r[1], "repo": repo})


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
    if not verdict("FC-C27", e.is_file()):
        return
    pattern = re.compile(r"""os\.(?:environ\s*\[\s*|environ\.get\s*\(\s*|getenv\s*\(\s*)['"]([A-Z_][A-Z0-9_]*)['"]""")
    used = {m for f in (project / "src").rglob("*.py") for m in pattern.findall(read(f))} if (project / "src").is_dir() else set()
    documented = set(re.findall(r"^\s*#?\s*([A-Z_][A-Z0-9_]*)\s*=", read(e), re.MULTILINE))
    missing = sorted(used - documented)
    verdict("FC-C28", not missing, {"missing": missing})


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
        emit("FC-E05", "unknown", "nofile", reason="labels.txt not found")
        return
    want = [ln.split("|")[0] for ln in read(f).splitlines()
            if ln.strip() and not ln.lstrip().startswith("#")]
    colour = {ln.split("|")[0]: ln.split("|")[1] for ln in read(f).splitlines()
              if ln.strip() and not ln.lstrip().startswith("#")}
    data = api(f"repos/{repo}/labels?per_page=100", network, paginate=True)
    if data is ERROR or not isinstance(data, list):
        # Unreadable is not empty. Reporting every label missing because the API
        # failed is the fail-open case in reverse, and just as useless.
        emit("FC-E05", "unknown", "unread", reason="labels not read")
        return
    have = {e.get("name") for e in data if isinstance(e, dict)}
    missing = [n for n in want if n not in have]
    if not missing:
        emit("FC-E05", "pass", "good", {"count": len(want)})
        return
    emit("FC-E05", "warn", "bad", {"missing": ", ".join(missing)})
    for n in missing:
        emit("FC-E05", "info", "gh", {"name": n, "repo": repo, "colour": colour[n]})


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
        emit("FC-E22", "unknown", "nopolicy", {"branch": branch}, reason="no --ruleset")
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
        emit("FC-E22", "fail", "bad", {"branch": branch, "weak": ", ".join(weak)})
        for rid in sorted({t["ruleset_id"] for t in tools if t.get("ruleset_id")}):
            emit("FC-E22", "info", "edit", {"repo": repo, "rid": rid})
    if unread:
        emit("FC-E22", "unknown", "unread", {"branch": branch, "fields": ", ".join(unread)},
             reason="a threshold not read")
    if not weak and not unread:
        emit("FC-E22", "pass", "good", {"branch": branch, "alerts": live["alerts_threshold"],
                                        "security": live["security_alerts_threshold"],
                                        "want_alerts": policy["alerts_threshold"],
                                        "want_security": policy["security_alerts_threshold"]})


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


def hidden_security(repo: str, meta: dict, network: bool, actions_token: bool) -> str | None:
    """Why a private repository answers no security settings to a login that
    administers it, as far as this run can tell (#1002); None when that is not
    the case. GitHub gives the same empty answer for a plan without its paid
    products (measured on a personal account's private repository, #811) and
    for a token without the Administration permission, which is how plinth has
    the agent work after the first merge; `meta` carries the login's role,
    never the token's permissions. So "plan" (cannot be read here) only when
    the token is shown to read an admin-only setting, the Actions permissions;
    otherwise "token", plain not verified, with the fix line naming a token
    with Administration. Not read under --actions-token, whose answers on
    these items are INFOs left to the skill."""
    perms = meta.get("permissions")
    if actions_token or not (meta.get("security_and_analysis") is None and is_private(meta)
                             and isinstance(perms, dict) and perms.get("admin") is True):
        return None
    actions = api(f"repos/{repo}/actions/permissions", network)
    readable = isinstance(actions, dict) and actions.get("allowed_actions") in ("all", "local_only", "selected")
    return "plan" if readable else "token"


ADMIN_TOKEN_FIX = ("  run /plinth:floor-check again with a token that has the Administration permission (read): "
                   "GitHub answers a token without it as it answers a plan without the paid security products")


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


def check_push_protection(repo: str, meta: dict, actions_token: bool = False, hidden: str | None = None) -> None:
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
        emit("FC-E09", "review", "review", reader=ADMIN_READER)
        return
    if hidden == "plan":
        # Measured on a personal account's private repository (#811): GitHub
        # leaves the settings out even for its administrator when no
        # security product is on offer there. Still not read, so a SKIP.
        emit("FC-E09", "unknown", "plan", reason=HERE)
        return
    if hidden == "token":
        emit("FC-E09", "unknown", "token", reason="the security settings not answered")
        emit("FC-E09", "info", "admin", {"line": ADMIN_TOKEN_FIX})
        return
    if security is None:
        emit("FC-E09", "unknown", "unread", reason="the security settings not read")
        return
    entry = security.get("secret_scanning_push_protection") if isinstance(security, dict) else None
    status = entry.get("status") if isinstance(entry, dict) else None
    protection = product_status(meta, "secret_scanning") if is_private(meta) else "enabled"
    if status == "enabled":
        emit("FC-E09", "pass", "good")
    elif protection == "disabled":
        emit("FC-E09", "info", "gap", {"turn_on": TURN_ON})
    elif status == "disabled" and protection is None:
        emit("FC-E09", "unknown", "nostatus", reason="no secret scanning status")
    elif status == "disabled":
        emit("FC-E09", "warn", "bad")
        # The body the door sends, both fields: push protection is a part of
        # secret scanning. As JSON on stdin, the form set-security-setting.sh
        # writes and reads back, so it does not depend on how a gh version
        # reads `-f a[b][c]=v`.
        body = json.dumps({"security_and_analysis": {k: {"status": "enabled"}
                                                     for k in ("secret_scanning", "secret_scanning_push_protection")}})
        emit("FC-E09", "info", "hint", {"repo": repo, "body": body})
        emit("FC-E09", "info", "bypass")
    else:
        emit("FC-E09", "unknown", "none", reason="no push protection status")


# The two routes plinth-template's SECURITY.md names (#747), by the line
# that opens each: the form on a public repository, an issue on a private one.
ROUTE_FORM = "Use the repository's private reporting form"
ROUTE_ISSUE = "Open an issue in this repository. It is private"


def check_security_route(root: Path, private: bool) -> None:
    """Does SECURITY.md send a reporter where this repository can take a
    report (#747)? A private repository is not offered the form, and a
    public repository's issues are public. An instance rendered before the
    template asked `visibility` and updated with `--defaults` gets `public`,
    the form, whatever the repository is (measured on a v1.32.0 instance,
    copier 9.18.2). A file naming neither route is someone's own: not judged."""
    f = root / "SECURITY.md"
    text = read(f) if f.is_file() else ""
    if private and ROUTE_FORM in text:
        emit("FC-E10", "warn", "form")
        emit("FC-E10", "info", "form_fix")
    elif not private and ROUTE_ISSUE in text:
        emit("FC-E10", "warn", "issue")
        emit("FC-E10", "info", "issue_fix")


def check_private_reporting(repo: str, meta: dict, network: bool, actions_token: bool = False,
                            root: Path | None = None) -> None:
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
    if root is not None and meta.get("private") in (True, False):
        check_security_route(root, is_private(meta))
    if is_private(meta):
        emit("FC-E11", "info", "private")
        return
    got = api(f"repos/{repo}/private-vulnerability-reporting", network)
    enabled = got.get("enabled") if isinstance(got, dict) else None
    if enabled is True:
        emit("FC-E11", "pass", "good")
    elif enabled is False:
        emit("FC-E11", "warn", "bad")
        emit("FC-E11", "info", "hint", {"repo": repo})
    elif actions_token:
        emit("FC-E11", "review", "review", reader=ADMIN_READER)
    else:
        emit("FC-E11", "unknown", "unread", reason="no answer read")


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
    return any(isinstance(p, str) and not p.startswith("!") and fnmatch.fnmatchcase(v, p.lower()) for p in patterns)


def read_allowlist(repo: str, network: bool):
    """(permissions, allowed_actions, selected-actions) as GitHub answers
    them; (None, None, None) when not read. selected-actions is read only
    when the policy is `selected`."""
    perms = api(f"repos/{repo}/actions/permissions", network)
    allowed = perms.get("allowed_actions") if isinstance(perms, dict) else None
    selected = api(f"repos/{repo}/actions/permissions/selected-actions", network) if allowed == "selected" else None
    if allowed not in ("all", "local_only", "selected") or (allowed == "selected" and not isinstance(selected, dict)):
        return None, None, None
    return perms, allowed, selected


def refused_by(uses: list[tuple[str, int, str]], allowed: str, selected) -> tuple[list[tuple[str, int, str]], list[str]]:
    """The uses (file, line, value; no docker:// image, no local ./ path)
    the policy refuses, and its patterns_allowed."""
    if allowed == "all":
        return [], []
    if allowed == "local_only":
        return list(uses), []
    assert isinstance(selected, dict)
    listed = selected.get("patterns_allowed")
    patterns = [p for p in listed if isinstance(p, str)] if isinstance(listed, list) else []
    owned = selected.get("github_owned_allowed") is True
    return [(f, n, v) for f, n, v in uses
            if not (owned and v.split("/", 1)[0].lower() in GITHUB_OWNED) and not allowlist_allows(v, patterns)], patterns


def print_refused_actions(root: Path, repo: str | None, network: bool = True) -> int:
    """--print-refused-actions (#1018): for template-update.sh's archetype
    move, run on the rehearsal of the move. The door allows only the actions
    of the archetype it renders (new-project.sh), and a move changes files,
    not the setting. One line per finding on stdout: `refused: <file> line
    <n> <action>` for each use the allowlist refuses, then `allow: <command>`,
    the gh call that allows them (patterns_allowed is replaced as a whole, so
    it carries the patterns already there, in the -f form new-project.sh
    uses, which reads nothing from stdin: with-admin-token.sh reads the token
    from stdin when there is no terminal); `allowed: <n>` when every use
    starts; `skip: <why>` for what is not judged (an image, a uses: this
    checker cannot read, a blocking pattern). Exit 1 with the reason on
    stderr when the allowlist is not read."""
    if not repo:
        print("no --repo: the Actions allowlist is a repository's setting", file=sys.stderr)
        return 1
    uses: list[tuple[str, int, str]] = []
    skips: list[str] = []
    for p in workflow_files(root):
        rel = p.relative_to(root).as_posix()
        for n, v, readable in iter_uses(read(p)):
            if not readable:
                skips.append(f"{rel} line {n}: a uses: in a form this checker does not read")
            elif v.startswith("docker://"):
                skips.append(f"{rel} line {n} {v}: whether the allowlist lets an image run is not judged")
            elif not v.startswith("./"):
                uses.append((rel, n, v))
    perms, allowed, selected = read_allowlist(repo, network)
    if perms is None:
        print("GitHub gave no answer this checker reads; a login with repository administration reads it", file=sys.stderr)
        return 1
    if perms.get("enabled") is False:
        print("skip: GitHub Actions is turned off on this repository: no workflow runs")
        return 0
    refused, patterns = refused_by(uses, allowed, selected)
    blocking = [p for p in patterns if p.startswith("!")]
    if blocking and uses:
        skips.append("it carries the blocking pattern" + ("s " if len(blocking) > 1 else " ") + ", ".join(blocking)
                     + ", and GitHub documents no order between blocking and allowing patterns")
    for s in skips:
        print(f"skip: {s}")
    for f, n, v in refused:
        print(f"refused: {f} line {n} {v.split('@', 1)[0]}")
    if not refused:
        if not skips:
            print(f"allowed: {len(uses)}")
        return 0
    if allowed != "selected":
        print(f"allow: gh api -X PUT repos/{repo}/actions/permissions -F enabled=true -f allowed_actions=selected")
        return 0
    assert isinstance(selected, dict)
    add = sorted({v.split("@", 1)[0] + "@*" for _, _, v in refused})
    words = ["gh", "api", "-X", "PUT", f"repos/{repo}/actions/permissions/selected-actions",
             "-F", f"github_owned_allowed={'true' if selected.get('github_owned_allowed') is True else 'false'}",
             "-F", f"verified_allowed={'true' if selected.get('verified_allowed') is True else 'false'}"]
    for pat in [*patterns, *add]:
        words += ["-f", f"patterns_allowed[]={pat}"]
    print("allow: " + " ".join(shlex.quote(w) for w in words))
    return 0


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
    one is not measured. A `uses` the line pattern cannot read (iter_uses)
    is a SKIP that names its line, and the all-actions PASS is not printed
    beside it, as check_action_pins does: it could name a refused action.
    A `!` pattern blocks what it matches (#756). GitHub's page shows it
    beside allowing patterns (`space-org/*, !space-org/action@*`) but gives
    no order between them or against github_owned_allowed, so a policy that
    carries one is a SKIP naming it, and never the all-actions PASS. An
    action no allowing pattern matches is still refused: `!` only blocks.
    WARN, never FAIL, as push protection."""
    if not network and not os.environ.get("FLOOR_CHECK_API_DIR"):
        return  # the wall's own SKIP says offline
    uses: list[tuple[str, int, str]] = []
    unread: list[tuple[str, int]] = []
    for p in workflow_files(root):
        rel = p.relative_to(root).as_posix()
        for n, v, readable in iter_uses(read(p)):
            if not readable:
                unread.append((rel, n))
            elif not v.startswith("./"):
                uses.append((rel, n, v))
    if not uses and not unread:
        return
    perms, allowed, selected = read_allowlist(repo, network)
    if perms is None:
        if actions_token:
            emit("FC-E27", "review", "review", reader=ADMIN_READER)
        else:
            emit("FC-E27", "unknown", "unread", reason="the Actions permissions not read")
        return
    if perms.get("enabled") is False:
        emit("FC-E27", "warn", "off")
        return
    docker = [(f, n, v) for f, n, v in uses if v.startswith("docker://")]
    uses = [(f, n, v) for f, n, v in uses if not v.startswith("docker://")]
    refused, patterns = refused_by(uses, allowed, selected)
    for f, n, v in docker:
        emit("FC-E27", "unknown", "docker", {"file": f, "line": n, "value": v}, reason="an image not judged")
    for f in sorted({f for f, _ in unread}):
        lines = ", ".join(str(n) for g, n in unread if g == f)
        emit("FC-E27", "unknown", "form", {"file": f, "lines": lines}, reason="uses in a form not read")
    blocking = [p for p in patterns if p.startswith("!")]
    if blocking and uses:
        emit("FC-E27", "unknown", "blocking", {"s": "s" if len(blocking) > 1 else "", "patterns": ", ".join(blocking)},
             reason="a blocking pattern")
    if not refused:
        if uses and not unread and not blocking:
            emit("FC-E27", "pass", "good", {"count": len(uses)})
        return
    emit("FC-E27", "warn", "bad", {"refused": ", ".join(f"{f} line {n} {v.split('@', 1)[0]}" for f, n, v in refused)})
    if allowed != "selected":
        emit("FC-E27", "info", "select", {"repo": repo})
        return
    assert isinstance(selected, dict)
    add = sorted({v.split("@", 1)[0] + "@*" for _, _, v in refused})
    body = json.dumps({"github_owned_allowed": selected.get("github_owned_allowed") is True,
                       "verified_allowed": selected.get("verified_allowed") is True,
                       "patterns_allowed": [*patterns, *add]})
    emit("FC-E27", "info", "allow", {"repo": repo, "body": shlex.quote(body)})


# The archetypes that release from a `v*` tag, and get the door's tag
# ruleset (ruleset-tags.json, #772): every one but `web`, which deploys on
# green, and `dashboard`, which runs where it is started or deploys on green
# (#1069). The exception is named, not the list: the template owns the
# archetypes (tests/archetype-single-source.sh). `*-v*` is a uv workspace
# member's own tag, `<prefix>-v<version>` (#931), whatever its prefix.
TAG_NOT_RELEASING = ("web", "dashboard")
TAG_RULESET = {"name": "tags: v* and *-v* not moved or deleted", "target": "tag", "enforcement": "active",
               "bypass_actors": [],
               "conditions": {"ref_name": {"include": ["refs/tags/v*", "refs/tags/*-v*"], "exclude": []}},
               "rules": [{"type": "deletion"}, {"type": "update"}]}


def check_actions_token(repo: str, network: bool, actions_token: bool = False) -> None:
    """The token a workflow gets without naming permissions reads only, and
    no workflow approves a pull request: what the door sets (#772) instead of
    GitHub's default, which an owner's settings change. Read with repository
    administration; a token without it is a SKIP, or an INFO left to the
    skill under --actions-token. WARN, never FAIL: a repository made before
    #772 relied on the default, and `ci / floor-check` runs in each one."""
    if not network and not os.environ.get("FLOOR_CHECK_API_DIR"):
        return
    w = api(f"repos/{repo}/actions/permissions/workflow", network)
    if not isinstance(w, dict) or "default_workflow_permissions" not in w:
        if actions_token:
            emit("FC-E28", "review", "review", reader=ADMIN_READER)
        else:
            emit("FC-E28", "unknown", "unread", reason="the Actions settings not read")
        return
    off = []
    if w.get("default_workflow_permissions") != "read":
        off.append(f"a workflow that names no permissions gets a token that can write "
                   f"(default_workflow_permissions: {w.get('default_workflow_permissions')})")
    if w.get("can_approve_pull_request_reviews") is not False:
        off.append("a workflow can approve a pull request (can_approve_pull_request_reviews: "
                   f"{json.dumps(w.get('can_approve_pull_request_reviews'))})")
    if not off:
        emit("FC-E28", "pass", "good")
        return
    emit("FC-E28", "warn", "bad", {"off": "; ".join(off)})
    emit("FC-E28", "info", "hint", {"repo": repo})


# What a token needs to read each of the items below, as GitHub's table of
# fine-grained token permissions gives it (read 2026-11-28): the alerts'
# on/off and security updates under "Administration", the open Dependabot
# alerts under "Dependabot alerts", the open secret scanning alerts under
# "Secret scanning alerts", repository secrets' names under "Secrets" and an
# environment's under "Environments". A classic token or gh's own login
# needs `repo`. No endpoint here returns a secret's value; the secret
# scanning alert does carry it, and it is never kept or printed.
SEVERITIES = ("critical", "high", "medium", "low")
# A release workflow that publishes through OIDC (it asks for the identity
# token, and a step publishes with it), and the secret names a token for that
# same registry goes by. Only the registry the workflow publishes to through
# OIDC is matched: a token for another registry (an image's, an npm publish
# without provenance) may still be in use.
OIDC_REGISTRIES = (
    (re.compile(r"pypa/gh-action-pypi-publish|\buv publish\b"), re.compile(r"PYPI|TWINE|UV_PUBLISH", re.IGNORECASE)),
    (re.compile(r"\bnpm publish\b.*--provenance"), re.compile(r"NPM|NODE_AUTH", re.IGNORECASE)),
)


def unread(cid: str, actions_token: bool, values: dict, reason: str) -> None:
    """An answer not read: left to the skill under --actions-token, otherwise a SKIP."""
    if actions_token:
        emit(cid, "review", "review", reader=ADMIN_READER)
    else:
        emit(cid, "unknown", "unread", values, reason=reason)


def check_dependabot_alerts(repo: str, meta: dict, network: bool, actions_token: bool) -> None:
    """Dependabot alerts on, and how many are open, by severity (#1118). The
    on/off is a 204 or a 404 on repos/{r}/vulnerability-alerts, and GitHub
    answers 404 as well to a login that does not administer the repository:
    a 404 is "off" only when the repository's answer says this login does.
    Count and severity only; GitHub only (FC-A19 is GitLab's line)."""
    on = api(f"repos/{repo}/vulnerability-alerts", network)
    admin = isinstance(meta.get("permissions"), dict) and meta["permissions"].get("admin") is True
    if on is ABSENT and admin and not actions_token:
        emit("FC-E31", "warn", "off")
        emit("FC-E31", "info", "hint", {"repo": repo})
        return
    if not isinstance(on, dict):
        unread("FC-E31", actions_token, {"what": "whether they are on was not answered", "permission": "Administration"},
               "Dependabot alerts not read")
        return
    alerts = api(f"repos/{repo}/dependabot/alerts?state=open&per_page=100", network, paginate=True)
    if not isinstance(alerts, list):
        unread("FC-E31", actions_token, {"what": "they are on; the open alerts were not read",
                                         "permission": "Dependabot alerts"}, "the open Dependabot alerts not read")
        return
    sev = [((a.get("security_advisory") or {}).get("severity") or (a.get("security_vulnerability") or {}).get("severity"))
           for a in alerts if isinstance(a, dict) and a.get("state", "open") == "open"]
    if not sev:
        emit("FC-E31", "pass", "good")
        return
    counts = [f"{sev.count(s)} {s}" for s in SEVERITIES if s in sev]
    other = sum(s not in SEVERITIES for s in sev)
    emit("FC-E31", "warn", "open", {"count": len(sev),
                                    "severities": ", ".join(counts + ([f"{other} of no severity"] if other else []))})
    emit("FC-E31", "info", "list", {"repo": repo})


def check_security_updates(repo: str, network: bool, actions_token: bool) -> None:
    """Dependabot security updates on (#1118): repos/{r}/automated-security-fixes
    answers `enabled` and `paused`. Anything else is not read."""
    got = api(f"repos/{repo}/automated-security-fixes", network)
    enabled = got.get("enabled") if isinstance(got, dict) else None
    if enabled is True and got.get("paused") is not True:
        emit("FC-E32", "pass", "good")
    elif enabled is True:
        emit("FC-E32", "warn", "paused")
        emit("FC-E32", "info", "hint", {"repo": repo})
    elif enabled is False:
        emit("FC-E32", "warn", "off")
        emit("FC-E32", "info", "hint", {"repo": repo})
    elif actions_token:
        emit("FC-E32", "review", "review", reader=ADMIN_READER)
    else:
        emit("FC-E32", "unknown", "unread", reason="Dependabot security updates not read")


def alert_place(repo: str, number, network: bool) -> str:
    """Where an open secret scanning alert's secret is: the first location's
    path, or its kind (an issue comment, an Actions log); never the value."""
    locs = api(f"repos/{repo}/secret-scanning/alerts/{number}/locations", network)
    first = locs[0] if isinstance(locs, list) and locs and isinstance(locs[0], dict) else None
    if first is None:
        return "where not read"
    details = first.get("details")
    path = details.get("path") if isinstance(details, dict) else None
    if isinstance(path, str) and path:
        return f"in {path}"
    kind = str(first.get("type") or "place").replace("_", " ")
    return f"in {'an' if kind[:1] in 'aeiou' else 'a'} {kind}"


def check_secret_scanning(repo: str, meta: dict, network: bool, actions_token: bool, hidden: str | None) -> None:
    """Secret scanning on, and its open alerts named by type and where, never
    by value (#1118). The status is in `security_and_analysis`, as push
    protection's is (FC-E09), which reports an unanswered block once for
    both; a private repository without GitHub Secret
    Protection has it off by plan, an INFO naming the plan. With alerts open
    the row is the alerts, not "on"."""
    security = meta.get("security_and_analysis")
    if not isinstance(security, dict) or hidden is not None:
        # The settings were not answered: push protection's line (FC-E09)
        # reports that one read, a SKIP, its plan or an INFO left to the
        # skill, and a second line here would count the same answer twice.
        return
    entry = security.get("secret_scanning")
    status = entry.get("status") if isinstance(entry, dict) else None
    if status == "disabled" and is_private(meta):
        emit("FC-E33", "info", "gap", {"turn_on": TURN_ON})
        return
    if status == "disabled":
        emit("FC-E33", "warn", "off")
        body = json.dumps({"security_and_analysis": {"secret_scanning": {"status": "enabled"}}})
        emit("FC-E33", "info", "hint", {"repo": repo, "body": body})
        return
    if status != "enabled":
        unread("FC-E33", actions_token, {"what": "its status was not answered", "permission": "Administration"},
               "secret scanning not read")
        return
    alerts = api(f"repos/{repo}/secret-scanning/alerts?state=open&per_page=100&hide_secret=true", network,
                 paginate=True)
    if not isinstance(alerts, list):
        unread("FC-E33", actions_token, {"what": "it is on; the open alerts were not read",
                                         "permission": "Secret scanning alerts"}, "the open secret scanning alerts not read")
        return
    open_ = [a for a in alerts if isinstance(a, dict) and a.get("state", "open") == "open"]
    if not open_:
        emit("FC-E33", "pass", "good")
        return
    # Only the type and the place are taken from each alert. The request asks
    # GitHub to leave the value out (hide_secret), and its `secret` field,
    # should one come back, is never read into a message.
    named = [f"{a.get('secret_type_display_name') or a.get('secret_type') or 'a secret'} "
             f"{alert_place(repo, a.get('number'), network)}" for a in open_[:10]]
    more = f"; {len(open_) - 10} more" if len(open_) > 10 else ""
    emit("FC-E33", "warn", "open", {"count": len(open_), "where": "; ".join(named) + more})
    emit("FC-E33", "info", "list", {"repo": repo})


def check_registry_secrets(root: Path, repo: str, network: bool, actions_token: bool) -> None:
    """Secrets named like a registry token while release.yml publishes through
    OIDC (#1118): names only, from the repository and each environment; a
    value is never read (GitHub returns none). Experimental, a WARN at most:
    the names are a guess at what a secret holds."""
    rel = root / RELEASE_WORKFLOW
    text = read(rel) if rel.is_file() else ""
    names = [n for publish, n in OIDC_REGISTRIES if publish.search(text)]
    if not (re.search(r"id-token:\s*write", text) and names):
        return

    def listed(got) -> bool:
        """A whole list of secrets: more than one page is not read, so not listed."""
        return (isinstance(got, dict) and isinstance(got.get("secrets"), list)
                and not (isinstance(got.get("total_count"), int) and got["total_count"] > len(got["secrets"])))

    repo_secrets = api(f"repos/{repo}/actions/secrets?per_page=100", network)
    if not listed(repo_secrets):
        unread("FC-E34", actions_token, {"what": "the repository's secrets were not listed", "permission": "Secrets"},
               "the secret names not read")
        return
    found = [(s.get("name"), None) for s in repo_secrets["secrets"] if isinstance(s, dict)]
    envs = api(f"repos/{repo}/environments?per_page=100", network)
    if envs is ABSENT:
        envs = {"environments": []}
    if not isinstance(envs, dict) or not isinstance(envs.get("environments"), list) or (
            isinstance(envs.get("total_count"), int) and envs["total_count"] > len(envs["environments"])):
        unread("FC-E34", actions_token, {"what": "the environments were not listed", "permission": "Actions"},
               "the environments not read")
        return
    for env in envs["environments"]:
        name = env.get("name") if isinstance(env, dict) else None
        got = api(f"repos/{repo}/environments/{name}/secrets?per_page=100", network) if name else None
        if not listed(got) or not isinstance(got, dict):
            unread("FC-E34", actions_token, {"what": f"environment {name}'s secrets were not listed",
                                             "permission": "Environments"}, "an environment's secret names not read")
            return
        found += [(s.get("name"), name) for s in got["secrets"] if isinstance(s, dict)]
    tokens = [(n, e) for n, e in found if isinstance(n, str) and any(r.search(n) for r in names)]
    if not tokens:
        emit("FC-E34", "pass", "good")
        return
    emit("FC-E34", "warn", "bad", {"names": ", ".join(f"{n} ({'environment ' + e if e else 'repository'})"
                                                      for n, e in tokens)})
    for n, e in tokens:
        emit("FC-E34", "info", "hint", {"line": f"gh secret delete {n} --repo {repo}" + (f" --env {e}" if e else "")})


def check_security_reads(root: Path, repo: str, network: bool, actions_token: bool) -> None:
    """The admin reads of #1118, after the wall: alerts, security updates,
    secret scanning and the registry token names."""
    if not network and not os.environ.get("FLOOR_CHECK_API_DIR"):
        return
    meta = api(f"repos/{repo}", network)
    if not isinstance(meta, dict):
        return   # FC-E06 has said the repository was not read
    hidden = hidden_security(repo, meta, network, actions_token)
    check_dependabot_alerts(repo, meta, network, actions_token)
    check_security_updates(repo, network, actions_token)
    check_secret_scanning(repo, meta, network, actions_token, hidden)
    check_registry_secrets(root, repo, network, actions_token)


# The patterns that cover every `v*` tag: the door's, and the two wider ones.
TAG_NAMESPACE = ("refs/tags/v*", "refs/tags/*", "~ALL")


def excludes_a_v_tag(pattern: str) -> bool:
    """Could this exclude pattern match some `v*` tag? Only a pattern that
    names a tag starting with a literal other than `v` is known not to."""
    if not pattern.startswith("refs/tags/"):
        return pattern == "~ALL" or any(c in pattern for c in "*?[")
    first = pattern[len("refs/tags/"):][:1]
    return first in ("", "v", "*", "?", "[", "\\")


def own_tag_prefixes(project: Path) -> dict[str, str] | None:
    """The members of a uv workspace released on their own tags (#931):
    `own-tags` under [tool.plinth.release] in pyproject.toml, each member's
    name and its prefix, read as the release workflow reads it, whatever the
    TOML spelling. Nothing when there is no such list; None when there may
    be one that cannot be read here (a Python without tomllib and a file
    that says `own-tags`, a file that is not TOML, a list that is not a
    table of strings)."""
    f = project / "pyproject.toml"
    if not f.is_file():
        return {}
    text = read(f)
    try:  # tomllib is Python 3.11's; these scripts also run on older ones
        data = importlib.import_module("tomllib").loads(text)
    except (ImportError, ValueError):
        return None if "own-tags" in text else {}
    node: object = data
    for k in ("tool", "plinth", "release"):
        node = node.get(k, {}) if isinstance(node, dict) else None
    if not isinstance(node, dict):
        return None
    listed = node.get("own-tags", {})
    if not isinstance(listed, dict) or not all(isinstance(v, str) for v in listed.values()):
        return None
    return {str(k): v for k, v in listed.items()}


def covers_prefix(pattern: str, prefix: str) -> bool:
    """Does this include pattern match every `<prefix>v*` tag? A pattern
    with `?` or `[` is never taken to: it names some of them at most."""
    if pattern == "~ALL":
        return True
    if not pattern.startswith("refs/tags/") or any(c in pattern for c in "?["):
        return False
    return fnmatch.fnmatchcase(f"refs/tags/{prefix}v*", pattern)


def excludes_prefix(pattern: str, prefix: str) -> bool:
    """Could this exclude pattern match some `<prefix>v*` tag? Its literal
    start and `<prefix>v` must agree as far as both go."""
    if not pattern.startswith("refs/tags/"):
        return pattern == "~ALL" or any(c in pattern for c in "*?[")
    rest, lit = pattern[len("refs/tags/"):], f"{prefix}v"
    head = re.split(r"[*?\[\\]", rest, maxsplit=1)[0]
    if head == rest:
        return rest.startswith(lit)
    return lit.startswith(head) or head.startswith(lit)


def tag_ruleset_covers(rs: dict, prefix: str | None = None) -> tuple[list[str], bool]:
    """What a tag ruleset leaves open of what TAG_RULESET closes, and whether
    its bypass actors were read. No gaps when it is active, includes the
    whole `v*` namespace (TAG_NAMESPACE, not a sample tag: `refs/tags/v1.0.0`
    alone matches one release), excludes nothing a `v*` tag could match,
    blocks deletion and update, and lets no actor bypass it. `non_fast_forward`
    is not `update`: it lets a tag move to a later commit. Bypass actors are
    returned only to a token that administers the repository; without the
    key they are unread, never taken as none. With a `prefix`, the namespace
    is a listed member's own tags, `<prefix>v*` (#931), in place of `v*`."""
    gaps = []
    if rs.get("enforcement") != "active":
        gaps.append(f"enforcement is {rs.get('enforcement')}")
    cond = (rs.get("conditions") or {}).get("ref_name") or {}
    inc = [p for p in cond.get("include") or [] if isinstance(p, str)]
    exc = [p for p in cond.get("exclude") or [] if isinstance(p, str)]
    if prefix is None:
        if not any(p in TAG_NAMESPACE for p in inc):
            gaps.append(f"it includes {inc or 'nothing'}, not every v* tag (refs/tags/v*)")
        open_exc = [p for p in exc if excludes_a_v_tag(p)]
        if open_exc:
            gaps.append(f"it excludes {open_exc}, which can match a v* tag")
    else:
        if not any(covers_prefix(p, prefix) for p in inc):
            gaps.append(f"it includes {inc or 'nothing'}, not every {prefix}v* tag (refs/tags/{prefix}v*)")
        open_exc = [p for p in exc if excludes_prefix(p, prefix)]
        if open_exc:
            gaps.append(f"it excludes {open_exc}, which can match a {prefix}v* tag")
    types = {r.get("type") for r in rs.get("rules") or [] if isinstance(r, dict)}
    gaps += [f"no {t} rule" for t in ("deletion", "update") if t not in types]
    actors = rs.get("bypass_actors")
    if isinstance(actors, list) and actors:
        gaps.append("bypass actors present: " + ", ".join(
            f"{a.get('actor_type')} {a.get('actor_id')} ({a.get('bypass_mode')})" for a in actors if isinstance(a, dict)))
    return gaps, isinstance(actors, list)


def judge_tag_rulesets(repo: str, archetype: str, rulesets: list[tuple[object, dict]], unread: bool,
                       actions_token: bool, member: tuple[str, str] | None = None) -> None:
    """One item: whether one of the tag rulesets read keeps the `v*` tags,
    or with `member` (its name and prefix) that member's own tags, from
    being moved or deleted."""
    best: list[str] | None = None
    actors_unread: object = None
    tags = f"{member[1]}v*" if member else "v*"
    for rid, rs in rulesets:
        gaps, actors_read = tag_ruleset_covers(rs, member[1] if member else None)
        if not gaps and actors_read:
            emit("FC-E29", "pass", "good", {"tags": tags, "rid": rid})
            return
        if not gaps:
            actors_unread = rid
            continue
        best = gaps if best is None or len(gaps) < len(best) else best
    if actors_unread is not None:
        if actions_token:
            emit("FC-E29", "review", "review", {"rid": actors_unread, "tags": tags}, reader=ADMIN_READER)
        else:
            emit("FC-E29", "unknown", "actors", {"rid": actors_unread, "tags": tags}, reason="bypass actors not read")
        return
    if unread and best is None:
        emit("FC-E29", "unknown", "unread", reason="a tag ruleset not read")
        return
    why = f"the tag rulesets here leave {tags} tags open: {'; '.join(best)}" if best else "no tag ruleset"
    if member:
        emit("FC-E29", "warn", "member", {"why": why, "name": member[0], "tags": tags})
        body = {**TAG_RULESET, "name": f"tags: {tags} not moved or deleted",
                "conditions": {"ref_name": {"include": [f"refs/tags/{tags}"], "exclude": []}}}
    else:
        emit("FC-E29", "warn", "bad", {"why": why, "archetype": archetype})
        body = TAG_RULESET
    emit("FC-E29", "info", "create", {"repo": repo, "body": shlex.quote(json.dumps(body))})


def check_tag_ruleset(repo: str, archetype: str | None, network: bool, actions_token: bool = False,
                      project: Path | None = None) -> None:
    """A releasing archetype's `v*` tags can be neither moved nor deleted
    (#772): a moved tag changes what a release names, a deleted one makes it
    vanish. Rulesets are listed with read access; their bypass actors need
    administration, so a ruleset that covers everything else and whose
    actors are unread is a SKIP (an INFO left to the skill under
    --actions-token), never a PASS. WARN, never FAIL, as the merge ruleset:
    every repository made before #772 lacks it, and `ci / floor-check` runs
    in each one. A member that pyproject.toml lists under
    [tool.plinth.release] own-tags (#931) is one more item, for its own
    `<prefix>v*` tags: a repository made before them protects `v*` only."""
    if archetype is None or archetype in TAG_NOT_RELEASING or (not network and not os.environ.get("FLOOR_CHECK_API_DIR")):
        return
    listed = api(f"repos/{repo}/rulesets?per_page=100", network, paginate=True)
    if listed is ERROR or (listed is not ABSENT and not isinstance(listed, list)):
        emit("FC-E29", "unknown", "unlisted", reason="the rulesets not listed")
        return
    rulesets: list[tuple[object, dict]] = []
    unread = False
    for item in listed if isinstance(listed, list) else []:
        if not isinstance(item, dict) or item.get("target") != "tag" or item.get("source_type", "Repository") != "Repository":
            continue
        rs = api(f"repos/{repo}/rulesets/{item.get('id')}", network)
        if isinstance(rs, dict):
            rulesets.append((item.get("id"), rs))
        else:
            unread = True
    judge_tag_rulesets(repo, archetype, rulesets, unread, actions_token)
    members = own_tag_prefixes(project) if project is not None else {}
    if members is None:
        emit("FC-E29", "unknown", "members", reason="own-tags not read")
        return
    for name, prefix in sorted(members.items()):
        judge_tag_rulesets(repo, archetype, rulesets, unread, actions_token, (name, prefix))


def check_description(repo: str, network: bool) -> None:
    """The line under the repository's name, which GitHub's community profile
    counts. Asked at creation and skippable (#772), and not recorded in the
    answers, so an empty one is said, never a miss."""
    if not network and not os.environ.get("FLOOR_CHECK_API_DIR"):
        return
    meta = api(f"repos/{repo}", network)
    if not isinstance(meta, dict) or "description" not in meta:
        return
    if (meta.get("description") or "").strip():
        emit("FC-E30", "pass", "good")
    else:
        emit("FC-E30", "info", "none", {"repo": repo})


def answered_true(answers: dict[str, str], key: str) -> bool:
    return answers.get(key, "").lower() == "true"


def check_answers(root: Path, owner: str | None, network: bool, host: str = "github") -> None:
    """The project against the answers it was made with (#772): each answer
    in .copier-answers.yml that turns something on, and the file it renders
    or relies on. An answer that turns something off is not a miss, and an
    answer not recorded is not read. WARN, never FAIL: the fix is the
    person's, and an older instance records fewer answers."""
    answers = copier_answers(root)
    if not answers:
        return
    if answered_true(answers, "third_party_review") and host == "github":
        caller = root / ".github" / "workflows" / "third-party.yml"
        if not verdict("FC-F03", caller.is_file(), bad="warn"):
            emit("FC-F03", "info", "hint")
    want_own = answered_true(answers, "code_of_conduct") and not (
        host == "github" and answered_true(answers, "owner_has_code_of_conduct"))
    if want_own and not verdict("FC-F04", (root / "CODE_OF_CONDUCT.md").is_file(), bad="warn"):
        emit("FC-F04", "info", "hint")
    if host == "github":
        # The owner's copy, answered at creation and relied on since: still
        # published, or this repository has none in effect. Issue forms are
        # judged in the document set above, local or inherited.
        for cid, key, name in OWNER_COPIES:
            if answered_true(answers, key):
                check_owner_copy(cid, root, owner, network, key, name)


def check_owner_copy(cid: str, root: Path, owner: str | None, network: bool, key: str, name: str) -> None:
    """`<key>: true` and the owner's `.github` still publishing `name` at one
    of the three places GitHub reads it from, unless the repository has its
    own, which applies in its place."""
    places = (name, f".github/{name}", f"docs/{name}")
    values = {"key": key, "name": name, "owner": owner}
    if any((root / p).is_file() for p in places):
        emit(cid, "pass", "own", values)
        return
    if owner is None:
        emit(cid, "unknown", "norepo", values, reason="no --repo")
        return
    vis = owner_dotgithub_public(owner, network)
    if vis.startswith("unknown"):
        emit(cid, "unknown", "visibility", {**values, "why": vis.removeprefix("unknown: ")},
             reason="visibility of the owner's .github not read")
        return
    if vis != "yes":
        emit(cid, "warn", "private", values)
        emit(cid, "info", "again")
        return
    found, failed = False, False
    for path in places:
        got = inherited_file(owner, path, network)
        if isinstance(got, str):
            found = True
            break
        failed = failed or got is ERROR
    if found:
        emit(cid, "pass", "good", values)
    elif failed:
        emit(cid, "unknown", "unread", values, reason="offline or API error")
    else:
        emit(cid, "warn", "gone", values)
        emit(cid, "info", "again")


def check_wall(repo: str, expected: list[str], merge_methods: set[str], policy: dict[str, str] | None, network: bool,
               sources: dict[str, int | None] | None = None, actions_token: bool = False,
               merge: dict | None = None, not_applying: list[str] | None = None, root: Path | None = None,
               archetype: str | None = None, answers: str = ".copier-answers.yml") -> None:
    """archetype: the one this checkout records (None when --archetype
    overrode it), compared with the one the default branch records at
    <answers> for a check an archetype move gains (#1017).

    not_applying: on a JavaScript or TypeScript repository (#681), the
    expected checks only python-ci.yml runs, already left out of `expected`.
    When nothing is left, the required-checks rule is not asked for either,
    and CodeQL's default setup is asked to analyse that language, not Python."""
    if not network and not os.environ.get("FLOOR_CHECK_API_DIR"):
        emit("FC-E06", "unknown", "offline", reason="offline")
        return
    meta = api(f"repos/{repo}", network)
    if meta in (ABSENT, ERROR) or not isinstance(meta, dict):
        if meta is ABSENT:
            emit("FC-E06", "fail", "absent", {"repo": repo})
        else:
            emit("FC-E06", "unknown", "error", {"repo": repo}, reason="an API error")
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
        emit("FC-E07", "unknown", "nobranch", reason="no default branch reported")
        branch = "main"
    else:
        emit("FC-E07", "info", "where", {"branch": branch})
    # WARN, never FAIL. `ci / floor-check` runs with --repo in every consumer's
    # CI, so a FAIL here blocks their merges -- and a repository whose default
    # is deliberately `master` or `trunk` is not broken, it just is not what the
    # door builds. Naming it is the whole job; deciding for them is not (#106,
    # the same reasoning that keeps a missing label a WARN in #84).
    if branch is not None and branch != "main":
        emit("FC-E07", "warn", "notmain", {"branch": branch})
        emit("FC-E07", "info", "hint", {"repo": repo})
    # The squash commit is the pull request (title and description), not a
    # list of the branch's commits. The door sets it; a button merge in the
    # web UI uses it. The fields are visible to a token with push access.
    title, msg = meta.get("squash_merge_commit_title"), meta.get("squash_merge_commit_message")
    # The Actions token in `ci / floor-check` never sees them (#440): an INFO
    # left to the skill there, as push protection below, not a SKIP no
    # consumer can clear.
    if title is None and msg is None and actions_token:
        emit("FC-E08", "review", "review", reader=ADMIN_READER)
    elif title is None and msg is None:
        emit("FC-E08", "unknown", "unread", reason="squash commit settings not read")
    else:
        verdict("FC-E08", title == "PR_TITLE" and msg == "PR_BODY", {"title": title, "msg": msg})
    hidden = hidden_security(repo, meta, network, actions_token)
    check_push_protection(repo, meta, actions_token, hidden)
    check_private_reporting(repo, meta, network, actions_token, root)
    rules = api(f"repos/{repo}/rules/branches/{branch}", network)
    # The merge line is printed on these two paths as well (#583): the skill's
    # summary relays it, and the role alone decides much of it.
    if rules is ERROR:
        emit("FC-E12", "unknown", "unread", {"branch": branch}, reason="an API error")
        if merge is not None:
            check_merge_setup(branch, meta, "unread", actions_token)
        return
    if rules is ABSENT or not rules:
        due = wall_later()
        if due:
            emit("FC-E12", "info", "later", {"branch": branch, "due": due})
        else:
            emit("FC-E12", "fail", "none", {"branch": branch})
        if merge is not None:
            check_merge_setup(branch, meta, "no rules", actions_token)
        return
    by_type = {r["type"]: r for r in rules}
    checks = not not_applying or bool(expected)
    for cid, t in WALL_RULES:
        if t != "required_status_checks" or checks:
            verdict(cid, t in by_type, {"branch": branch})

    pr = by_type.get("pull_request", {}).get("parameters", {})
    methods = set(pr.get("allowed_merge_methods", []))
    verdict("FC-E17", bool(methods) and methods <= merge_methods,
            {"branch": branch, "allowed": sorted(merge_methods), "methods": sorted(methods) or "unknown"})

    # Strict when any active required-checks rule is strict: GitHub enforces
    # each rule, so one strict rule already requires a current branch.
    strict = any(r.get("parameters", {}).get("strict_required_status_checks_policy") is True
                 for r in rules if r.get("type") == "required_status_checks")
    if not_applying:
        emit("FC-E19", "not_applicable", "na", {"branch": branch, "checks": ", ".join(not_applying)})
    if checks:
        verdict("FC-E18", strict, {"branch": branch})
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
    # A check the archetype gains in this checkout and not on the default
    # branch (#1017): the move's own pull request, where it cannot be
    # required yet. Said with the command, never passed; once the default
    # branch records the archetype too, it is a missing check as any other.
    gained, old = archetype_gained(repo, branch, archetype, answers, network) if checks and missing else (set(), None)
    held = [c for c in missing if c in gained]
    missing = [c for c in missing if c not in gained]
    for c in held:
        emit("FC-E19", "unknown", "held", {"branch": branch, "check": c, "archetype": archetype, "old": old, "repo": repo},
             reason="an archetype move")
    if not checks or (held and not missing):
        pass
    elif not verdict("FC-E19", not missing, {"branch": branch, "count": len(expected), "missing": missing}) \
            and sources is not None and all(sources.get(c) is not None for c in missing):
        # The script only adds checks, and asks for repository administration.
        emit("FC-E19", "info", "hint", {"repo": repo, "pairs": " ".join(shlex.quote(f"{c}:{sources[c]}") for c in missing)})
    # Which app may report each check is part of the wall. Without the pin, a
    # commit status of the same name, which anyone with write access can post,
    # satisfies the requirement.
    # Each check is compared with its own expected app, so a ruleset that pins
    # checks to different apps is still compared check by check.
    if not checks:
        pass
    elif sources is None:
        emit("FC-E20", "info", "nocompare", {"branch": branch})
    else:
        bad = unknown = 0
        for c in expected:
            if c not in live:
                unknown += 1   # reported above as dropped; the PASS cannot speak for it
                continue
            want = sources.get(c)
            if want is None:
                emit("FC-E20", "unknown", "unknown", {"branch": branch, "check": c}, reason="no expected app")
                unknown += 1
                continue
            if want in live[c]:
                continue
            bad += 1
            if None in live[c]:
                emit("FC-E20", "fail", "any", {"branch": branch, "check": c, "want": want})
            else:
                got = ", ".join(str(i) for i in sorted(i for i in live[c] if i is not None))
                emit("FC-E20", "fail", "other", {"branch": branch, "check": c, "got": got, "want": want})
        apps = sorted({v for v in sources.values() if v is not None})
        # A PASS speaks for every expected check; with one uncompared it would not.
        if not bad and not unknown and apps:
            label = "app" if len(apps) == 1 else "apps"
            emit("FC-E20", "pass", "good", {"branch": branch, "label": label, "apps": ", ".join(map(str, apps))})

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
        verdict("FC-E21", bool(tools) or by_name, {"branch": branch, "how": "rule" if tools else "check name"})
    elif scanning == "disabled":
        emit("FC-E21", "info", "gap", {"branch": branch, "turn_on": TURN_ON})
    elif meta.get("security_and_analysis") is None and actions_token:
        emit("FC-E21", "review", "review", {"branch": branch}, reader=ADMIN_READER)
    elif hidden == "plan":
        emit("FC-E21", "unknown", "plan", {"branch": branch}, reason=HERE)
    elif hidden == "token":
        emit("FC-E21", "unknown", "token", {"branch": branch}, reason="the security settings not answered")
        emit("FC-E21", "info", "admin", {"line": ADMIN_TOKEN_FIX})
    else:
        why = ("this token does not read the repository's security settings; one with repository administration does"
               if meta.get("security_and_analysis") is None else
               "GitHub reports no Code Security status for this repository")
        emit("FC-E21", "unknown", "unread", {"branch": branch, "why": why}, reason="no Code Security status read")
    if tools:
        check_codeql_policy(repo, branch, tools, policy)
    elif by_name:
        # A check name only asks the analysis to finish: the alerts it finds
        # block nothing. Said as not verified, not as the rule's policy.
        emit("FC-E22", "unknown", "name", {"branch": branch, "repo": repo}, reason="a check name sets no threshold")
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
            emit("FC-E23", "review", "review", reader=ADMIN_READER)
        # A CodeQL rule or check name means Code Security is there, so on
        # that repository a failed read is one a re-run can clear (#1002).
        elif not isinstance(langs, list) and hidden == "plan" and not (tools or by_name):
            emit("FC-E23", "unknown", "plan", reason=HERE)
        elif not isinstance(langs, list):
            emit("FC-E23", "unknown", "unread", reason="default setup not read")
        else:
            # CodeQL's name for the language; `javascript` and `typescript`
            # are the older spellings GitHub still accepts (#681 review).
            if not_applying is None:
                lang, accepted, code = "python", {"python"}, "the Python under src/"
            else:
                lang, code = "javascript-typescript", "the JavaScript or TypeScript code"
                accepted = {lang, "javascript", "typescript"}
            if any(a in langs for a in accepted):
                emit("FC-E23", "pass", "good", {"langs": langs})
            else:
                emit("FC-E23", "warn", "bad", {"langs": langs, "code": code})
                emit("FC-E23", "info", "hint", {"repo": repo, "lang": lang})

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
                emit("FC-E24", "review", "review", {"rid": rid}, reader=ADMIN_READER)
                continue
            emit("FC-E24", "unknown", "unread", {"rid": rid}, reason="bypass actors not read")
        else:
            verdict("FC-E24", actors == [], {"rid": rid, "actors": actors})
    if "pull_request" in by_type:
        check_approvals(repo, branch, pr, reserved, network, actions_token, root)


def codeowner_logins(root: Path | None) -> tuple[set[str], set[str]] | None:
    """The user logins and the teams (org/team) the CODEOWNERS file GitHub
    reads names (.github/, the root, docs/, the first found), lowercased;
    emails left out. None when there is no such file. A team's members are
    not read here (#1235 review)."""
    for rel in (".github/CODEOWNERS", "CODEOWNERS", "docs/CODEOWNERS"):
        f = (root or Path(".")) / rel
        if f.is_file():
            names, teams = set(), set()
            for line in read(f).splitlines():
                for tok in line.split("#", 1)[0].split()[1:]:
                    if tok.startswith("@"):
                        (teams if "/" in tok else names).add(tok[1:].lower())
            return names, teams
    return None


def check_approvals(repo: str, branch: str, pr: dict, reserved: str | None, network: bool,
                    actions_token: bool, root: Path | None = None) -> None:
    """The approvals the pull-request rule requires against the people
    (#1150), a WARN either way it does not fit. Two or more people can merge
    and no approval is required, so neither has to look at the other's
    change: who can merge is the admins where the merge ruleset stands (an
    agent's own account is a collaborator with write, never the admin), and
    everyone with write where it does not. Or an approval is required and
    one person at most can give one that counts, so their own pull requests
    cannot merge: GitHub counts an approval from anyone with write, and with
    code owners' review on, only from a code owner, so there it is those
    with write whom this checkout's CODEOWNERS names. Bots are not people."""
    required = pr.get("required_approving_review_count")
    if not isinstance(required, int):
        return
    got = api(f"repos/{repo}/collaborators?per_page=100", network, paginate=True)
    if not isinstance(got, list) and actions_token:
        emit("FC-E35", "review", "review", reader=ADMIN_READER)
        return
    if not isinstance(got, list):
        emit("FC-E35", "info", "unread", {"branch": branch})
        return
    role = "admin" if reserved in ("stands", "never") else "push"
    who = sorted(c.get("login", "?") for c in got if isinstance(c, dict) and c.get("type") != "Bot"
                 and (c.get("permissions") or {}).get(role) is True)
    approvers = sorted(c.get("login", "?") for c in got if isinstance(c, dict) and c.get("type") != "Bot"
                       and (c.get("permissions") or {}).get("push") is True)
    how = ""
    teams: set[str] = set()
    if pr.get("require_code_owner_review") is True:
        read_owners = codeowner_logins(root)
        owners, teams = read_owners if read_owners is not None else (None, set())
        approvers = [a for a in approvers if a.lower() in (owners or set())]
        how = (" (code owners' review is on, and no CODEOWNERS file is here)" if owners is None else
               " (code owners' review is on, and CODEOWNERS names no one else with write)")
    values = {"branch": branch, "who": ", ".join(who) or "nobody", "how": how,
              "approvers": ", ".join(approvers) or "nobody",
              "people": f"{len(who)} {'person' if len(who) == 1 else 'people'}",
              "required": f"{required} approval{'' if required == 1 else 's'}", "repo": repo}
    # An author cannot approve their own pull request, so one of theirs needs
    # `required` approvals from the others: fewer than required + 1 who can
    # approve leaves it unable to merge (#1235 review). A team in CODEOWNERS
    # may hold more approvers than are read: then the count is not made.
    if required >= 1 and len(approvers) <= required and teams:
        emit("FC-E35", "info", "teams", dict(values, teams=", ".join(f"@{t}" for t in sorted(teams))))
    elif required >= 1 and len(approvers) <= required:
        emit("FC-E35", "warn", "alone", values)
        emit("FC-E35", "info", "hint", dict(values, preset="one-person" if len(approvers) <= 1 else "two-people"))
    elif not who:
        emit("FC-E35", "info", "nobody", dict(values, role="admin" if role == "admin" else "write"))
    elif len(who) >= 2 and required == 0:
        emit("FC-E35", "warn", "none", values)
        emit("FC-E35", "info", "hint", dict(values, preset="two-people"))
    else:
        emit("FC-E35", "pass", "good", values)


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
            emit("FC-E25", "info", "nocompare", {"branch": branch})
        return set(), None
    if not carriers:
        if any(r.get("type") == "update" for r in rules):
            emit("FC-E25", "unknown", "outside", {"branch": branch}, reason="a ruleset outside this repository")
            return set(), None
        # Not in effect is not absent: a merge ruleset switched to evaluate or
        # disabled, or scoped off the default branch, is missing from the
        # branch's rules but still there, and then the merge is open while
        # it looks reserved. This repository's other rulesets are read for
        # one that carries `update`.
        listed = api(f"repos/{repo}/rulesets?per_page=100", network, paginate=True)
        if listed is ERROR or (listed is not ABSENT and not isinstance(listed, list)):
            emit("FC-E25", "unknown", "unlisted", {"branch": branch}, reason="the rulesets not listed")
            return set(), None
        in_effect = {r.get("ruleset_id") for r in rules}
        idle = []
        for item in listed if isinstance(listed, list) else []:
            rid = item.get("id") if isinstance(item, dict) else None
            if not rid or rid in in_effect or item.get("source_type", "Repository") != "Repository":
                continue
            rs = api(f"repos/{repo}/rulesets/{rid}", network)
            # A tag ruleset (ruleset-tags.json, #772) carries `update` too and
            # never governs a branch.
            if isinstance(rs, dict) and rs.get("target", "branch") == "branch" \
                    and any(r.get("type") == "update" for r in rs.get("rules", [])):
                idle.append(f"ruleset {rid} ({rs.get('enforcement')}, {rs.get('target')}, {rs.get('conditions')})")
        if idle:
            emit("FC-E25", "fail", "idle", {"branch": branch, "idle": "; ".join(idle),
                                            "enforcement": merge["enforcement"], "conditions": merge["conditions"]})
            return set(), None
        # A WARN, not a FAIL: every repository made before #568 lacks it, and
        # `ci / floor-check` runs in each of them; while the agent works under
        # the person's own account it changes nothing.
        emit("FC-E25", "warn", "missing", {"branch": branch})
        emit("FC-E25", "info", "create", {"repo": repo})
        return set(), "missing"
    want_types = sorted(r["type"] for r in merge["rules"])
    want_actors = sorted(bypass_key(a) for a in merge["bypass_actors"])
    judged = set()
    passed = []
    cannot_bypass: list[bool] = []
    for rid in sorted(carriers):
        types = sorted({r.get("type") for r in rules if r.get("ruleset_id") == rid})
        if types != want_types:
            emit("FC-E25", "fail", "types", {"branch": branch, "rid": rid, "types": types, "want": want_types})
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
            emit("FC-E25", "fail", "scope", {"rid": rid, "scope": scope, "want": want_scope})
            continue
        actors = rs.get("bypass_actors") if isinstance(rs, dict) else None
        # GitHub's own answer for this login, readable without the actors.
        cannot_bypass.append(isinstance(rs, dict) and rs.get("current_user_can_bypass") == "never")
        if actors is None and actions_token:
            emit("FC-E25", "review", "review", {"rid": rid}, reader=ADMIN_READER)
        elif actors is None:
            emit("FC-E25", "unknown", "unread", {"rid": rid}, reason="bypass actors not read")
        elif sorted(bypass_key(a) for a in actors) != want_actors:
            emit("FC-E25", "fail", "actors", {"rid": rid, "actors": actors, "want": merge["bypass_actors"]})
        elif scope is None:
            emit("FC-E25", "unknown", "noscope", {"rid": rid}, reason="the scope not read")
        else:
            emit("FC-E25", "pass", "good", {"rid": rid})
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
        emit("FC-E26", "review", "review", reader=ADMIN_READER)
        return
    perms = meta.get("permissions")
    admin = perms.get("admin") if isinstance(perms, dict) else None
    push = perms.get("push") if isinstance(perms, dict) else None
    if not isinstance(admin, bool):
        emit("FC-E26", "unknown", "role", reason="the role not read")
    elif not admin and push is False:
        emit("FC-E26", "pass", "readonly")
    elif not admin and push is not True:
        emit("FC-E26", "unknown", "write", reason="write access not read")
    elif admin:
        emit("FC-E26", "info", "admin")
    elif reserved == "stands":
        emit("FC-E26", "pass", "stands", {"branch": branch})
    elif reserved == "never":
        # Only this login's answer: whether the admin is still exempt, so
        # the person's merge goes through, is in the actors it cannot read.
        emit("FC-E26", "pass", "never", {"branch": branch})
    elif reserved == "missing":
        emit("FC-E26", "info", "missing")
    elif reserved == "no rules":
        emit("FC-E26", "info", "norules", {"branch": branch})
    elif reserved == "unread":
        emit("FC-E26", "unknown", "unread", {"branch": branch}, reason="the rules not read")
    else:
        emit("FC-E26", "unknown", "shape", reason="the merge ruleset not in its shape")


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
        emit("FC-G01", "info", "on", {"path": on})
    else:
        emit("FC-G01", "unknown", "unset", {"conf": conf}, reason=HERE)
    for key in ("off", "gh", "uvx", "other"):
        emit("FC-G01", "info", key)


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
        emit("FC-G02", "unknown", "unread", {"path": plugins_dir / "installed_plugins.json", "err": type(e).__name__},
             reason="the installed plugins not read")
        return
    if not isinstance(installed, dict) or installed.get("version") != 2 or not isinstance(installed.get("plugins"), dict):
        emit("FC-G02", "unknown", "shape", {"path": plugins_dir / "installed_plugins.json"},
             reason="the installed plugins not in a shape read here")
        return
    try:
        loc = Path(json.loads(read(plugins_dir / "known_marketplaces.json"))["plinth"]["installLocation"])
        market = json.loads(read(loc / ".claude-plugin" / "marketplace.json"))
        if market.get("name") != "plinth":
            raise ValueError("not the plinth marketplace")
        entries = {e["name"]: e for e in market["plugins"]}
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as e:
        emit("FC-G02", "unknown", "market", {"path": plugins_dir / "known_marketplaces.json", "err": type(e).__name__},
             reason="the marketplace's pins not read")
        return

    # The Retired entries table of the marketplace copy's
    # docs/reference/dependency-entries.md (#1229), for the release a removed
    # entry left in and what replaced it. Best effort: unread, the WARN names
    # neither.
    retired: dict[str, tuple[str, str]] = {}
    try:
        for line in read(loc / "docs" / "reference" / "dependency-entries.md").splitlines():
            m = re.match(r"^\| `([^`]+)` \| entry removed \| (v[0-9.]+) \| ([^|]*?) \|", line)
            if m:
                rep = re.fullmatch(r"`([^`]+)`", m.group(3).strip())
                retired[m.group(1)] = (m.group(2), rep.group(1) if rep else "")
    except OSError:
        pass

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
        if name not in entries and isinstance(installs, list) and installs:
            # An entry the marketplace no longer lists (#1229): Claude Code
            # keeps the install and reports it "not found in marketplace";
            # with forceRemoveDeletedPlugins it uninstalls it at the next
            # session start, and this names the command for one not yet.
            left, replaced = retired.get(name, ("", ""))
            for rec in installs:
                rec = rec if isinstance(rec, dict) else {}
                where = rec.get("scope") or "unknown scope"
                if rec.get("projectPath"):
                    where += f" in {rec['projectPath']}"
                scope = rec.get("scope")
                fix = f"claude plugin uninstall {pid}" + (f" --scope {scope}" if scope in ("user", "project", "local") else "")
                if scope in ("project", "local"):
                    path = rec.get("projectPath")
                    fix = f"cd {shlex.quote(path)} && {fix}" if isinstance(path, str) and path else \
                        f"{fix}, run from the project folder it was installed for"
                key = "replaced" if left and replaced else "retired" if left else "gone"
                emit("FC-G12", "warn", key, {"pid": pid, "where": where, "left": left, "replaced": replaced, "fix": fix})
            continue
        want, how = pinned(name)
        if not isinstance(installs, list) or not installs:
            emit("FC-G02", "unknown", "norecord", {"pid": pid}, reason="no install record")
            continue
        for rec in installs:
            rec = rec if isinstance(rec, dict) else {}
            where = rec.get("scope") or "unknown scope"
            if rec.get("projectPath"):
                where += f" in {rec['projectPath']}"
            have = rec.get("gitCommitSha") if how == "commit" else rec.get("version")
            if want is None:
                emit("FC-G02", "unknown", "nopin", {"pid": pid, "where": where, "how": how},
                     reason="the entry pins nothing comparable")
            elif not isinstance(have, str) or (how == "commit" and not SHA.fullmatch(have)):
                emit("FC-G02", "unknown", "noinstall", {"pid": pid, "where": where, "how": how},
                     reason="the install records nothing comparable")
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
                emit("FC-G02", "warn", "bad", {"pid": pid, "where": where, "how": how, "have": shown(have),
                                               "want": shown(want), "fix": fix})
            else:
                current.append(f"{pid} ({where})")
    if current:
        emit("FC-G02", "info", "current", {"names": ", ".join(current)})
    if other:
        # Outside what this item compares, not a read that failed (#1002).
        emit("FC-G02", "info", "other", {"names": ", ".join(other)})


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


def none_found(cid: str, what: str) -> None:
    """Finding nothing is not a pass: these rules read gh's and git's formats
    as far as they go, and a credential they do not recognise is not reported
    (#344's review found one after another). A WARN is what they found. An
    INFO of check `cid`, whose `none` message is NONE_FOUND."""
    emit(cid, "info", "none", {"what": what})


def check_workflow_scope(accounts: object, env_tokens: list[str]) -> None:
    """Whether the active github.com login holds `workflow` (#986), read from
    the `scopes` gh 2.103.3 lists beside it in `gh auth status --json hosts`
    ("gist, read:org, repo, workflow"), never from the token. With it the agent
    can push a change to .github/workflows/, the checks included: a WARN, not a
    FAIL, since the setup needs it until the first pull request is merged. A
    fine-grained token lists no scopes, so none listed is not verified."""
    active = [a for a in accounts if isinstance(a, dict) and a.get("active")] if isinstance(accounts, list) else []
    if not active:
        emit("FC-G03", "unknown", "noactive", reason="no active gh login read")
        return
    login, scopes = str(active[0].get("login", "?")), active[0].get("scopes")
    aside = (f" ({' and '.join(env_tokens)} is set: the token in use may not have these scopes)" if env_tokens else "")
    if scopes is None:   # not listed at all, as for a fine-grained token
        scopes = []
    elif isinstance(scopes, str):
        scopes = scopes.split(",")
    if not isinstance(scopes, list) or not all(isinstance(s, str) for s in scopes):
        emit("FC-G03", "unknown", "unread", {"login": login, "aside": aside}, reason="the scopes not read")
        return
    listed = [s.strip() for s in scopes if s.strip()]
    if not listed:
        emit("FC-G03", "unknown", "none", {"login": login, "aside": aside}, reason="no scopes listed")
        return
    if "workflow" in listed:
        emit("FC-G03", "warn", "bad", {"login": login, "aside": aside})
        emit("FC-G03", "info", "hint")
    else:
        emit("FC-G03", "info", "good", {"login": login, "aside": aside})


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
        emit("FC-G04", "warn", "bad", {"var": var, "cli": cli})
        emit("FC-G04", "info", "hint", {"var": var})

    # Each points gh or git away from, or adds to, the configuration read by
    # default; that one is not read here, and the agent can unset the variable.
    for var in (GLAB_CONFIG_MASKS if gitlab else CONFIG_MASKS):
        if var in os.environ:   # set but empty counts: `GIT_CONFIG_GLOBAL=` reads no global file
            emit("FC-G05", "unknown", "set", {"var": var}, reason="the default configuration not read")

    if gitlab:
        emit("FC-G06", "unknown", "glab", reason="glab's configuration not read")
        emit("FC-G03", "unknown", "glab", reason="glab's token scopes not read")
    else:
        env = {k: v for k, v in os.environ.items() if k not in ("GH_TOKEN", "GITHUB_TOKEN")}
        try:
            r = subprocess.run(["gh", "auth", "status", "--hostname", "github.com", "--json", "hosts"],
                               capture_output=True, text=True, timeout=30, check=False, env=env)
            accounts = json.loads(r.stdout)["hosts"].get("github.com", []) if r.returncode == 0 else None
        except (OSError, subprocess.TimeoutExpired, ValueError, KeyError, TypeError, AttributeError):
            accounts = None
        if not isinstance(accounts, list):
            emit("FC-G06", "unknown", "unread", reason="gh's answer not read")
        else:
            logins = [str(acct.get("login", "?")) if isinstance(acct, dict) else "?" for acct in accounts]
            active = [str(acct.get("login", "?")) for acct in accounts if isinstance(acct, dict) and acct.get("active")]
            if len(logins) > 1:
                emit("FC-G06", "warn", "many", {"n": len(logins), "active": ", ".join(active) or "none"})
                # Which account holds the agent's token is not known here, active or
                # not (third-party review round 9 on #344): the person chooses.
                emit("FC-G06", "info", "keep")
                for login in logins:
                    emit("FC-G06", "info", "logout", {"login": shlex.quote(login)})
            elif logins and env_tokens:
                # The agent can unset the variable itself, and the stored login answers.
                emit("FC-G06", "warn", "beside", {"login": logins[0], "vars": " and ".join(env_tokens)})
                emit("FC-G06", "info", "keepone", {"login": shlex.quote(logins[0])})
            else:
                none_found("FC-G06", f"gh stores {len(logins) or 'no'} account{'' if len(logins) == 1 else 's'} for github.com"
                           + (f": {logins[0]}" if logins else ""))
        check_workflow_scope(accounts, env_tokens)

    g: subprocess.CompletedProcess[str] | None
    try:
        g = subprocess.run(["git", "-C", str(root), "config", "--null", "--get-regexp",
                            r"^(credential\..*helper|http\..*extraheader)$"],
                           capture_output=True, text=True, timeout=30, check=False)
    except (OSError, subprocess.TimeoutExpired):
        g = None
    if g is None or g.returncode not in (0, 1):   # 1: no such key
        emit("FC-G07", "unknown", "unread", reason="git config not read")
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
                emit("FC-G07", "unknown", "url", {"section": section, "shown": shown, "name": name},
                     reason="a URL not parsed")
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
            emit("FC-G07", "warn", "bad", {"n": len(others), "s": "s" if len(others) > 1 else "", "name": name,
                                           "cli": cli, "others": ", ".join(others)})
            emit("FC-G07", "info", "hint", {"cli": cli, "name": name})
        else:
            none_found("FC-G07", f"git asks {'only ' + cli if helpers else 'no credential helper'} for {name}")
        if headers:
            emit("FC-G08", "warn", "bad", {"name": name})

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
        emit("FC-G09", "unknown", "unread", {"netrc": netrc}, reason="~/.netrc not read")
    elif any(m.group(3) is not None for m in tokens):
        emit("FC-G09", "unknown", "quote", {"netrc": netrc}, reason="a quote not closed")
    # Host names and keywords in any case: curl 8.5.0 matched `GITHUB.COM` (third-party review on #344).
    elif github is None:
        emit("FC-G09", "unknown", "shape", {"netrc": netrc}, reason="a token sequence not placed")
    elif github:
        emit("FC-G09", "warn", "bad", {"netrc": netrc, "name": name})
    else:
        none_found("FC-G09", f"no {name} login in {netrc}")

    emit("FC-G10", "unknown", "gitlab" if gitlab else "github", reason=HERE)
    emit("FC-G10", "info", "askpass")


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
        emit("FC-G11", "warn", "bad", {"where": where})
        emit("FC-G11", "info", "hint", {"fix": fix, "db": DB_FIX})

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
            emit("FC-G11", "unknown", "unread", {"rel": rel}, reason="a .env file not read")
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
            emit("FC-G11", "unknown", "json", {"shown": shown}, reason="a settings file not read")
            continue
        if not isinstance(env, dict):
            emit("FC-G11", "unknown", "env", {"shown": shown}, reason="a settings env not an object")
            continue
        for var in sorted(env):
            if production_url_in(env[var]):
                warn(f"{named(var, 'an entry')} in the env of {shown}", "delete the entry")

    if not found:
        emit("FC-G11", "info", "none")


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
    ap.add_argument("--format", choices=("text", "json"), default="text",
                    help="json: print the run once, as one JSON document in the shape of "
                         "scripts/floor-check.schema.json, instead of the report's lines")
    ap.add_argument("--sandbox", action="store_true", help="also report what this machine's Claude Code settings say about the sandbox")
    ap.add_argument("--plugins", action="store_true",
                    help="also compare each plugin installed from the plinth marketplace with the commit its entry pins")
    ap.add_argument("--credentials", action="store_true",
                    help="also report what else on this machine can push to github.com (gitlab.com with --host gitlab): "
                         "gh accounts, git helpers, ~/.netrc; and a production database URL in the environment, "
                         ".env* files or the env of .claude/settings*.json")
    ap.add_argument("--print-conditional-archetypes", action="store_true", help=argparse.SUPPRESS)
    ap.add_argument("--print-adoption", action="store_true",
                    help="print .plinth-adoption.yml as JSON, in the shape of scripts/plinth-adoption.schema.json, and "
                         "exit 0 (1, with the reason, when it is not read) (#1112)")
    ap.add_argument("--print-diff-size", action="store_true",
                    help="print what ci / diff-size counts against here, from the ci job's with: or plinth's defaults, "
                         "as max=, exclude= and root= lines, and exit 0 (1, with the reason, when not read) (#795)")
    ap.add_argument("--print-plinth-pins", action="store_true",
                    help="print each coolbress/plinth uses: of the workflow files as `<file> <ref>`, or `<file> unread "
                         "line <n>` for a uses: this checker cannot read, and exit 0 (#793)")
    ap.add_argument("--print-plinth-comments", action="store_true",
                    help="print each coolbress/plinth uses: of the workflow files that carries a trailing comment as "
                         "`<file> <ref>`, and exit 0 (#1045)")
    ap.add_argument("--print-template-changes", action="store_true",
                    help="print the template CHANGELOG's section headings from the recorded tag to the one this plinth "
                         "targets, with each section's files-and-questions block; exit 0, or the compare link and "
                         "exit 1 when not read (#1184)")
    ap.add_argument("--print-question-help", nargs="+", metavar="NAME",
                    help="print each named question of the copier.yml this plinth targets with its help, indented; "
                         "exit 1, with the reason, when copier.yml is not read (#1185)")
    ap.add_argument("--print-plugin-skew", action="store_true",
                    help="compare the template tag this plinth targets with the latest release's and the CI pin's: exit 3 "
                         "with what to type when it is older, else exit 0, a failed read said on stderr (#843)")
    ap.add_argument("--print-behind", action="store_true",
                    help="print whether the template tag is behind the one this plinth targets and whether the plinth "
                         "pin is behind plinth's latest release, one line each, `not read` when not read; exit 0 (#904)")
    ap.add_argument("--print-update-command", action="store_true",
                    help="print the template drift item's `copier update` line alone and exit (1, with the reason, when there is none)")
    ap.add_argument("--move-archetype", metavar="ARCHETYPE",
                    help="with --print-update-command: the line that re-renders this repository under ARCHETYPE at the "
                         "tag it records, with check-drop:/check-add:/check-add-floor:/diff-size-move: lines on stderr (#1004, #1017, #1044)")
    ap.add_argument("--print-refused-actions", action="store_true",
                    help="print each uses: of the workflow files that --repo's Actions allowlist refuses as `refused:` "
                         "lines, then the `allow:` call, or `allowed: <n>`; exit 1, with the reason, when not read (#1018)")
    ap.add_argument("--print-ruleset", action="store_true",
                    help="print --ruleset as the door applies it for --archetype (the image check added for a service archetype), and exit")
    ap.add_argument("--without-code-scanning", action="store_true",
                    help="with --print-ruleset: leave the code_scanning rule out, as the door does for a private "
                         "repository without GitHub Code Security")
    a = ap.parse_args()
    if a.format == "json" and any(v for k, v in vars(a).items() if k.startswith("print_")):
        ap.error("--format json reports a run; a --print-* flag prints something else")
    global out_format
    out_format = a.format
    # Known before anything is read, so a run that raises still says what it read.
    run_info.update(root=str(Path(a.root).resolve()), project=a.project, host=a.host or "github", repo=a.repo)
    if a.verdicts:
        global next_action
        next_action = NEXT_ACTION

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
    if a.move_archetype is not None and not a.print_update_command:
        ap.error("--move-archetype needs --print-update-command")
    if a.print_adoption:
        return print_adoption(root)
    if a.print_plinth_pins:
        return print_plinth_pins(root)
    if a.print_plinth_comments:
        return print_plinth_comments(root)
    if a.print_refused_actions:
        return print_refused_actions(root, a.repo, not a.no_network)
    if a.print_diff_size:
        return print_diff_size(root)
    if a.print_template_changes:
        return print_template_changes(root, not a.no_network)
    if a.print_question_help:
        return print_question_help(a.print_question_help, not a.no_network)
    if a.print_plugin_skew:
        return print_plugin_skew(root, not a.no_network, a.host)
    if a.print_behind:
        return print_behind(root, not a.no_network, a.host)
    if a.print_update_command and a.move_archetype is not None:
        return print_move_command(root, a.move_archetype, not a.no_network, a.host,
                                  a.repo.split("/")[0] if a.repo else None)
    if a.print_update_command:
        return print_update_command(root, not a.no_network, a.host, a.repo)
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
        emit("FC-F07", "unknown", "other", {"host": host}, reason="an unknown host")
        host = "github"
    run_info.update(root=str(root), project=str(project.relative_to(root)) if project != root else ".",
                    host=host, repo=a.repo)
    if out_format == "text":
        print(f"floor check: root={root} project={project.relative_to(root) if project != root else '.'}"
              + (" host=gitlab" if host == "gitlab" else ""))
    check_adoption(root)
    javascript = host == "github" and javascript_project(project, root)
    if javascript:
        emit("FC-C04", "info", "info")
    check_files(root, owner, network, host)
    if not a.actions_token:
        check_plugin_skew(root, network, host)
    check_answers(root, owner, network, host)
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
            emit("FC-E01", "unknown", "norepo" if not a.repo else "offline",
                 reason="no --repo" if not a.repo else "--no-network")
    else:
        if javascript:
            emit("FC-D02", "not_applicable", "js", {"workflow": CALLER_WORKFLOW})
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
        emit("FC-E06", "info", "expect", {"expected": expected, "methods": sorted(merge_methods)})
        merge = json.loads(read(Path(a.merge_ruleset))) if a.merge_ruleset else None
        check_wall(a.repo, expected, merge_methods, policy, network, sources, a.actions_token, merge, not_applying, root,
                   None if a.archetype else archetype, (project / ".copier-answers.yml").relative_to(root).as_posix())
        check_actions_allowlist(root, a.repo, network, a.actions_token)
        check_actions_token(a.repo, network, a.actions_token)
        check_security_reads(root, a.repo, network, a.actions_token)
        check_tag_ruleset(a.repo, archetype, network, a.actions_token, project)
        check_description(a.repo, network)
        check_labels(a.repo, network)
    else:
        emit("FC-E06", "unknown", "norepo", reason="no --repo")

    if a.sandbox:
        check_sandbox()
    if a.plugins:
        check_plugins()
    if a.credentials:
        check_credentials(root, host)
        check_database_urls(root)

    if out_format == "json":
        # The verdicts file first: when it cannot be written, the one
        # document printed is the crashed one, not a whole run and then it.
        if a.verdicts:
            Path(a.verdicts).write_text(render_verdicts(results), encoding="utf-8")
        print_json(results)
    else:
        print(render_summary(results))
        if a.verdicts:
            Path(a.verdicts).write_text(render_verdicts(results), encoding="utf-8")
    return 1 if any(r["state"] == "fail" for r in results) else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        if out_format == "json":
            # The skill reads a document either way: one that says where the run stopped.
            print_json(results, {"after": results[-1]["id"] if results else None, "error": type(exc).__name__})
        if TRACE:
            with open(TRACE, "a", encoding="utf-8") as t:
                t.write(f"crashed {results[-1]['id'] if results else '-'}\n")
        raise
