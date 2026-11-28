### Fixed

- The [decisions page](https://github.com/coolbress/plinth/blob/main/docs/reference/decisions-in-force.md)
  no longer marks as "not built yet" eight decisions whose work has landed,
  and its release line says what `/plinth:guide` counts: a `feat:` or `fix:`
  by a person since the last tag, not for web or dashboard (#1221).
  `scripts/make-release.sh` now stops on a marker whose issue is closed as
  completed, and names one closed another way for a person.
