### Changed

- When a release owes both the eval suite and the smoke run, one
  `scripts/eval-suite.sh --release` on the release branch serves both (#1134).
  The run starts with the smoke run's six rows and prints their verdict, the
  line `--smoke` prints, before any other run starts. Its exit is the smoke
  run's for those rows. The why says `eval suite: on the release candidate`,
  and the run's link goes in the release pull request's description;
  `scripts/make-release.sh` run 2 reads it there, refuses without it, and puts
  it in the GitHub Release. `--smoke` alone stays for releases that owe only
  the smoke run.
