---
name: new-project
description: Create a new GitHub repository with required checks already enforced. User-invoked only; creates a remote repository and deletes it if any check cannot be raised.
argument-hint: "<owner>/<name>"
disable-model-invocation: true
---

# New project

This version of plinth ships this skill as a placeholder. It creates nothing.

Tell the user, in one sentence, that `/plinth:new-project` is not implemented in
this version, and that a later version adds it (see the CHANGELOG). Then stop.

Do not run `gh repo create`, do not clone anything, do not ask for a token.
