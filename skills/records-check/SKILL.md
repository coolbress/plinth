---
name: records-check
description: Read-only count of what is out of place in a GitHub repository's issue and pull-request records, judged by the repository's own written conventions - references to nothing, home paths, bodies near GitHub's size limit, completed issues with no ending, merged pull requests with no AI trailer - plus unticked acceptance criteria listed for a person to read. Changes nothing. Use at a milestone's end, when coming back to a project, or when the user asks whether the issues and pull requests are in order.
argument-hint: "[owner/name]"
disallowed-tools: Edit, Write, NotebookEdit
---

# Records check

Counts what is out of place in the issue and pull-request records, one line
per item, and never changes a record. Not a required check: no CI job runs
it. Run it at a milestone's end, or when coming back to a project.

## Run

From the repository root (the current directory). The repository on GitHub is
the argument if the user gave one (`$ARGUMENTS`), otherwise the remote:

```bash
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)"   # or the argument
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/records-check.py" --root . ${repo:+--repo} ${repo:+"$repo"}
```

It reads every issue and pull request with `gh`'s login, in pages of 20, so
a large repository takes minutes. It exits non-zero only when it could not
run (no repository, or a page of the list not read): say so and stop; a
partial count is not given. A GitLab checkout prints `GitLab: not read` and
nothing else.

## What it judges

Every line is `PASS`, `WARN`, `INFO` or `SKIP`. The last line counts the
items per rule, the rules not checked for want of a convention, and the
records not verified.

- **Facts**, whatever the conventions say: `ref` (a `#N` or `owner/repo#N`
  outside code that was deleted, 410, or is a 404 above the highest number
  that repository has used), `home-path` (a home path in a body, by line and
  form; it never prints what followed the prefix, and neither do you),
  `body-size` (a body at 90% or more of GitHub's 65,536 limit, in characters
  or UTF-8 bytes). Each `ref` `WARN` or `SKIP` line names the records the
  reference was read in. What `ref` cannot see: a bare `#N` meant for another
  repository whose number also exists here resolves, so it passes. A table
  of another repository's numbers written as bare `#N`, or a `#236` that
  links to the wrong issue here, looks like a right link from this
  repository's records alone. The `ref` `PASS` line means every reference
  read resolves or is a `SKIP` above, not that each points where it was
  meant to.
- **Conventions**, judged only against what the repository's own files say:
  its issue and pull-request templates (local, else the owner's `.github`),
  `CONTRIBUTING.md`, `docs/agents/issue-tracker.md`, `AGENTS.md`. Each line
  names the file. `ending`: a completed `task` or `bug` with none of the
  ending headings those files name (a `Decision` heading, a record's ending,
  is excepted). `trailer`: a merged pull request with no AI trailer in its
  body or merge commit, an `INFO`: a person or a bot may have written it, so
  it is never a violation. With no file read for a rule, its line is
  `not checked: convention not read`.
- **For a person to read**: completed issues with unticked acceptance
  criteria, with line numbers. Whether the ending says why is not judged:
  read them, or hand the list to the person.

## Report

Lead with the last line's counts in plain words: how many items per rule,
how many were not verified, and which rules were `not checked`.

Then give the checker's output whole; do not shorten it or drop `PASS`
lines.

After the output, list every `WARN` line again, and under each one write one
line that fixes it, for the person to do or hand to an agent. Never edit,
comment on or close a record yourself.

| Rule | Fix line |
| --- | --- |
| `ref` | Edit the body so the reference names the issue or pull request meant, or remove it |
| `home-path` | Replace the path in the body with `~/...` or the condition it shows; the earlier text stays in the edit history until the owner deletes that revision |
| `body-size` | Move detail out of the body into a linked file or a comment, keeping the decision and the outcome in the body |
| `ending` | Add the heading the line names, from the file it names, saying how the issue ended and what was verified |

Under a `not checked: convention not read` line, the fix line says where to
write the convention down, and offers plinth's default as a suggestion, not
a requirement: an issue ends in `## Outcome` (a record in `## Decision`), in
`docs/agents/issue-tracker.md`; a commit made with AI carries
`Assisted-by: <agent>:<model>`, in `CONTRIBUTING.md`; a task carries
`## Acceptance criteria`, in its issue form. The repository's own
conventions win: never tell the person a record is missing something their
files do not ask for.

`INFO  trailer: ... no trailer` lines take no fix line.
