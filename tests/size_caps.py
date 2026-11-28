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

# The arsenal's SKILL.md, tighter: it loads on every call an agent makes to
# choose a tool, and what lies outside its stage table is in the files beside
# it (#1086).
ARSENAL_MAX_LINES = 250
ARSENAL_MAX_BYTES = 12000

# AGENTS.md (CLAUDE.md is a link to it), at about the size the slimming left.
AGENTS_MAX_LINES = 110
AGENTS_MAX_BYTES = 7500

# What one invocation of each shipped skill reads: its SKILL.md and every file
# its body says to read before acting (tests/lib/skill_reads.py says how they
# are found), set at the day's size and a little over (#1181). A file the
# body names to read only when asked is not counted.
READS_ARSENAL_MAX_BYTES = 12000
READS_FLOOR_CHECK_MAX_BYTES = 10500
READS_GUIDE_MAX_BYTES = 19000
READS_NEW_PROJECT_MAX_BYTES = 50500
READS_RECORDS_CHECK_MAX_BYTES = 5500
READS_TEMPLATE_UPDATE_MAX_BYTES = 26500

# Each shipped skill's description, read on every turn to choose a skill.
DESCRIPTION_ARSENAL_MAX_BYTES = 400
DESCRIPTION_FLOOR_CHECK_MAX_BYTES = 600
DESCRIPTION_GUIDE_MAX_BYTES = 550
DESCRIPTION_NEW_PROJECT_MAX_BYTES = 350
DESCRIPTION_RECORDS_CHECK_MAX_BYTES = 550
DESCRIPTION_TEMPLATE_UPDATE_MAX_BYTES = 400
