"""The size caps tests/skill-size.sh holds, one `NAME = number` line each.

Python, not shell, on purpose: `ci / diff-size` lists a kept Python test
file that lost lines as a change to the checks, put to an admin, and a raised
cap here is a changed line. The same number in tests/skill-size.sh is not
listed. Raise a cap in the pull request that needs it, and say there why no
check can hold what the added text holds (CONTRIBUTING.md, "After something
goes wrong").
"""

# Each shipped skills/*/SKILL.md, as Claude Code's skill guidance recommends.
SKILL_MAX_LINES = 500
SKILL_MAX_BYTES = 20000

# AGENTS.md (CLAUDE.md is a link to it), at about the size the slimming left.
AGENTS_MAX_LINES = 110
AGENTS_MAX_BYTES = 7500
