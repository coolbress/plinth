# How to add a second person

Before this page: a project made by `/plinth:new-project`, run by one person
and an agent. `/plinth:guide` points here once it sees someone besides you
who can be assigned issues or who opened a pull request. Do the steps in
order, before that person's first change.

Every default plinth sets is for one person and an agent. Two of them turn
around when a second person arrives:

- **Who can merge.** The merge ruleset ("main: merged by an admin",
  `ruleset-merge.json`) lets only the repository's admin merge.
- **Who looks at a change.** The main ruleset requires no approval
  (`required_approving_review_count: 0`), so nothing makes the two of you
  look at each other's changes.

## 1. Where the repository lives

A repository under a personal account has two permission levels: the owner
and collaborators. A collaborator cannot be made an admin
([GitHub Docs](https://docs.github.com/en/account-and-profile/setting-up-and-managing-your-personal-account-on-github/managing-user-account-settings/permission-levels-for-a-personal-account-repository)).
The merge ruleset exempts only the admin role, so it refuses a
collaborator's merge. That was measured for the agent's own account on
[#568](https://github.com/coolbress/plinth/issues/568). For a second person's
account it is not measured yet:
[#1158](https://github.com/coolbress/plinth/issues/1158) records that run.

So that both of you can merge, move the repository to an organization where
both of you are admins:

1. Create a free organization, or use one you have, and invite the second
   person as an owner.
2. In the repository, **Settings → General → Danger Zone → Transfer**, to
   that organization. GitHub redirects the old address.
3. Run `/plinth:floor-check` in the project: it says whether the rulesets and
   the checks still stand after the move.

An organization-owned repository stays where it is: give the second person
the admin role there.

## 2. Invite them, with two-factor authentication

Turn on **Require two-factor authentication** in the organization's
**Settings → Authentication security** before you invite them. Then add them:
in the organization as an owner, or in the repository under **Settings →
Collaborators and teams** with the Admin role.

## 3. A CODEOWNERS file that names the two of you

Add `.github/CODEOWNERS` through a pull request, as any other change:

```text
*         @<your login> @<their login>
/.github/ @<your login>
```

Name people only, never the agent's own account. An approval counts toward
the rule when it comes from someone with write access, or from a code owner
([GitHub Docs, rules](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)).
The agent's own account
([give the agent its own account](give-the-agent-its-own-account.md)) has write
access, so with one approval required, its approval would count. Code
owners' review, with only people in this file, is what stops that. Whether
GitHub holds to it with the agent's account is measured in run 2 of
[#1158](https://github.com/coolbress/plinth/issues/1158).

The `/.github/` line keeps the workflows and this file yours to approve.
For other paths one of you should review, add a line each, as
[code owners](turn-on-what-starts-off.md#code-owners) says.
`/plinth:guide` stops pointing here once the file is on the branch it reads.

## 4. The two-person rules

From a plinth checkout, after the CODEOWNERS pull request merges:

```sh
scripts/with-admin-token.sh scripts/add-ruleset-rule.sh --dry-run <owner/name> two-people
scripts/with-admin-token.sh scripts/add-ruleset-rule.sh <owner/name> two-people
```

The `two-people` preset changes three fields of the main ruleset's
pull-request rule, and nothing else:

- `required_approving_review_count`: 0 to 1;
- `require_code_owner_review`: false to true;
- `required_review_thread_resolution`: false to true.

`--dry-run` prints the three before and after and writes nothing. The merge
ruleset is not touched, and `bypass_actors` stays empty, for everyone.

The main ruleset also has the preview rule **Require an additional approval
for unattributed Copilot pull requests**
(`require_extra_approval_for_unattributed_changes`, on in `ruleset.json`).
While the count is 0 it does nothing. Once the count is 1, a Copilot pull
request that is not attributed to a person needs two approvals from people
with write access (GitHub Docs, read 2026-11-25). The preset leaves it on:
with two people, that is still the two of you.

`/plinth:floor-check` warns when this and the people do not match: two or
more people can merge and no approval is required, or no more people can give
an approval that counts than the approvals required (an author cannot approve
their own pull request; with code owners' review on, those who count are the
people CODEOWNERS names). When CODEOWNERS names a team, its members are not
read, so it says the count was not made instead.

## 5. A token and a plinth install for each person

Each person uses their own login, their own agent token
([give the agent a token](give-the-agent-a-token.md)) and, if they want one,
their own agent account. Nobody shares a token. Each installs plinth on their
own machine:

```sh
claude plugin marketplace add coolbress/plinth
claude plugin install plinth@plinth
```

## 6. One pull request by the second person

The second person opens one small pull request; you approve it, and it
merges. That shows the invitation, CODEOWNERS and the rules all work, before
the first change that matters.

## When one of you is away

With one approval required, a change cannot merge while the other person is
away. Lower the count with the same command, and say so in an issue first:

```sh
scripts/with-admin-token.sh scripts/add-ruleset-rule.sh <owner/name> one-person
```

`one-person` puts the three fields back to `ruleset.json`'s values. When they
are back, run `two-people` again and close the issue. Never add a bypass actor
instead: it would hold for every rule, not only this one.

## Handing the project over

A handover goes through this page first. The new owner joins as a second
person, restores the backup and ships one fix through a pull request you
approve. Only then is the repository transferred to them. After that, remove
the old owner, replace the old owner's tokens in the repository's secrets,
and run `/plinth:floor-check`. The issue form "End or hand over this project"
lists the rest.
