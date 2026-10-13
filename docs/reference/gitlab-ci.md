# GitLab pipeline

plinth ships a pipeline for GitLab.com, [`gitlab/python-ci.yml`](../../gitlab/python-ci.yml),
beside the GitHub workflow `python-ci.yml`. It is the first part of a GitLab
path on GitLab.com Free ([#353](https://github.com/coolbress/plinth/issues/353)).
It has run green on a GitLab.com Free private project, on the default branch
and on a merge request ([measured](#measured-on-gitlabcom-free)).
`/plinth:new-project` and `/plinth:floor-check` do not handle GitLab yet, and
plinth-template does not render it yet.

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

These are project settings, made by hand for now:

- The default branch is protected: no force push, changes through merge
  requests only, Maintainers merge.
- The merge check "Pipelines must succeed" is on, and "Skipped pipelines are
  considered successful" is off.

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
| `diff-size` | The pipeline definition is `.gitlab-ci.yml` and anything under `.gitlab/ci/`. The description is `CI_MERGE_REQUEST_DESCRIPTION`, which GitLab cuts at 2700 characters; a path named past the cut reads as not named |
| `pr-title` | The merge request's title. A draft prefix (`Draft:`, `[Draft]`, `(Draft)`) is left out, since marking the merge request ready removes it without a new pipeline. A title ending in `(#N)` passes: GitLab's squash commit does not add the merge request's number to its title. GitLab starts no pipeline when a merge request is retitled, so a title changed after the last pipeline is never checked, and the squash commit takes it |
| `floor-check` | Reads only the pipeline definition (`CI_CONFIG_PATH`, `.gitlab-ci.yml` by default): it reads the top-level `include:` only, so include this file from the root definition, not from a nested local file. It fails unless every include of this file there is at a full commit SHA, and passes the checksum only when each of those includes names one; otherwise that the fetched bytes are not checked is a `not yet confirmed` line. The protected branch, the merge checks, every job's presence and the rest of the floor are `not yet confirmed` lines on every run, never passes |

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
