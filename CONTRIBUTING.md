# Contributing

plinth is a Claude Code plugin, its marketplace, and the reusable CI workflow
that repositories built with it call. Changes land through pull requests only;
`main` is protected by a ruleset that requires the checks below.

## Run the checks

```bash
claude plugin validate --strict .                           # marketplace manifest
claude plugin validate --strict .claude-plugin/plugin.json  # plugin manifest
claude plugin validate --strict skills                      # skill frontmatter
./scripts/check-ruleset.sh                                  # the wall the door applies
for t in tests/*.sh; do "./$t"; done                        # every test; install-smoke needs network
```

`tests/install-smoke.sh` installs plinth into a temporary Claude Code config
directory exactly as the README says, so it needs network and a few minutes.
Everything else runs offline in seconds.

## Land a change

1. Branch from `main`: `git switch -c <type>/<slug>`.
2. Commit with a Conventional Commits title, `type(scope): summary`, using one
   of the eleven standard types. A commit made with AI carries the trailer
   `Assisted-by: <agent>:<model>` (see `AGENTS.md`).
3. Open a pull request. The template asks what changed, how it was verified,
   and how AI was involved. CI runs `ci / install`, `ci / docs` and `CodeQL`;
   the canary job runs the reusable workflow against `canary/`.
4. Merge when green. Squash is the only merge method and the branch is deleted
   on merge.

## What a change must keep true

- Check names are the contract with every consumer. `ci / <job>` in
  `python-ci.yml` and the contexts in `ruleset.json` must stay identical;
  `tests/python-ci-contract.sh` holds the snapshot.
- Every third-party marketplace entry is pinned to a full commit SHA.
- Every `tests/*.sh` is a `run:` step in a workflow; `tests/all-tests-are-wired.sh`
  fails otherwise.
