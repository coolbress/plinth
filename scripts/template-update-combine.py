#!/usr/bin/env python3
"""The combination template-update.sh proposes for one file copier left in
conflict (#1186): the template's side of each conflict block, with the lines
this repository added there kept. Standard library only.

  template-update-combine.py combine <file> <base> <old-render|-> <out>
      <file> holds copier's markers (`<<<<<<< before updating`, `=======`,
      `>>>>>>> after updating`); <base> is the file at the base, <old-render>
      copier's render of the recorded answers at the recorded tag (`-` when the
      template rendered no such file, so every line of it is this
      repository's). Writes the whole file, each block resolved to the
      combination, to <out>, and prints one line per line this repository
      added that the template's side drops:
          risk<TAB><placement><TAB><count><TAB><line>
      <count> is how many times <line> is in the template's side of the
      whole file, for `where`; <line> is the rest of the line, tabs and all.
      <placement> is `in place` (after or before a line both sides keep),
      `replaces <the template's line>` (the same key under the same parent
      keys or table, set by this repository),
      `no old place` (its neighbours are gone: at the end of the block), or
      `no old place; propose: <where>` for a Markdown line, `under ## This
      project` when the file ends in that section, or `above <the template's
      line>` (a comment added above a key whose value it left alone). A line
      in a `[[table]]` entry is `no old place` when the two sides hold a
      different number of those entries. On Python 3.11 or later (tomllib), a
      TOML combination that does not parse adds a line `invalid<TAB><why>`. Exit 0; exit 2 when the
      markers cannot be read (nested, unclosed, or diff3's `|||||||`).

  template-update-combine.py where <file> <line> <count>
      Where <line> is now: `<section><TAB><line number>` of its last
      occurrence, the section being the Markdown heading above it, the TOML
      table, or the YAML keys it sits under (`jobs.ci.with`), empty when
      there is none. Prints nothing and exits 1 when the file holds it no
      more than <count> times, the template's side's own.
"""

from __future__ import annotations

import difflib
import importlib
import re
import sys
from pathlib import Path

OURS, MID, THEIRS = "<<<<<<< ", "=======", ">>>>>>> "
THIS_PROJECT = "## This project"


def lines_of(path: str) -> list[str]:
    return Path(path).read_text(encoding="utf-8").splitlines()


def kind_of(path: str) -> str:
    p = path.lower()
    if p.endswith((".md", ".markdown")):
        return "md"
    if p.endswith((".yml", ".yaml")):
        return "yaml"
    if p.endswith(".toml"):
        return "toml"
    return "other"


def blocks(text: list[str]) -> list[tuple[int, int, int]] | None:
    """(start, middle, end) line indexes of each block, or None when unreadable."""
    out, at = [], None
    mid = -1
    for i, line in enumerate(text):
        if line.startswith(OURS):
            if at is not None:
                return None
            at, mid = i, -1
        elif line.startswith("|||||||"):
            return None
        elif line == MID and at is not None:
            if mid != -1:
                return None
            mid = i
        elif line.startswith(THEIRS):
            if at is None or mid == -1:
                return None
            out.append((at, mid, i))
            at = None
    return None if at is not None else out


def added_lines(base: list[str], old: list[str] | None, kind: str) -> set[tuple[tuple[str, ...], str]]:
    """The lines of <base> that copier's old render does not have there, each
    with its scope (`parents`): a line this repository changed in one table is
    not its line in another table that holds the same text (#1233)."""
    if old is None:
        return {(parents(base, j, kind), ln) for j, ln in enumerate(base)}
    out: set[tuple[tuple[str, ...], str]] = set()
    sm = difflib.SequenceMatcher(a=old, b=base, autojunk=False)
    for tag, _, _, j1, j2 in sm.get_opcodes():
        if tag in ("insert", "replace"):
            out.update((parents(base, j, kind), base[j]) for j in range(j1, j2))
    return out


def indent(line: str) -> int:
    return len(line) - len(line.lstrip())


def is_comment(line: str, kind: str) -> bool:
    return kind in ("yaml", "toml", "other") and line.lstrip().startswith("#")


def key_of(line: str, kind: str) -> str | None:
    s = line.strip()
    if kind == "yaml":
        m = re.match(r"^(?:- )?([^\s#'\"][^:#]*|'[^']*'|\"[^\"]*\"):(\s|$)", s)
    elif kind == "toml":
        m = re.match(r"^([A-Za-z0-9_.\-]+|\"[^\"]*\")\s*=", s)
    else:
        return None
    return m.group(1).strip() if m else None


def depth(line: str) -> int:
    d, quote = 0, ""
    for c in line:
        if quote:
            if c == quote:
                quote = ""
        elif c in "'\"":
            quote = c
        elif c == "#":
            break
        elif c in "[{(":
            d += 1
        elif c in "]})":
            d -= 1
    return d


def units(side: list[str], kind: str) -> list[tuple[int, int, int]]:
    """(first, item, last) spans: leading comments, the item line, and the
    lines that continue its value (deeper indentation in YAML, an open bracket
    in TOML). Markdown: one line each."""
    out, i, n = [], 0, len(side)
    while i < n:
        if kind == "md" or not side[i].strip():
            out.append((i, i, i))
            i += 1
            continue
        first = i
        while i < n and is_comment(side[i], kind):
            i += 1
        if i == n:
            out.append((first, n - 1, n - 1))
            break
        item, d, j = i, depth(side[i]), i + 1
        while j < n and side[j].strip() and (
            d > 0
            or (kind == "yaml" and indent(side[j]) > indent(side[item]) and not is_comment(side[j], kind)
                and key_of(side[j], kind) is None)
        ):
            d += depth(side[j])
            j += 1
        out.append((first, item, j - 1))
        i = j
    return out


def parents(lines: list[str], n: int, kind: str) -> tuple[str, ...]:
    """The scope line n sits in: the TOML table, or the YAML keys of the lines
    above it with less indentation, a sequence item by its whole first line
    (`- name: Test`), so two steps' `run:` keys are not the same key."""
    if kind == "toml":
        # The table above it; an array-of-tables entry by its ordinal, so two
        # `[[tool.sources]]` entries are not one scope (#1233).
        h = next((i for i in range(n - 1, -1, -1) if re.match(r"^\s*\[", lines[i])), None)
        if h is None:
            return ()
        header = lines[h].strip()
        if header.startswith("[["):
            return (f"{header}#{sum(1 for t in lines[:h + 1] if t.strip() == header)}",)
        return (header,)
    if kind != "yaml":
        return ()
    keys: list[str] = []
    limit = indent(lines[n])
    for t in reversed(lines[:n]):
        if not t.strip() or t.lstrip().startswith("#") or indent(t) >= limit:
            continue
        if t.lstrip().startswith("- "):
            keys.insert(0, t.strip())
            limit = indent(t)
        else:
            k = key_of(t, kind)
            if k is not None:
                keys.insert(0, k)
                limit = indent(t)
        if limit == 0:
            break
    return tuple(keys)


def combine(ours: list[str], theirs: list[str], added: set[tuple[tuple[str, ...], str]], kind: str,
            closing: bool, head: list[str], oscope: list[tuple[str, ...]],
            shifted: set[str]) -> tuple[list[str], list[tuple[str, str]]]:
    """<oscope>: the scope of each line of <ours>, read in the file as this
    repository has it; <head>: the combined file above the block, for the
    template's side and the result; <shifted>: the `[[table]]` headers whose
    entries the two sides count differently, so an entry's ordinal names
    another entry on the other side."""
    def rscope(lines: list[str], i: int) -> tuple[str, ...]:
        return parents(head + lines, len(head) + i, kind)

    # A line the template's side keeps is one it holds in the same scope (the
    # same TOML table or YAML parents): the same text under another table is
    # not this repository's line kept (review on #1224).
    kept = {(rscope(theirs, i), ln) for i, ln in enumerate(theirs)}
    risky = [ln.strip() != "" and (oscope[i], ln) in added and not ln.startswith((OURS, THEIRS))
             and (oscope[i], ln) not in kept for i, ln in enumerate(ours)]
    result = list(theirs)
    mine = [False] * len(result)  # which lines of result came from this repository's side
    report: list[tuple[str, str]] = []
    if not any(risky):
        return result, report

    def put(at: int, span: list[str]) -> None:
        result[at:at] = span
        mine[at:at] = [True] * len(span)

    def find(j: int) -> int | None:
        """Where ours[j] is in result: the same text in the same scope, and
        the same occurrence of it there (#1233), not the first anywhere."""
        nth = sum(1 for i in range(j) if ours[i] == ours[j] and oscope[i] == oscope[j])
        hits = [i for i, ln in enumerate(result) if ln == ours[j] and not mine[i] and rscope(result, i) == oscope[j]]
        return hits[nth] if nth < len(hits) else None

    tail: list[tuple[str, bool]] = []
    for first, item, last in units(ours, kind):
        if not any(risky[first:last + 1]):
            continue
        span = ours[first:last + 1]
        placement = ""
        if any(sc.split("#", 1)[0] in shifted for sc in oscope[item][:1]):
            # Its entry cannot be named on the template's side: the person
            # places it (review on #1233).
            tail += list(zip(span, risky[first:last + 1]))
            continue
        k = key_of(ours[item], kind) if not is_comment(ours[item], kind) else None
        # A YAML sequence item is named by its whole first line: every step's
        # `- name:` has the key `name` (review on #1233).
        same_item = kind == "yaml" and ours[item].lstrip().startswith("- ")
        match = None
        if k is not None:
            for tf, ti, tl in units(result, kind):
                if key_of(result[ti], kind) == k and indent(result[ti]) == indent(ours[item]) \
                        and rscope(result, ti) == oscope[item] and not any(mine[tf:tl + 1]) \
                        and (not same_item or result[ti] == ours[item]):
                    match = (tf, ti, tl)
                    break
        if match and any(risky[item:last + 1]) and not same_item:
            # The key that owns the at-risk lines, whether the project changed
            # its line or only its value's continuation: the project's value.
            tf, ti, tl = match
            placement = f"replaces {result[ti].strip()}"
            result[tf:tl + 1] = span
            mine[tf:tl + 1] = [True] * len(span)
        elif match and not any(risky[item:last + 1]):
            # Only comments above an unchanged key are this repository's: they
            # go above the template's line, which keeps its value (#1233).
            ti = match[1]
            placement = f"above {result[ti].strip()}"
            put(ti, ours[first:item])
            span = ours[first:item]
        else:
            neighbours = [j for j in range(first - 1, -1, -1) if not risky[j] and ours[j].strip()]
            before = next((i for i in map(find, neighbours) if i is not None), None)
            neighbours = [j for j in range(last + 1, len(ours)) if not risky[j] and ours[j].strip()]
            after = next((i for i in map(find, neighbours) if i is not None), None)
            if before is not None:
                at = before + 1
                # After what this repository's side already put there, so
                # consecutive additions keep their order (review on #1224).
                while at < len(result) and mine[at]:
                    at += 1
                put(at, span)
                placement = "in place"
            elif after is not None:
                put(after, span)
                placement = "in place"
        if placement:
            report += [(placement, ln) for ln, r in zip(span, risky[first:first + len(span)]) if r]
        else:
            tail += list(zip(span, risky[first:last + 1]))
    for ln, r in tail:
        if r:
            note = "no old place"
            if kind == "md" and closing:
                note += "; propose: drop it, the file's last section is that heading" if ln.strip() == THIS_PROJECT \
                    else f"; propose: under {THIS_PROJECT}, the file's last section"
            report.append((note, ln))
    result += [ln for ln, _ in tail]
    return result, report


def cmd_combine(path: str, base_path: str, old_path: str, out_path: str) -> int:
    text, kind = lines_of(path), kind_of(path)
    found = blocks(text)
    if found is None:
        print("the conflict markers could not be read", file=sys.stderr)
        return 2
    added = added_lines(lines_of(base_path), None if old_path == "-" else lines_of(old_path), kind)
    # The file without its blocks' "before" sides: does it close with the section?
    theirs_whole: list[str] = []
    at = 0
    for s, m, e in found:
        theirs_whole += text[at:s] + text[m + 1:e]
        at = e + 1
    theirs_whole += text[at:]
    headings = [ln for ln in theirs_whole if re.match(r"^#{1,6} ", ln)]
    closing = bool(headings) and headings[-1] == THIS_PROJECT
    # The file as this repository has it, each block its "before" side: where
    # each of its lines sits, read as `added` read the base.
    ours_whole: list[str] = []
    starts: list[int] = []
    at = 0
    for s, m, e in found:
        ours_whole += text[at:s]
        starts.append(len(ours_whole))
        ours_whole += text[s + 1:m]
        at = e + 1
    ours_whole += text[at:]
    shifted = set()
    if kind == "toml":
        for h in {ln.strip() for ln in ours_whole + theirs_whole if ln.strip().startswith("[[")}:
            if sum(ln.strip() == h for ln in ours_whole) != sum(ln.strip() == h for ln in theirs_whole):
                shifted.add(h)
    out: list[str] = []
    at = 0
    for (s, m, e), o in zip(found, starts):
        oscope = [parents(ours_whole, o + i, kind) for i in range(m - s - 1)]
        res, report = combine(text[s + 1:m], text[m + 1:e], added, kind, closing, out + text[at:s], oscope, shifted)
        out += text[at:s] + res
        at = e + 1
        for placement, line in report:
            # The placement may quote a template line: its tabs are shown as
            # `\\t`, so the fields stay where the caller reads them (review on #1224).
            shown = placement.replace("\t", "\\t")
            print(f"risk\t{shown}\t{theirs_whole.count(line)}\t{line}")
    out += text[at:]
    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    Path(out_path).write_text("\n".join(out) + "\n", encoding="utf-8")
    # A TOML combination that does not parse is said (#1233): the person takes
    # a side or edits it instead. YAML has no parser in the standard library.
    if kind == "toml":
        try:  # tomllib is Python 3.11's; without it the check is not made
            importlib.import_module("tomllib").loads("\n".join(out) + "\n")
        except ImportError:
            pass
        except ValueError as e:  # tomllib.TOMLDecodeError
            print(f"invalid\tTOML: {e}".replace("\n", " "))
    return 0


def cmd_where(path: str, line: str, theirs_count: str) -> int:
    text, kind = lines_of(path), kind_of(path)
    # Kept only when the file holds more of it than the template's side did.
    if text.count(line) <= int(theirs_count):
        return 1
    n = len(text) - 1 - text[::-1].index(line)
    section = ""
    if kind == "md":
        section = next((t for t in reversed(text[:n]) if re.match(r"^#{1,6} ", t)), "")
    elif kind == "toml":
        section = next((t.strip() for t in reversed(text[:n]) if re.match(r"^\s*\[", t)), "")
    elif kind == "yaml":
        keys: list[str] = []
        limit = indent(line)
        for t in reversed(text[:n]):
            if not t.strip() or t.lstrip().startswith("#") or indent(t) >= limit:
                continue
            k = key_of(t, kind)
            if k is not None:
                keys.insert(0, k)
                limit = indent(t)
            if limit == 0:
                break
        section = ".".join(keys)
    print(f"{section}\t{n + 1}")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) == 6 and argv[1] == "combine":
        return cmd_combine(*argv[2:6])
    if len(argv) == 5 and argv[1] == "where":
        return cmd_where(argv[2], argv[3], argv[4])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
