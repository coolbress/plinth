#!/usr/bin/env python3
"""Does a pull request's diff add a merge conflict marker? (#936)

A step of `ci / diff-size` in .github/workflows/python-ci.yml, which every
project calling it runs, and of plinth's own `ci / docs`. A pull request that
brought its base in and kept the markers of a conflict passed every check and
reached main (coolbress/plinth-template#237).

    conflict-markers.py <git diff revisions>

The arguments go to `git diff` as they are: `BASE...HEAD` for a pull
request's base and head, `HEAD^1 HEAD` for the merge commit GitHub checks out.
Only the lines the diff adds are read, in every tracked file the diff touches
(binary files have no lines), so a marker the base already has passes.

A line is a marker when it is one of git's:
  - `<<<<<<<`, `|||||||` (diff3's base) or `>>>>>>>`, alone or followed by a
    space and a label;
  - `=======` alone, when the same file's added lines also carry one of the
    three above. Alone it is also a Markdown heading's underline, and a
    conflict always writes an opening and a closing marker around it.
A trailing carriage return is ignored. A marker inside a fenced code block in
Markdown is still a marker: the block's fences say nothing about whether a
conflict left it there. A document that shows one indents it or puts it in a
code span.

Each marker is printed as `path:line: text` (the line number in the head) and
the first nine as `::error` annotations: GitHub drops a step's annotations
past ten. Exit 1 when there is one, 0 when there is none, 2 when git cannot
produce the diff or the script stops on anything else: a crash is never read
as a marker.

    tests/conflict-markers-cases.sh runs it on throwaway repositories.
"""
import codecs
import os
import re
import subprocess
import sys

# At the plinth commit ci / diff-size fetched this from (job.workflow_sha); main run by hand.
HOW = f"https://github.com/coolbress/plinth/blob/{(os.environ.get('PLINTH_SHA') or 'main')[:12]}/docs/reference/required-checks.md#required-by-rulesetjson"
EDGE = re.compile(r"^(<{7}|\|{7}|>{7})(?: .*)?$")
MIDDLE = re.compile(r"^={7}$")
HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")
ANNOTATED = 9


def unquote(path):
    """git writes a path with unusual bytes as a C string in double quotes."""
    if not path.startswith('"'):
        return path
    # On bytes: non-ASCII text stays raw UTF-8 inside the quotes, beside the
    # escapes (a quote, a backslash, a tab).
    raw, _ = codecs.escape_decode(path[1:-1].encode("utf-8"))
    return raw.decode("utf-8", "replace")


def added_lines(revisions):
    """Yield (path, head line number, text) for every line the diff adds."""
    # The prefixes are named so a `diff.noprefix` setting cannot drop them.
    cmd = ["git", "-c", "core.quotePath=false", "diff", "--no-color", "--no-ext-diff", "--no-textconv",
           "--src-prefix=a/", "--dst-prefix=b/", "--unified=0", *revisions, "--"]
    done = subprocess.run(cmd, capture_output=True, check=False)
    if done.returncode != 0:
        sys.stderr.write(done.stderr.decode("utf-8", "replace"))
        raise RuntimeError(" ".join(revisions))
    # A hunk header gives how many old and new lines follow; counting them
    # keeps an added line that starts `++ ` from reading as a file header.
    path, line, old, new = None, 0, 0, 0
    for raw in done.stdout.decode("utf-8", "replace").split("\n"):
        if old > 0 or new > 0:
            if raw.startswith("+"):
                new -= 1
                if path is not None:
                    yield path, line, raw[1:].rstrip("\r")
                line += 1
            elif raw.startswith("-"):
                old -= 1
            continue
        if raw.startswith("+++ "):
            # git ends a header whose path has a space with a tab.
            target = unquote(raw[4:].rstrip("\t"))
            path = target[2:] if target.startswith("b/") else None
        elif m := HUNK.match(raw):
            old = int(m.group(2)) if m.group(2) is not None else 1
            line, new = int(m.group(3)), int(m.group(4)) if m.group(4) is not None else 1


def escape(value, prop=False):
    value = value.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    return value.replace(":", "%3A").replace(",", "%2C") if prop else value


def main(argv):
    if not argv:
        print("usage: conflict-markers.py <git diff revisions>", file=sys.stderr)
        return 2
    edges, middles, files = [], [], set()
    try:
        for path, line, text in added_lines(argv):
            if EDGE.match(text):
                edges.append((path, line, text))
                files.add(path)
            elif MIDDLE.match(text):
                middles.append((path, line, text))
    except RuntimeError as err:
        print(f"::error::git could not produce the diff {err}. Update the branch from its base and push again: {HOW}")
        return 2
    except Exception as err:  # noqa: BLE001  exit 1 means a marker was found; a crash is not one
        print(f"::error::the conflict-marker check stopped ({type(err).__name__}: {err}); the diff was not read: {HOW}")
        return 2
    found = sorted(edges + [m for m in middles if m[0] in files])
    if not found:
        print(f"OK: no line the diff ({' '.join(argv)}) adds is a merge conflict marker.")
        return 0
    for path, line, text in found:
        print(f"{path}:{line}: {text}")
    for path, line, text in found[:ANNOTATED]:
        print(f"::error file={escape(path, True)},line={line}::{escape(path)}:{line} is a merge conflict marker "
              f"({escape(text[:40])}). Resolve the conflict, delete the marker lines and push: {HOW}")
    if len(found) > ANNOTATED:
        print(f"::error::{len(found) - ANNOTATED} more conflict marker lines are in the log: {HOW}")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
