### Changed

- plinth releases on a weekly train: at most one release a week, with a named
  hotfix path for a published advisory, a broken install or a consumer's
  required check failing because of plinth (#1132). `scripts/make-release.sh`
  run 1 stops when origin's highest `vX.Y.Z` tag is less than 7 days old,
  naming the tag and its age, unless the why-file carries `hotfix: <reason>`,
  which the release's section and GitHub Release then say.
  [How to cut a release](https://github.com/coolbress/plinth/blob/main/docs/how-to/cut-a-release.md)
  opens with the cadence.
