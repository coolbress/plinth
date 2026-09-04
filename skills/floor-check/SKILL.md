---
name: floor-check
description: Read-only check of an existing repository against the plinth floor (required checks, branch rules, secret scanning). Reports what is missing and never changes anything. Use when the user asks whether an existing repository is set up, protected, or "has the floor".
argument-hint: "[owner/name]"
disallowed-tools: Edit, Write, NotebookEdit
---

# Floor check

This version of plinth ships this skill as a placeholder. It checks nothing.

Tell the user, in one sentence, that `/plinth:floor-check` is not implemented in
this version, and that a later version adds it (see the CHANGELOG). Then stop.

Do not edit files and do not change any repository setting.
