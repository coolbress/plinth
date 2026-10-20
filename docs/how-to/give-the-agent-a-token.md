# How to give the agent a token that cannot change the checks

Do this once the first pull request of step 1 in
[Run a project](run-a-project.md#1-start) is merged.

The browser login from Getting started holds `workflow`, and so does the one
`gh auth login` asks for by default over HTTPS: an agent working with it can
push a change under `.github/workflows/`, including one that replaces
plinth's checks with jobs that do nothing and turns every check green
([what green means](../explanation/concepts.md#about-what-green-means)).
GitHub refuses a push that adds or changes a file there when the token lacks
workflow permission, for fine-grained and classic tokens alike. So once the
first pull request is merged, give the agent a token of its own without it:

1. On GitHub: **Settings → Developer settings → Personal access tokens →
   Fine-grained tokens → Generate new token**. Repository access: **Only
   select repositories**, this one. Repository permissions: **Contents**,
   **Issues** and **Pull requests** at **Read and write**. Leave
   **Workflows** and **Administration** at **No access**. If a `gh` command
   later answers 403, add the permission it needed, but never those two.
   Without Administration the token cannot edit or delete the ruleset
   either; the browser login can, because its `repo` scope includes
   administration.
2. In a separate terminal window, not with `!` in Claude Code, run
   `gh auth login`: GitHub.com, HTTPS, **Yes** to authenticating Git, then
   **Paste an authentication token**. It replaces the browser login.
3. Make sure nothing overrides it. `gh`, and the `git push` it serves, use
   `GH_TOKEN` or `GITHUB_TOKEN` before any stored login, and a running Claude
   Code keeps the environment it started with. If either is set in a shell
   startup file (`~/.zshrc`, `~/.bashrc`, `~/.zshenv`), remove it there, then
   restart Claude Code. In the new session, `gh auth status` should show a
   `github_pat_` token, stored in the keyring or gh's config file; after your
   account it should not say `(GH_TOKEN)` or `(GITHUB_TOKEN)`. Then
   `gh api repos/<owner>/<name>/actions/permissions` should answer
   `Resource not accessible by personal access token (HTTP 403)`: that read
   needs Administration, so the token has none. (`permissions.admin` on the
   repository says `true` for you either way: it is your account's role, not
   the token's.) `/plinth:new-project` asks the same when it finishes, for the
   login the agent inherits, and prints the answer.
4. Keep SSH out of the agent's reach. Over SSH the refusal does not happen: a
   deploy key with write access pushed a workflow change in the same
   measurement. In the project, `git remote -v` should show
   `https://github.com/…`, but the agent could switch the remote itself and
   use any SSH key it can read, under any file name. So check on GitHub, not
   on the machine: **Settings → SSH and GPG keys** on your account should list
   no authentication key this machine holds, and the repository's **Settings →
   Deploy keys** none with write access. (`ssh -T git@github.com` answering
   `Permission denied (publickey)` tests only the keys SSH picks by itself.)
   The token protects only pushes that go over HTTPS.
5. Leave no other credential for github.com on the machine. The first two
   pushed a workflow change past the token in a measurement with gh 2.101.0
   and git 2.55.0; the others are what gh and git document, not measured:
   - **Another account stored in `gh`.** `gh auth login` adds an account
     beside those already stored and makes it the active one; the agent can
     run `gh auth switch`. See them with `gh auth status`; remove each one
     that is not the token's with
     `gh auth logout --hostname github.com --user <login>`.
   - **Another git credential helper.** Git asks its helpers in the order
     `git config --show-origin --get-regexp 'credential.*helper'` lists them.
     One listed before gh's answers first; one listed after gh's answers when
     gh has no login, and in one run it stored the credential a push had
     just succeeded with, so it held that token afterwards. The macOS
     keychain helper is the usual one: git installed on macOS often lists it
     for every host in its system config. Delete its github.com entry (**Keychain
     Access**, search `github.com`), then keep it out with an empty
     `helper =` line before gh's, which is what `gh auth setup-git` writes:

     ```ini
     [credential "https://github.com"]
         helper =
         helper = !/opt/homebrew/bin/gh auth git-credential
     ```

   - **A `machine github.com` line in `~/.netrc`**, or an `Authorization`
     header in git's `http.extraHeader`: git over HTTPS sends either. Remove
     the line.
   - **`GH_TOKEN` or `GITHUB_TOKEN`**: `gh auth status` names it after the
     account; remove it as step 3 says. While one is set, an account stored
     in `gh` is a second credential even when it is the only one: the agent
     can unset the variable, and the stored login answers.

   `/plinth:floor-check` lists these on the machine it runs on and prints
   only whether each is there, never its value. Its rules are best effort:
   what they find is a warning, and finding nothing is a note, not a pass,
   since a credential written in a form they do not recognise is not
   reported. Go through this list yourself as well. What it could not read
   is not verified. So is a configuration hidden behind `GH_CONFIG_DIR`,
   `XDG_CONFIG_HOME`, `GIT_CONFIG` or a `GIT_CONFIG_*` variable: the agent can unset the
   variable, so give it its own token in the configuration read without one.
   It does not read SSH keys (step 4, on GitHub), a program named by
   `GIT_ASKPASS` or `core.askPass`, or a token saved anywhere else.
   The macOS keychain helper itself was not in the measurement; a credential
   store file in its place was. Every run lists SSH keys as not verified.

What it costs: the agent cannot push a change under `.github/workflows/`, so
a template update, or a fix `/plinth:floor-check` asks for in `ci.yml`, stops
at a commit. You push that branch from a separate terminal with a credential
that has the permission, the way the generator's admin-token path runs
([Getting started](../tutorials/getting-started.md#create-the-repository)).
Dependabot's updates to the pinned workflow are not affected: Dependabot
pushes with its own credential. Creating another repository with
`/plinth:new-project` needs the permission again; the generator stops, says
so and prints the fix.

One loop finished on this token without Claude Code asking for more
permission: an issue, the change, a pull request with its checks green, a
merge a person made, and a resume in a new session (one run, on a public
command-line repository, #403 record 1). Not run on it: a change that needs a
new dependency, a failing check, a review round, the agent attempting the
merge. That Contents, Issues and Pull requests are enough for every step of
[Run a project](run-a-project.md) is not verified.
