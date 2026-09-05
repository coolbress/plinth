# Configure the third-party reviewer

Make a review by a reviewer that is not the author's own agent session part of
the checks on a repository, and optionally part of its wall.

The check is `third-party / review`. It passes when the Codex code reviewer
(`chatgpt-codex-connector[bot]`) has looked at the pull request's current
commit; it never blocks on what the reviewer said. Drafts are not reviewed;
the first review happens when the pull request is marked ready, and every push
after that is reviewed again.

## 1. Enable the reviewer on the repository

Turn on Codex code review for the repository in the Codex settings,
`chatgpt.com/codex/settings/code-review` (a ChatGPT subscription; no API key
and no secret in the repository). The page needs a login, so it is not linked.

## 2. Call the reusable workflow

Add `.github/workflows/third-party.yml` to the repository:

```yaml
name: third-party
on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]
  pull_request_review:
    types: [submitted]
permissions:
  contents: read
  pull-requests: write
concurrency:
  group: third-party-${{ github.event.pull_request.number }}
  cancel-in-progress: false
jobs:
  third-party:
    uses: coolbress/plinth/.github/workflows/pr-review.yml@<commit-sha> # vX.Y.Z
```

Keep the job name `third-party`; the check name comes from it. To accept a
different reviewer, change what is posted to summon it, or wait longer than
15 minutes, pass `reviewer-logins`, `ask-comment` or `wait-seconds` under `with:`. The reviewer reads its
instructions from `## Code Review Rules` in the repository's `AGENTS.md`; that
section can only change in a pull request that changes nothing else.

## 3. Make it part of the wall (optional)

Once the check has reported on at least one pull request, add it to the
required checks. This needs repository administration, so it goes through the
token prompt:

```bash
scripts/with-admin-token.sh scripts/upgrade-ruleset.sh <owner/name> 'third-party / review:15368'
```

`15368` is the GitHub Actions app. The tool refuses a name that has never
reported on the repository, because a required check that never arrives means
nothing merges. It looks at the five most recent pull requests and the three
most recent commits on the default branch; run it while the pull request that
reported the check is still among them.

## Optional: a security review by Claude Code

A second opt-in check in the same slot, with an API key instead of a
subscription: [anthropics/claude-code-security-review](https://github.com/anthropics/claude-code-security-review)
reads the diff and comments on security findings. Add it as its own workflow,
put the key in the `CLAUDE_API_KEY` secret, and add
`anthropics/claude-code-security-review@*` to the repository's Actions allowlist
(`/plinth:new-project` allows GitHub-owned actions and plinth only). The action
is not hardened against prompt injection; use it on trusted pull requests only,
and keep "require approval for all external contributors" on.

```yaml
name: security-review
on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]
permissions:
  contents: read
  pull-requests: write
jobs:
  security-review:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          fetch-depth: 2
          persist-credentials: false
      - uses: anthropics/claude-code-security-review@0c6a49f1fa56a1d472575da86a94dbc1edb78eda # main, 2026-02-11
        with:
          comment-pr: true
          claude-api-key: ${{ secrets.CLAUDE_API_KEY }}
```

Like the third-party review, it is a filter, not a gate: read what it says,
and do not add it to the required checks.

## Review before the pull request

For a look before opening the pull request, from the branch:

```bash
codex review --base main
```

A review by the same agent session that wrote the change is not a third-party
review, whatever tool runs it.
