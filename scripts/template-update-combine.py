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
          risk<TAB><placement><TAB><line>
      <placement> is `in place` (after or before a line both sides keep),
      `replaces <the template's line>` (the same key, set by this repository),
      `no old place` (its neighbours are gone: at the end of the block), or
      `no old place; propose: <where>` for a Markdown line, `under ## This
      project` when the file ends in that section. Exit 0; exit 2 when the
      markers cannot be read (nested, unclosed, or diff3's `|||||||`).

  template-update-combine.py where <file> <line>
      Where <line> is now: `<section><TAB><line number>`, the section being
      the Markdown heading above it, the TOML table, or the YAML keys it sits
      under (`jobs.ci.with`), empty when there is none. Prints nothing and
      exits 1 when the line is not in the file.
"""

from __future__ import annotations

import difflib
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


def added_lines(base: list[str], old: list[str] | None) -> set[str]:
    """The lines of <base> that copier's old render does not have there."""
    if old is None:
        return set(base)
    out: set[str] = set()
    sm = difflib.SequenceMatcher(a=old, b=base, autojunk=False)
    for tag, _, _, j1, j2 in sm.get_opcodes():
        if tag in ("insert", "replace"):
            out.update(base[j1:j2])
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
            d > 0 or (kind == "yaml" and indent(side[j]) > indent(side[item]) and not is_comment(side[j], kind))
        ):
            d += depth(side[j])
            j += 1
        out.append((first, item, j - 1))
        i = j
    return out


def combine(ours: list[str], theirs: list[str], added: set[str], kind: str,
            closing: bool) -> tuple[list[str], list[tuple[str, str]]]:
    result = list(theirs)
    kept = set(theirs)
    risky = [ln.strip() != "" and ln in added and ln not in kept and not ln.startswith((OURS, THEIRS)) for ln in ours]
    report: list[tuple[str, str]] = []
    if not any(risky):
        return result, report
    tail: list[str] = []
    tail_report: list[tuple[int, int]] = []
    for first, item, last in units(ours, kind):
        if not any(risky[first:last + 1]):
            continue
        span = ours[first:last + 1]
        placement = ""
        k = key_of(ours[item], kind)
        if k is not None:
            for tf, ti, tl in units(result, kind):
                if key_of(result[ti], kind) == k and indent(result[ti]) == indent(ours[item]) and result[ti] not in added:
                    placement = f"replaces {result[ti].strip()}"
                    result[tf:tl + 1] = span
                    break
        if not placement:
            before = next((ours[j] for j in range(first - 1, -1, -1) if not risky[j] and ours[j].strip() and ours[j] in result), None)
            after = next((ours[j] for j in range(last + 1, len(ours)) if not risky[j] and ours[j].strip() and ours[j] in result), None)
            if before is not None:
                at = result.index(before) + 1
                result[at:at] = span
                placement = "in place"
            elif after is not None:
                at = result.index(after)
                result[at:at] = span
                placement = "in place"
        if placement:
            report += [(placement, ln) for ln, r in zip(span, risky[first:last + 1]) if r]
        else:
            tail_report.append((len(tail), len(tail) + len(span)))
            tail += span
    for a, b in tail_report:
        for ln in tail[a:b]:
            if ln.strip() and ln in added and ln not in kept:
                where = "no old place"
                if kind == "md" and closing:
                    where += "; propose: drop it, the file's last section is that heading" if ln.strip() == THIS_PROJECT \
                        else f"; propose: under {THIS_PROJECT}, the file's last section"
                report.append((where, ln))
    result += tail
    return result, report


def cmd_combine(path: str, base_path: str, old_path: str, out_path: str) -> int:
    text, kind = lines_of(path), kind_of(path)
    found = blocks(text)
    if found is None:
        print("the conflict markers could not be read", file=sys.stderr)
        return 2
    added = added_lines(lines_of(base_path), None if old_path == "-" else lines_of(old_path))
    # The file without its blocks' "before" sides: does it close with the section?
    theirs_whole: list[str] = []
    at = 0
    for s, m, e in found:
        theirs_whole += text[at:s] + text[m + 1:e]
        at = e + 1
    theirs_whole += text[at:]
    headings = [ln for ln in theirs_whole if re.match(r"^#{1,6} ", ln)]
    closing = bool(headings) and headings[-1] == THIS_PROJECT
    out: list[str] = []
    at = 0
    for s, m, e in found:
        res, report = combine(text[s + 1:m], text[m + 1:e], added, kind, closing)
        out += text[at:s] + res
        at = e + 1
        for placement, line in report:
            print(f"risk\t{placement}\t{line}")
    out += text[at:]
    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    Path(out_path).write_text("\n".join(out) + "\n", encoding="utf-8")
    return 0


def cmd_where(path: str, line: str) -> int:
    text, kind = lines_of(path), kind_of(path)
    if line not in text:
        return 1
    n = text.index(line)
    section = ""
    if kind == "md":
        section = next((t for t in reversed(text[:n]) if re.match(r"^#{1,6} ", t)), "")
    elif kind == "toml":
        section = next((t.strip() for t in reversed(text[:n]) if re.match(r"^\s*\[", t)), "")
    elif kind == "yaml":
        keys, limit = [], indent(line)
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
    if len(argv) == 4 and argv[1] == "where":
        return cmd_where(argv[2], argv[3])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
