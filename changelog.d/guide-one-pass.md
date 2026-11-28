### Changed

- `/plinth:guide` reads GitHub faster: the reads that wait on nothing but
  the repository's name (the open and merged pull requests, the open issues,
  the history, main's latest CI run and floor-check's pin read) run at once,
  and the token step's reach and the issue dependencies start as soon as the
  read they wait on is in. One run on a real project went from 9.0–9.4 s to
  4.3–4.8 s with the same eleven calls; what it prints does not change, and a
  failed read still says which one failed. When the pull requests or issues
  cannot be read, the reads started beside them still go out (6 calls where
  there were 2 or 3) and their answers are not used. `tests/guide-cases.sh` holds every
  run to at most 11 `gh` calls (#1180).
