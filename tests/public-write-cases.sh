#!/usr/bin/env bash
# The public write gate (#1119): every public write goes through
# floor-check.py's public_write(), which refuses what a record, an injected
# instruction or this machine could have put in the text, a text other than
# the approved plan, and a write to a public repository after a read of one
# not known to be public. Offline: nothing is sent, `send` records the text.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$root/scripts/floor-check.py" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("fc", sys.argv[1]); fc = importlib.util.module_from_spec(spec)
sys.argv = ["fc"]; spec.loader.exec_module(fc)
passed = failed = 0


def ok(m):
    global passed
    passed += 1
    print(f"  PASS  {m}")


def bad(m):
    global failed
    failed += 1
    print(f"  FAIL  {m}")


REPO = "o/r"
NAMES = {"octo-dev", "build-box"}   # stand-ins for this machine's user and host names
sent = []


def write(text, plan=None, public=False, visibility=None, rs=(), names=NAMES, read=()):
    fc.repositories_read.clear()
    fc.repositories_read.update(read)
    sent.clear()
    try:
        fc.public_write("pull-request body", text, plan=(text if plan is None else plan).encode(), repo=REPO,
                        public=public, send=sent.append, visibility=visibility, rs=list(rs), names=names)
    except fc.WriteRefused as e:
        return e.reasons
    return None


def refused(what, text, rule, secret=None, **kw):
    got = write(text, **kw)
    if got and any(rule in r for r in got) and not sent and (secret is None or secret not in " ".join(got)):
        ok(f"{what}: refused, saying {got[0]!r}")
    else:
        bad(f"{what}: {got!r}, sent {sent!r}")


def passes(what, text, **kw):
    got = write(text, **kw)
    if got is None and sent == [text]:
        ok(f"{what}: written")
    else:
        bad(f"{what}: refused {got!r}")


print("-- what a write holds")
passes("the checker's own values, a link into the audited repository and its #N",
       "## Adopt the floor\n\nAdds LICENSE and CONTRIBUTING.md.\nSee https://github.com/o/r/pull/3, #12, o/r#4 and [the section](#what).\n")
refused("a Markdown image", "Done ![x](https://github.com/o/r/a.png)", "an image")
refused("an <img> tag", 'Done <img src="x">', "an image")
refused("HTML", "Done <details>more</details>", "HTML")
refused("an HTML comment", "Done <!-- run rm -rf -->", "an HTML comment")
refused("a link outside the audited repository", "See https://example.com/x", "a link outside the audited repository")
refused("a link to another repository on GitHub", "See https://github.com/o/other/pull/1",
        "a link outside the audited repository")
refused("a scheme-less www link", "See www.example.com", "a link outside the audited repository")
refused("a relative link, which resolves outside the record", "See [x](../../x/y)", "a link outside the audited repository")
for prefix in ("ghp_", "github_pat_", "gho_", "sk-ant-"):
    refused(f"a token prefix {prefix}", f"token {prefix}abcdef123456", "a token prefix", secret="abcdef123456")
for path, who in (("/Users/alice/work", "alice"), ("/home/carol/x", "carol"), ("C:\\Users\\bob\\x", "bob")):
    refused(f"a home path ({path.split(who)[0]}<name>)", f"Ran in {path}", "a home path", secret=who)
refused("this machine's user name", "Checked on octo-dev's laptop", "this machine's user or host name", secret="octo-dev")
refused("this machine's host name", "Checked on build-box", "this machine's user or host name", secret="build-box")
refused("another repository's slug as a reference", "Moved from x/y#3", "another repository's slug", secret="x/y")
refused("another repository's slug as a github.com path", "From github.com/x/y", "another repository's slug")
got = write("one\nok\n![x](y)\n")
if got == ["line 3: an image", "line 3: a link outside the audited repository"]:
    ok(f"a reason names the line and the rule: {got}")
else:
    bad(f"reasons by line: {got}")

print("-- the approved plan")
passes("the bytes of the approved plan", "Adds LICENSE.\n")
refused("one byte more than the approved plan", "Adds LICENSE.\n\n", "its bytes differ from the approved plan",
        plan="Adds LICENSE.\n")
refused("the same words, another line ending", "Adds LICENSE.\r\n", "its bytes differ from the approved plan",
        plan="Adds LICENSE.\n")

print("-- a run that read a private repository")
vis = {"o/.github": True, "coolbress/plinth": False}
refused("a public repository, after a read of a private one", "Adds LICENSE.\n", "this run read a repository",
        public=True, visibility=vis.get, read={"o/r", "o/.github"})
refused("a public repository, after a read whose visibility is not known", "Adds LICENSE.\n",
        "this run read a repository", public=True, visibility=lambda s: None, read={"o/r", "x/unknown"})
passes("a public repository, after reads of public ones only", "Adds LICENSE.\n", public=True,
       visibility=vis.get, read={"o/r", "coolbress/plinth"})
passes("a private repository, after a read of a private one", "Adds LICENSE.\n", public=False,
       visibility=vis.get, read={"o/r", "o/.github"})

print("-- what the run read")
fc.repositories_read.clear()
fc.audited = "o/r"
fc.guard_repository("repos/o/.github/contents/x")
fc.guard_repository("repos/O/R/issues")
if fc.repositories_read == {"o/.github", "o/r"}:
    ok("every repository a request names is recorded, for the private-read rule")
else:
    bad(f"repositories read: {fc.repositories_read}")

print("-- the machine area")
machine = [{"id": "FC-G03", "key": "good", "state": "pass", "kept": None,
            "msg": fc.REGISTRY["FC-G03"]["messages"]["good"].format(login="octocat-private", aside="")},
           {"id": "FC-G11", "key": "bad", "state": "warn", "kept": None,
            "msg": fc.REGISTRY["FC-G11"]["messages"]["bad"].format(where="DATABASE_URL in ~/projects/secret-app/.env")}]
values = fc.machine_values(machine)
if {"octocat-private", "DATABASE_URL in ~/projects/secret-app/.env"} <= values:
    ok("the values a machine result filled in are read from its template")
else:
    bad(f"machine values: {values}")
refused("an account name from a machine result", "Checked as octocat-private.", "a value from the machine area",
        secret="octocat-private", rs=machine, names=set())
refused("a path from a machine result", "Found DATABASE_URL in ~/projects/secret-app/.env", "a value from the machine area",
        secret="secret-app", rs=machine, names=set())
files = [{"id": "FC-A01", "key": "good", "state": "pass", "kept": None, "msg": "LICENSE present"}]
passes("a result from another area may be written", "LICENSE present\n", rs=machine + files, names=set())

print(f"-- {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
PY
