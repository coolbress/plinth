# Turn on what a new project starts without

A project made by `/plinth:new-project` starts without the items below,
because whether each one is worth having depends on what the project
becomes (the rule is in
[Off by default](../reference/off-by-default.md#how-an-item-is-sorted)).
Each section says when it is worth turning on and how. The commands run
from the project's folder, with `gh` logged in as someone who administers
the repository where the section says so.

## Immutable releases

Turn them on when the project publishes GitHub Releases that other people
download, and you never want a release's files or its tag changed after it
is out. Once a release is published, its tag cannot move or be deleted while
the release exists, and its files cannot be changed or removed; deleting the
release frees the tag, but that tag name can never be used again in this
repository, even after the repository is deleted and made again
([GitHub's page](https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/immutable-releases)).
That is why it starts off: a release cut by mistake keeps its version
number forever.

```bash
gh api -X PUT repos/<owner>/<name>/immutable-releases    # needs repository administration
gh api repos/<owner>/<name>/immutable-releases           # reads it back
```

The `v*` tags of a `cli`, `library` or `backend` project are already kept
from moving by the tag ruleset `/plinth:new-project` raises; immutable
releases add the release's files. Whether the template's release workflow
for `data-ml`, which uploads its files with `gh release create`, publishes
cleanly with immutability on has not been measured.

## A support file

Add `SUPPORT.md` when people start asking for help in issues and you want
to tell them where help is (a discussion board, a chat, or "this project
gives no support"). GitHub links it when someone opens a new issue. It goes
in the repository's root, `.github/` or `docs/`; one in your account's
`.github` repository applies to every repository that has none.

## Sponsorship

Add `.github/FUNDING.yml` when you accept money for the project: GitHub
then shows a Sponsor button. Each line names a platform and your account on
it, for example `github: <your-login>`; the format is in
[GitHub's page](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/displaying-a-sponsor-button-in-your-repository).

## A citation file

Add `CITATION.cff` when people may cite the project in a paper or a
report, which is most likely for a `library` or a `data-ml` model. GitHub
then offers "Cite this repository" with the text ready to copy. The format
is the [Citation File Format](https://citation-file-format.github.io/); its
site has a form that writes the file for you.

## Code owners

Add `.github/CODEOWNERS` when a second person shares the repository and
some paths should be reviewed by a particular person. Each line is a path
pattern and the accounts that own it, for example `/src/ @<login>`. GitHub
then asks those people to review a pull request that touches their paths.
It asks; it does not require: the ruleset `/plinth:new-project` raises does
not require code owners' approval, and a project of one person gains
nothing from the file.

## Topics

Add topics when you want people to find the project in GitHub's search and
on topic pages: a few lowercase words for what it is and what it is built
with.

```bash
gh repo edit --add-topic python --add-topic <another>
```

## Turning the wiki off

GitHub gives every new repository a wiki. Turn it off when the project's
documents live in the repository itself (`README.md` and `docs/`), so there
is one place to read and change them and every change goes through a pull
request; a wiki page is edited outside the checks.

```bash
gh repo edit --enable-wiki=false
```
