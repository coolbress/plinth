### Added

- [`/plinth:floor-check`](https://github.com/coolbress/plinth/blob/main/skills/floor-check/reference.md#dependabot-alerts-secret-scanning-and-registry-tokens)
  reads whether Dependabot alerts, Dependabot security updates and secret
  scanning are on, with the user's login. Open Dependabot alerts are counted
  by severity. Open secret scanning alerts are named by type and where, never
  by value. On a private repository without GitHub Secret Protection, secret
  scanning says the plan, not "off". When `release.yml` publishes through
  OIDC, a secret named like a registry token is a WARN (experimental, names
  only). In `ci / floor-check` these reads are left to the skill, and its
  FAIL and SKIP counts do not change (#1118).
