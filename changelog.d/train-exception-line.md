### Added

- `scripts/make-release.sh` releases early without the hotfix path when the
  why-file names the comment that records the owner's decision:
  `train exception: <https://github.com/<owner>/<repo>/issues/<n>#issuecomment-<id>>`.
  Run 1 reads the comment with `gh` and stops when it cannot; the line stays
  in the release's section and its GitHub Release, and a why with a
  `hotfix:` line too stops (#1132).
