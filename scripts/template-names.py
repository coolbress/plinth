#!/usr/bin/env python3
"""Whether the template refuses a repository name for an archetype (#1067).

    template-names.py <name> <archetype> < copier.yml

Reads the refusals from the pinned template's copier.yml itself, not from a
copy: the `project_name` validator (the package name derived from the name
must be an identifier, not a Python keyword, and must not start or end with
`_`) and the `archetype` validator (a package name that a shipped test of
that archetype already takes, such as `train` for data-ml). The doors run it
before they create anything, so /plinth:new-project can drop a suggested name
the render would refuse before the person sees it.

Exit 0: not refused. Exit 1: refused; stdout is the reason, in one line.
Exit 3: copier.yml no longer has the shape read here; stdout says what is
missing, and copier stays the judge at the render (it refuses before anything
is created).
"""

import re
import sys


def block(text: str, key: str) -> str:
    """The lines of a top-level question, up to the next top-level key."""
    m = re.search(rf"^{re.escape(key)}:\n(.*?)(?=^[a-z_]+:|\Z)", text, re.MULTILINE | re.DOTALL)
    return m.group(1) if m else ""


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: template-names.py <name> <archetype> < copier.yml", file=sys.stderr)
        return 2
    name, archetype = sys.argv[1], sys.argv[2]
    text = sys.stdin.read()
    pkg = re.sub(r"[-. ]", "_", name).lower()

    project = block(text, "project_name")
    ident = re.search(r"regex_search\('([^']+)'\)", project)
    words = re.search(r"elif pkg in \[(.*?)\]", project, re.DOTALL)
    shipped = re.search(r"set shipped = \{(.*?)\}", block(text, "archetype"), re.DOTALL)
    if ident is None or words is None or shipped is None:
        unread = [what for what, found in (("the identifier rule", ident), ("the keyword list", words),
                                           ("the shipped test names", shipped)) if found is None]
        print("copier.yml's validators changed shape (not found: " + ", ".join(unread) + ")")
        return 3

    if not re.search(ident.group(1), pkg):
        print(f"no Python package name can be made from '{name}': '{pkg}' is not an identifier")
        return 1
    if pkg in re.findall(r"'([^']+)'", words.group(1)):
        print(f"the package name '{pkg}' derived from '{name}' is a Python keyword")
        return 1
    if "pkg[:1] == '_'" in project and (pkg[:1] == "_" or pkg[-1:] == "_"):
        print(f"the package name '{pkg}' derived from '{name}' starts or ends with '_'")
        return 1
    taken = {}
    for arch, names in re.findall(r"'([a-z-]+)':\s*\[([^\]]*)\]", shipped.group(1)):
        taken[arch] = re.findall(r"'([^']+)'", names)
    if pkg in taken.get(archetype, []):
        print(f"the {archetype} archetype already ships a test named tests/test_{pkg}.py, which the name '{name}' would take")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
