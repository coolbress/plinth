# Security

## Reporting a vulnerability

**Do not open a public issue.** Use the repository's private reporting form:
**Security → Report a vulnerability** (GitHub Security Advisories). Include what you
found, how to reproduce it, and the version or commit you tested.

## Response — targets, not an SLA

| What | Target |
| --- | --- |
| Acknowledgement | within 3 business days |
| Fix for medium severity or higher | within 60 days |

These are best-effort targets. The project is maintained by one person with no
on-call rotation, and this file does not promise what cannot be operated. If your
report is urgent, say so in the report.

## Scope

This repository: the plugin, its marketplace, the reusable CI workflows, and the
scripts that create repositories and apply rulesets.

The project template is reported to `coolbress/plinth-template`. Projects
*generated* by the template are not covered here; report those to their own
maintainers.

## Supported versions

The latest release. Older releases are not patched.

## What this repository does

- Third-party marketplace entries and GitHub Actions are pinned to full commit SHAs —
  tags are mutable and a supply-chain vector. Dependabot opens weekly updates for the actions.
- Secrets are never committed.
- `main` is protected: nothing merges without green CI.
- No home-grown cryptography — standard libraries and vetted implementations only.
