### Added

- The getting-started tutorial says what plinth does not cover, before the
  first `/plinth:new-project` (#1148). Six short items, each linking its
  primary page and dated 2026-11-28:
  - the person's own GitHub and email accounts: two-factor authentication
    without SMS, recovery codes, phishing, authorised apps and the
    security log;
  - the agent's permission mode: auto mode is the default and not a
    boundary, and bypass mode is never used on the person's own computer;
  - MCP servers, plugins and someone else's repository;
  - checking a package name on PyPI before `uv add`, with uv's
    `exclude-newer = "7 days"` as an option;
  - Claude Code's accessibility settings;
  - the cost: the paid plan, shared limits and `/usage`, the model, usage
    credits and GitHub's free runners for public repositories.
- A section near the top, "When plinth is not the right tool", names the kind
  of tool that fits instead: an AI app builder, Replit, Streamlit Community
  Cloud. Mobile and desktop apps are outside plinth's scope.
- `tests/doc-consistency.sh` pins the key words of both sections.
