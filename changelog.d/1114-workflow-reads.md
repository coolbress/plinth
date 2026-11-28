### Added

- [`/plinth:floor-check`](https://github.com/coolbress/plinth/blob/main/skills/floor-check/SKILL.md)
  reads two more things in the workflows, as experimental WARNs that
  `ci / floor-check` does not print (`--experimental`, #1114): an AI agent
  action (Claude Code, Gemini CLI, Codex, AI inference) run on issues,
  comments or discussions, holding a write permission or a secret, with no
  author check (FC-D09); and a registry token read from the secrets in any
  workflow (FC-D10), whose fix is the registry's trusted publisher.
