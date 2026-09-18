# Configure the third-party reviewer

Add a review signal from a reviewer other than the author's own agent session
to the checks on a repository, and optionally to its wall.

The check is `third-party / review`. It passes when the Codex code reviewer
(`chatgpt-codex-connector[bot]`) has left a review, a review comment, a
completion comment, or a `Completed` row in its summary comment's table, on
the pull request's current commit. The row is there because a review started
by a push that found nothing has left only that (measured on #190, 2026-09-18:
the check waited the full window on a commit the reviewer had looked at, #191);
a `Running` row does not count. The row names its commit in seven characters
and the completion comment in ten, which a later head can be made to share, so
each counts only when its time (the row's completion, the comment's
`created_at`) is later than the newest push of the current head in the
repository's activity log, and the head is the one commit the branch has
pointed at, by that log, that begins with those characters; where that push
cannot be read (a fork's branch, a failed call, a log of a full page of 100
pushes) neither counts and the log says which was left out and why. A fork's
branch is not in the base repository's log (measured on two fork pull requests
of `cli/cli`, 2026-09-18), so a pull request from a fork passes on a review, a
review comment or the security review's `completed` marker, not on the
completion comment or the row: a
zero-finding review that leaves only those waits the window and fails, and a
person asks for another review or merges past an optional check (#193). That is evidence of
participation: it does not say the whole change was reviewed, that the
findings were handled, or anything about the code's quality. It never blocks
on what the reviewer said. Nor is it a barrier against people with write
access to the repository. Three of the signals are issue comments (the security
review's marker, the completion comment, the summary row), and the check does not look at
whether such a comment was edited after it was posted, or by whom, so one that
someone else edited can still count. GitHub lets people with write access edit
other people's comments (its documentation; not tried here); the pull request
page marks an edited comment and keeps its history (#196). Drafts and Dependabot's pull requests are not
summoned, nor release pull requests where that is turned on ([below](#pull-requests-it-passes-without-summoning)); any other ready pull request must
show a signal on its current head. The check posts a summons only when the
caller gives it a person's token ([below](#summoning-the-reviewer)); without one
it waits for the reviewer's own trigger.

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
  pull-requests: read
concurrency:
  group: third-party-${{ github.event.pull_request.number }}
  cancel-in-progress: false
jobs:
  third-party:
    uses: coolbress/plinth/.github/workflows/pr-review.yml@<commit-sha> # vX.Y.Z
```

Keep the job name `third-party`; the check name comes from it. To accept a
different reviewer, or wait longer than 15 minutes, pass `reviewer-logins` or
`wait-seconds` under `with:`; `ask-comment` changes the summons text, which is
posted only with a token ([below](#summoning-the-reviewer)).
`reviewer-logins` says whose signal counts; it does not check that the
reviewer is independent of the author. The reviewer reads its instructions
from `## Code Review Rules` in the repository's `AGENTS.md`. The check fails a
pull request that changes that section together with other files, so a rule
change arrives on its own and is visible; it compares only that section and
only within one pull request, so it is not a guarantee that the instructions
cannot be weakened.

### Pull requests it passes without summoning

On one kind of pull request, and on a second if you turn it on, the step that
looks for a review passes at once, posts no summons and looks for no review;
its log says which. The step before it still runs on them: one that changes
`## Code Review Rules` together with other files fails the check like any
other.

- `Dependabot pull request: not summoned`: the author is Dependabot
  (`dependabot[bot]`) and every push to its branch was Dependabot's, up to
  the current head, by the repository's activity log. The log names the
  account that pushed; a commit's author line does not count, because
  whoever writes a commit chooses it. Once anyone else has pushed to the
  branch, an "Update branch" included, it is looked at like any other, and it
  stays so if Dependabot later overwrites that push. No
  other bot is on the list: a coding agent's account is a bot too (`Copilot`,
  `cursor[bot]`, `claude[bot]`, `devin-ai-integration[bot]`), and what it opens
  is code, which is what the review is for. Renovate is not on it either; it
  has not been measured here.
- `release pull request: not summoned`, only with
  `pass-release-pull-requests: true` under `with:`. The title must be exactly
  `chore(release): vX.Y.Z`, the one `scripts/make-release.sh` writes; one that
  only resembles it (`chore(release-notes): …`, `chore(release): v2 docs
  only`) is summoned as usual. The author of a pull request chooses its title,
  so with this on anyone who can open a pull request, an agent included, can
  skip the review by choosing that title. It is off by default; leave it off
  where `third-party / review` is a required check. This repository turns it
  on: the check is optional here and a release is four generated lines.

On these the check is no evidence that anyone looked. If `third-party /
review` is one of your required checks, such a pull request meets it with no
review attached. To have one reviewed, comment the summons (`@codex review`)
on it yourself; the check still passes either way.

### Summoning the reviewer

The check does not start a review by itself. It used to comment `@codex
review` as `github-actions[bot]` whenever no review was attached; measured
on #186 (2026-09-18) that drew no review in the full wait, twice, while the same
text from a person's account started one sixteen seconds later, and of seven
reviewers read that day (Codex, Copilot, CodeRabbit, Gemini Code Assist, Qodo,
Cursor Bugbot, Claude Code) none documents honouring a bot's mention. So the
summons is posted only when the caller passes a person's token:

```yaml
jobs:
  third-party:
    uses: coolbress/plinth/.github/workflows/pr-review.yml@<commit-sha> # vX.Y.Z
    secrets:
      summons-token: ${{ secrets.CODEX_SUMMONS_TOKEN }}
```

The token must be the repository owner's, the account connected to the
reviewer: the check reads the token's login before posting and fails at once,
with the reason, when the login cannot be read, is another person's, or the
post itself is refused. The login is compared with the repository's owner, so
this fits a repository owned by a person; in an organization's repository the
owner is the organization and no person's token matches (an input naming the
person is not built until someone needs it). A login read that fails for a
reason other than the token, a rate limit or an outage, fails the same way;
the error line carries `gh`'s own words so the two are told apart, and a
re-run fixes the second. A pull request opened from a fork gets no secrets
from GitHub, so on it the token is empty however the caller is set: nothing is
posted, the log says why, and with automatic reviews off such a pull request
is reviewed only when a person comments the summons.
With it the summons goes out as that person, at most twice per commit, and
`ask-comment` is its text. Without it nothing is posted, the job needs only
`pull-requests: read`, and the check waits for the reviewer's own trigger,
which with the provider's automatic reviews on arrives about four minutes after
a push (measured on #186). This repository gives no token: automatic reviews
are on. A token is what a repository wants when it turns automatic reviews off
to leave Dependabot and release pull requests unreviewed; it then also takes
on a token that expires, a person's name on every summons, and a check that
turns red on every pull request when the token stops working (#185).

Two things this does not do. It does not stop the provider's own app from
reviewing anyway: Codex starts on its own when a pull request is opened or
marked ready wherever its "Automatic reviews" toggle is on, and no setting
narrows that by author or title (seen on `chatgpt.com/codex/settings`,
2026-09-18: a repository offers `Review all PRs`, `Review team PRs` and
`Follow personal preferences`; the personal toggle, on the code review tab and
the security review tab, is the off switch). Leave that toggle on. The summons
this check posts is not a substitute for it: measured on #186 (2026-09-18,
toggle off), two `@codex review` comments from `github-actions[bot]` drew no
review in the check's full wait and the check failed, while the same text
commented by a person's account started a review sixteen seconds later. What
the summons has done on its own, with the toggle on, has not been measured;
the reviews on every earlier pull request here arrived while the toggle was
on. Another repository measured the same and moved its summons to a token
owned by the Codex-connected person (hide212131/hane#57, read 2026-09-18);
this workflow does the same only when given `summons-token`, so with the
toggle off and no token a pull request gets no review until a person comments
the summons. Do not spell the summons in a pull
request description: one that did (#184) drew a comment from the reviewer
asking for an environment. And skipping the summons skips nothing the toggle
does not already give: on the first Dependabot pull request here (#178) the
reviewer had nothing to say about the bump and one correct comment about this
repository's text next to it.

## What to do with the findings

The check turns green when the reviewer has posted, whatever it found. The
findings still have to be handled, in the pull request, before merging:

| The reviewer said | Do |
| --- | --- |
| A defect you can reproduce or confirm from the code | Fix it, add or run the check that would have caught it, push |
| A false positive, or something that does not apply here | Reply on the thread with the reason, pointing at the code or the requirement |
| An important risk you cannot judge | Leave it open and say so in the pull request; ask for another look (`/security-review`, a second reviewer) rather than merging past it |

An agent handling the findings does the same, and does not close the matter
by asking "merge anyway?": the person merging should see what was found, what
was fixed, and what is still open.

Read the inline comments, not only the summary comment. The summary's
wording does not cover them: on #174 the summary read "Didn't find any major
issues" while the same review had left one inline P2 (a step order in `ci /
tools`), and the pull request was merged with it unanswered; the P2 was right
and became #175. Once the check has decided, its log and its job summary list
the accepted reviewer's inline comments on the reviewed head with their URLs,
or say `no inline comments on this head`; when the comments could not be
fetched at all it says `inline comments: could not be read` instead of zero,
and the live query below is the list. That list is what the check saw
when it decided; a review that finishes later (the security review has taken
over 30 minutes) is not on it. The live list, filtered the same way, with
`<login>` one of the caller's `reviewer-logins` (the default is
`chatgpt-codex-connector[bot]`; with several logins, one call per login):

```bash
gh api repos/<owner>/<repo>/pulls/<n>/comments --paginate \
  --jq '.[] | select(.user.login == "<login>" and .original_commit_id == "<head sha>") | .html_url'
```

Without the filter the endpoint returns every review comment on the pull
request, every head and every author. The pull request description then says
what happened to each one: fixed, answered with the reason, or moved to an
issue. On #180 the summary comment still read `running` when the inline
comment was already there.

## When to stop

A model reviewer samples; it does not enumerate. Every fix is new surface, and
a new head is a new review, so "until it finds nothing" is not a stopping
rule. On one release script here it took seven rounds and thirteen findings,
and the last four came from the fixes themselves. Stop by the consequence of
what is left, not by the reviewer's severity label:

| What is left | Do |
| --- | --- |
| Irreversible, or reaches other people: a wrong tag or release, `main` polluted, a check name consumers require, a security hole | Fix before merging, whatever round it is |
| Recoverable locally with one command (a leftover branch, a retry that fails) | Fix if it is a few lines and one test case; otherwise open an issue and merge |
| Only the maintainer can cause it, or hypothetical, and the consequence is not in the first row | Reply with the reason; no change |

The first row wins whenever it applies: who can trigger a defect is independent
of how far its consequence reaches. An important risk that cannot be judged
yet is in no row: it stays open until another look classifies it, as the table
above says, and the budget below does not merge past it.

Budget: after the first review, two rounds of fixes. From the third round on,
fix only the first row; the second row becomes an issue, answered on the
thread with the link; the third row still gets its reply and nothing else; and
the pull request merges. Say on the thread what was not changed and why, so
the next reader does not reopen it.

The same rule bounds the code: a script guards outcomes that cannot be undone
and documents the states that can. A reviewer asking for a guard on a
recoverable state gets the documentation, not the guard.

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
