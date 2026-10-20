# How to give the agent its own account

Before this page: [the agent's token](give-the-agent-a-token.md), its
step 5 included. After it: [the four things by hand](set-four-things-by-hand.md),
then step 2 of [Run a project](run-a-project.md).

[The agent's token](give-the-agent-a-token.md) stops the agent from changing the checks, but not from
merging. GitHub decides who may merge by the account, not by the token: your
account owns the repository, so any token of yours can merge, even one
without Administration (#517 measured this). While the agent works under
your account, "ask before you merge" is something it is asked to do, not
something GitHub enforces.

A repository `/plinth:new-project` made carries a second rule set on
GitHub (a ruleset) that lets only the repository's admin merge. With the
agent on an account of its own, which is not the admin, GitHub refuses that
account's merge, and only you can merge. The token alone is the default
path; this account is the strongly recommended step after it. Without it the
loop in [Run a project](run-a-project.md) still works, but the merge stays
guidance: the agent is asked not to merge, and GitHub does not stop it.

1. **Create the agent's account.** Sign out of GitHub in your browser, or
   open a private window, and sign up for a new account with a different
   email address. GitHub's terms let one person hold one free extra account
   for automation, called a machine account. Turn on two-factor
   authentication for it, as for your own.
2. **Invite it to the repository.** Signed in as yourself: the
   repository's **Settings → Collaborators → Add people**, then the agent
   account's name. Then, signed in as the agent account, open
   `https://github.com/<owner>/<name>/invitations` and accept. Do not make it
   an admin. Invite it only to the repositories it works on.
3. **Make its token.** Signed in as the agent account: **Settings →
   Developer settings → Personal access tokens → Tokens (classic) → Generate
   new token (classic)**. Tick only **`repo`**, nothing else, and choose a
   short expiry, such as 30 days. It has to be a classic token: a
   fine-grained token cannot be made for a repository the account was only
   invited to, because the owner offered is the agent account itself
   (#568 step 1). Leaving **`workflow`** unticked keeps the token from
   changing the checks, as with [the agent's token](give-the-agent-a-token.md): a push of a file under
   `.github/workflows/` was refused (#568 step 1). `repo` reaches every
   repository the agent account was invited to, which is why step 2 invites
   it only where it works.
4. **Sign the agent's session into it.** In a separate terminal window, not
   with `!` in Claude Code, run `gh auth login`: GitHub.com, HTTPS, **Yes**
   to authenticating Git, then **Paste an authentication token**, and paste
   the agent's token.
5. **Take your own login off this machine.** The agent can use any login it
   finds here, and yours can merge. Go through step 5 of [the agent's token](give-the-agent-a-token.md)
   and remove every credential for github.com that is not the agent's:
   another account in `gh` (`gh auth status` lists them; remove yours with
   `gh auth logout --hostname github.com --user <your login>`), another git
   credential helper, `~/.netrc`, `GH_TOKEN` and `GITHUB_TOKEN`, and SSH
   keys (its step 4). Then restart Claude Code.
6. **Check it.** In the new session, `gh api user --jq .login` prints the
   agent account's name, and `/plinth:floor-check` prints a line starting
   `the merge: boundary`. If it says `the merge: guidance`, the login the
   agent has is still the repository's admin, or the repository has no
   ruleset that reserves the merge (the same run shows a WARN with the
   command that adds one).

When a pull request is ready, the agent asks you, and you merge it yourself,
with the merge button on the pull request's page, signed in to GitHub as
yourself. The button looks as it does on any repository: green, with no
checkbox to bypass a rule and no warning about one, and the merge goes
through as usual (one measurement, #569). If the agent tries,
GitHub refuses (a 405 in the measurement), and
`scripts/merge-when-green.sh` stops and says that you merge, not to retry. If
the agent turns on auto-merge, the pull request stays open after its checks
pass (#568 step 1).

What it costs: you merge every pull request yourself, in the browser. Issues,
pull requests and commits show the agent account as their author. The token
expires and has to be made again, as in step 3. Everything that needs
administration, such as `/plinth:new-project` for another repository or the
admin-token commands in [Run a project](run-a-project.md), runs with your own token in a separate
terminal: `scripts/with-admin-token.sh` asks for it each time and passes it
to that one command only, so it does not stay behind as a login.

What it does not cover: a browser on this machine signed in to GitHub as you,
if the agent can drive that browser; a credential for your account stored in
a form `/plinth:floor-check` does not recognise; and anything outside
GitHub's merge. The agent still pushes branches and opens pull requests, and
the checks and your review in step 5 of [Run a project](run-a-project.md#5-check-what-the-checks-cannot) are what judge them. Measured on a
public repository owned by a personal account on GitHub Free; a private
repository, GitHub Pro and a repository an organization owns were not
measured. On GitLab the same idea is a Developer login, not built yet
(#553).

## A repository made before the merge ruleset

On a repository the door made before the merge ruleset, `/plinth:floor-check`
warns that no ruleset reserves the merge to an admin. The door now adds a
second ruleset that lets only the repository's admin merge; while the agent
works under your own account it changes nothing; with the agent's own account
it is what stops the agent's merge. Add it in a separate terminal, from a
plinth checkout, with a token that has administration:
`scripts/with-admin-token.sh scripts/create-merge-ruleset.sh <owner>/<name>`.
