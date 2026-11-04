# GitLab pipeline

plinth ships a pipeline for GitLab.com, [`gitlab/python-ci.yml`](../../gitlab/python-ci.yml),
beside the GitHub workflow `python-ci.yml`. It is the first part of a GitLab
path on GitLab.com Free ([#353](https://github.com/coolbress/plinth/issues/353)).
It has run green on a GitLab.com Free private project, on the default branch
and on a merge request ([measured](#measured-on-gitlabcom-free)).
plinth-template renders a project that includes it (`host: gitlab`, from
v1.13.0), and `/plinth:new-project <name> --host gitlab` creates one.
`/plinth:floor-check` reads a GitLab project: the checkout's files, and
through `glab` the protected branch, the merge checks, squash and
fast-forward, the labels, and this include on the default branch, judged by
this pipeline's own `floor-check` rule.

## Include it

A project's `.gitlab-ci.yml` includes the file from GitHub, at a full commit
SHA, and passes inputs only where it wants something other than the default:

```yaml
include:
  - remote: https://raw.githubusercontent.com/coolbress/plinth/<commit-sha>/gitlab/python-ci.yml
    integrity: sha256-<checksum>
    inputs:
      max-diff-lines: 400
```

The checksum is the file's SHA-256 in base64:

```sh
curl -fsSL https://raw.githubusercontent.com/coolbress/plinth/<commit-sha>/gitlab/python-ci.yml \
  | openssl dgst -sha256 -binary | openssl base64 -A
```

The file defines its own `workflow:` rules (merge request pipelines, and the
default branch after a merge) and puts every job in the `test` stage. A
project that defines its own `workflow:` replaces those rules and has to keep
merge request pipelines: on a branch pipeline for a commit an open merge
request carries, `pr-title`, `deps`, `diff-size` and `test`'s changed lines
fail rather than read it as not a merge request. A project that lists
`stages:` keeps `test` among them.

## What the commit SHA and the checksum hold

| | Holds | Does not hold |
| --- | --- | --- |
| The commit SHA in the URL | GitHub serves the same bytes for a commit SHA for as long as it serves them at all: nobody can change the file behind that URL by pushing to plinth | The fetch still depends on GitHub being reachable when the pipeline is created. Without a checksum, nothing on GitLab's side checks the bytes it received |
| `include:integrity` | GitLab compares the fetched file with the checksum before the pipeline starts and fails the pipeline, with no job, when they differ: ``Remote file `…` failed integrity check!``. GitLab.com Free does this (measured below). The keyword arrived in GitLab 17.9 | It is one more value to change with every raise of the commit SHA, and nothing raises it for you: a checksum left behind fails every pipeline until it is corrected |

## The wall on GitLab Free

These are project settings. `/plinth:new-project <name> --host gitlab`
sets them, reads each back, and rolls the project back if one does not hold
(where the login can delete it: a group Maintainer cannot, so the project
stays for an Owner to delete or finish);
on a project made another way they are set by hand:

- The default branch is protected: no force push, changes through merge
  requests only, Maintainers merge.
- The merge check "Pipelines must succeed" is on, and "Skipped pipelines are
  considered successful" is off.
- Squash is required and the merge method is fast-forward, so the default
  branch gains one commit per merge request.

What it cannot hold: GitLab Free has no required checks by name. The merge
check takes the pipeline as a whole, and the pipeline is built from the merge
request's own `.gitlab-ci.yml`. A merge request that removes a job, or the
include, runs without it and still merges when what is left passes. Nothing
inside that merge request's pipeline can see this, `floor-check` included:
only a read from outside the merge request, after the merge, can. Holding
it before the merge takes GitLab Ultimate's pipeline execution policies.

## Jobs

The jobs have `python-ci.yml`'s names and run its checks with the same pinned
tools. `tests/gitlab-ci-cases.sh` keeps the names, the inputs, the tool
pins, the commit types, the coverage requirements, the changed-lines judge
and the diff-size functions the two files share equal, and runs `pr-title`,
`deps`, `floor-check` and `diff-size` on fixtures. GitLab does not enforce the names; this page
and that test keep them. Each job writes its verdict lines (the forms in
[required checks](required-checks.md#what-a-jobs-summary-says)) at the end of
its log under `Verdict`: GitLab has no job summary and no annotations, so a
`not yet confirmed` line appears in the log only.

| Job | Differs from GitHub |
| --- | --- |
| `lint` | No zizmor: it audits GitHub Actions only, and nothing here audits `.gitlab-ci.yml`. A `not yet confirmed` line says so on every run |
| `typecheck` | Nothing |
| `test` | The changed lines are judged against the merge request's merge base (`CI_MERGE_REQUEST_DIFF_BASE_SHA`); GitLab checks out the merge request's head, not a merge commit |
| `build` | Nothing |
| `secrets` | Nothing in the job. GitLab Free has no secret push protection, so this job is the only secret check, and it runs after the secret has reached GitLab |
| `deps` | osv-scanner 2.6.0 (checked against its SHA-256) instead of GitHub's dependency review. It downloads the OSV database once, scans `uv.lock` at the head and at the merge base offline against that one copy, and fails on an advisory the head has and the base does not, at `deps-fail-on-severity` or above. The severity is the advisory's highest CVSS score: critical from 9.0, high from 7.0, moderate from 4.0, low above 0; an advisory with no score counts as at or above. A scan that cannot run (the download, a tool error, a lockfile it cannot read) fails the job. Both scans use an empty configuration of plinth's, so an `osv-scanner.toml` in the project cannot ignore an advisory |
| `diff-size` | The pipeline definition is `.gitlab-ci.yml` and anything under `.gitlab/ci/`. The description is `CI_MERGE_REQUEST_DESCRIPTION`, which GitLab cuts at 2700 characters; a path named past the cut reads as not named. A listed change the description does not name is a WARN in the log, never a failure: GitLab Free has no required approvals. The agent's own rules (`AGENTS.md`, `CLAUDE.md`, `.claude/settings.json`, `.claude/skills/`, `.claude/output-styles/`) are listed as on GitHub, before the pipeline definition, so a move between `.gitlab/ci/` and one of them gives the agent's reason; on GitHub such a change can need an admin's approval, here it is a WARN like the rest. The `web` input's rows are not here |
| `pr-title` | The merge request's title. A draft prefix (`Draft:`, `[Draft]`, `(Draft)`) is left out, since marking the merge request ready removes it without a new pipeline. A title ending in `(#N)` passes: GitLab's squash commit does not add the merge request's number to its title. GitLab starts no pipeline when a merge request is retitled, so a title changed after the last pipeline is never checked, and the squash commit takes it. Then the description, [below](#the-description-in-pr-title) |
| `floor-check` | Reads only the pipeline definition (`CI_CONFIG_PATH`, `.gitlab-ci.yml` by default), with PyYAML 6.0.3 installed by hash, so it reads YAML as GitLab does (a duplicate key's last value, GitLab's tags as data); a definition that is not YAML, or a PyYAML that does not install, fails. An inputs header (`spec:`, `---`, then the configuration) is read as GitLab lays it out. A URL that names plinth in any other form than the pinned raw URL (a query, a fragment, another host) fails. It reads the top-level `include:` only, so include this file from the root definition, not from a nested local file. It fails unless every include of this file there is at a full commit SHA, and passes the checksum only when each of those includes names one; otherwise that the fetched bytes are not checked is a `not yet confirmed` line. The protected branch, the merge checks, this include on the default branch after the merge, and the rest of the floor are `not yet confirmed` lines on every run, left to `/plinth:floor-check`, never passes |

### The description in `pr-title`

GitLab closes an issue when a merge request whose description has a
closing keyword before the issue merges into the default branch, in a
sentence as much as on a line of its own. `pr-title` fails a description
whose closing keyword stands before an issue that the closing line
(`Closes #N` in a paragraph of its own, directly above the attribution)
does not name, and quotes the line to reword. It decides as `ci / pr-title`
does on GitHub, with two differences:

- GitLab's own list of the issues a merge closes
  (`GET /projects/:id/merge_requests/:iid/closes_issues`) answers 404 to
  the job token (`CI_JOB_TOKEN`), measured below. So the job applies
  GitLab's default closing pattern to the description: the keywords
  `close`, `fix`, `resolve` and `implement` in every form GitLab lists, an
  optional colon, then `#N`, `project#N`, `group/project#N`, `GL-N`,
  `[issue:N]`, `[issue:group/project/N]`, or an issue, incident or work item
  URL. A closing line may give each issue its own keyword
  (`Closes #65, fixes #66`). What it cannot see is a `not yet confirmed` line on every run that
  does not fail, never a pass: a project's or instance's own closing
  pattern, and the issues the merge request's commit messages close, which
  GitLab's list also counts (measured below).
- A project that turned off "Auto-close referenced issues on default
  branch", or changed the pattern, can see a fail for an issue GitLab
  would not close. Rewording the sentence passes either way.

The description is read whole: `CI_MERGE_REQUEST_DESCRIPTION` when GitLab
did not cut it, and the merge request API with the job token when it did
(at 2700 characters), asking the merge request's own project: a fork's
pipeline runs in the fork. Whether a fork's job token may read the merge
request there is not measured. A description that cannot be read fails.

GitLab starts no pipeline when a description is edited, as for a retitle.
An edited description is checked on the next pipeline only: after
rewording, run a new pipeline for the merge request, or push a commit.
Until then the merge request shows the last pipeline's result, and a
pipeline that passed before the edit lets it merge with the new text.

## Inputs

`working-directory`, `max-diff-lines`, `deps-fail-on-severity`,
`diff-size-exclude` and `extra-python-versions`, with `python-ci.yml`'s
meanings and defaults. `floor-check-required-checks` has no GitLab
counterpart: there are no required checks to list.

## Measured on GitLab.com Free

On 2026-10-13, on a private project in a personal namespace on the Free plan,
with plinth's `canary/` project and this file included at commit `2c968ba`
with its checksum:

| Run | Result |
| --- | --- |
| The default branch's first push | All nine jobs passed; the not-a-merge-request jobs said `does not apply` |
| A merge request changing two lines with a test | All nine jobs passed: `diff size, 10 lines`, `all 2 changed lines ran`, no added dependency version with an advisory, the title passed. The merge request could merge |
| A merge request with a wrong checksum | The pipeline failed with no job (`failed integrity check`), and the merge request could not merge (`ci_must_pass`) |
| Compute minutes | GitLab counted 8 minutes for the two green pipelines (500 seconds on `saas-linux-small-amd64`), about 4 per pipeline: the nine jobs run 23 to 34 seconds each, most of it pulling the image and installing tools. At GitLab.com Free's 400 minutes a month per top-level namespace, that is about 100 pipelines a month |

On 2026-11-03 (UTC), on another private project in a personal namespace on the
Free plan, with this file's `pr-title` included as a local file and the
other jobs turned off ([#782](https://github.com/coolbress/plinth/issues/782)):

| Run | Result |
| --- | --- |
| The job token on GitLab's API, from a merge request pipeline | `GET .../merge_requests/:iid/closes_issues` answered 404, `GET .../merge_requests/:iid` answered 200 with the whole description, and GraphQL answered 401 |
| A description with "the two fixes #1 decided" in a sentence | `pr-title` failed, naming #1 and quoting the line. GitLab's own list, read with a maintainer's token, also held #1 |
| The description edited to a closing line only, `Closes #1` | No pipeline started in the 90 seconds after the edit. A pipeline run by hand passed, with the description's `not yet confirmed` line |
| The description edited to `Part of #1` and a reworded sentence | A pipeline run by hand passed, with the same line |
| A 3162-character description whose "fixes #2" stands past the 2700-character cut | `pr-title` failed, naming #2: the description was read whole through the API |
| A commit message on the merge request's branch with "fixes #2", and a description with no closing keyword | GitLab's list held #2, and a squash merge closed #2. The job reads the description only, so it does not see this |
