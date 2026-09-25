# Concepts

Why plinth is shaped the way it is. For the checks themselves, see
[Required checks](../reference/required-checks.md); the vocabulary is in
[CONTEXT.md](../../CONTEXT.md).

## About what plinth is

plinth helps someone building with a coding agent keep purpose, decisions and
context, repeat small verifiable changes, and leave a repository another
developer can take over.

It is not a harness: Claude Code is. plinth adds two things around it. The
first is required checks in the environment, on GitHub, where the agent that
writes the code cannot switch them off. The second is skills the harness
loads only when a task calls for them. Nothing in the plugin enforces
anything; the plugin can be uninstalled and the checks still stand.

## About the three review layers

A change can be reviewed in three ways, and they fail differently.

- **Automated checks** are deterministic and, once required by a ruleset,
  cannot be merged past. They catch only what they assert.
- **Automated review**, such as an AI reviewer on the pull request, reads
  the change and can notice what no check asserts. It is a filter, not a
  gate: it misses things and sometimes invents them.
- **Human review** is reading the diff. For someone who builds by
  describing what they want, it is often the weakest of the three.

plinth puts most of its weight on the first layer, adds the second as an
option (`third-party / review`), and does not claim the two replace the
third. Giving less weight to human review is a choice made for this kind of
user, not a claim that checks are as good as a careful reader.

## About what green means

A check only catches what it asserts: green means the asserted properties
hold, not that the code is right. `ci / test` passing says the tests that
exist pass, not that they test the right things. `ci / secrets` passing says
gitleaks found nothing it knows, and even a red one arrives after the push:
by then the secret is on GitHub and has to be revoked, not just removed.

Some gaps are measured rather than assumed. CodeQL does not analyse a pull
request head that Dependabot pushed, and the code scanning rule passes it;
the dependency and test checks still run there, and `main` is analysed after
the merge (measured on five such heads in three repositories; heads other
bots push were not measured). The reference page says, check by check, what
each asserts.

## About who can change the wall

The ruleset stops everyone who merges, owners included, from merging past a
red check. It does not stop anyone holding administration from editing the
ruleset itself. The wall is aimed at the everyday agent, not at the
administrator.

That is why the generated `AGENTS.md` tells the agent never to ask for
administration on its everyday token: a change to the ruleset or to code
scanning is a person's decision, made in Settings or through
`scripts/with-admin-token.sh`. A weakened ruleset is noticed by
`ci / floor-check`, but only when a pull request runs it; nothing watches the
repository between pull requests.

## About guidance written for the agent

Much of what a larger project would put in explanation pages lives in files
the agent reads instead: `AGENTS.md` (with `CLAUDE.md` pointing to it),
`CONTRIBUTING.md` and `docs/agents/`. That is deliberate. `AGENTS.md` is read
natively by most coding agents, and a 2026 study of 124 pull requests across
10 repositories measured 28.64% faster median runtime and 16.58% fewer output
tokens with one present, at the same completion rate
([arXiv:2601.20404](https://arxiv.org/abs/2601.20404)).

It is also why plinth ships no set of architecture decision records. The
generated guidance leads the agent to write one into the project when a
decision calls for it.

## About pins

What plinth runs from other repositories is pinned. A consumer's CI calls
plinth's reusable workflow at a commit SHA, not a tag, and Dependabot proposes
raising it. Every third-party marketplace entry is pinned to a full commit
SHA. A commit SHA cannot move. The template is the exception: the door renders
one release tag of plinth-template, and a tag can be moved by whoever
maintains that repository; the door does not check which commit it resolves
to. Each plinth release names the tag it was tested with, and
`/plinth:floor-check` reports a repository rendered from an older tag as
behind.

A pin is also the recovery plan. plinth has one maintainer, and a SHA keeps
working only while its repository exists. If maintenance stops, fork the
marketplace and the workflow repository, point `claude plugin marketplace add`
and the `uses:` lines at the fork, and the pinned commits keep working from
there. Signed releases are not promised.

## About private repositories

The wall needs CodeQL, and on a private repository CodeQL needs a GitHub Code
Security license. Rather than raise a wall with a hole in it, the door stops
before creating a private repository. It points to a public repository
first. GitLab Free is the alternative for code that must stay private: it has
protected branches and requires pipelines to pass, with no CodeQL and no push
protection. A lower private wall, with another scanner in CodeQL's place, is
a later option, not built.
