### Changed

- `tests/skill-size.sh` counts what one invocation of each shipped skill
  reads: its `SKILL.md` and every file its body says to read before acting
  (`tests/lib/skill_reads.py`), against a per-skill cap in
  `tests/size_caps.py`, and each skill's description against a cap of its
  own. The files read are held to no issue numbers too; a link's anchor to a
  heading that starts with a digit is not counted as one (#1181).
