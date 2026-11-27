### Changed

- `/plinth:new-project` renders plinth-template v1.52.0 instead of v1.51.0.
  A new project can be a `dashboard`, a Streamlit page of tables and charts,
  local by default or on Render (coolbress/plinth-template#360; the door's
  half is #1069). Its `AGENTS.md` keeps under Always only what a check or a
  deny rule holds, is capped at 8,192 bytes, and ends with a `## This project`
  section a template update never changes (coolbress/plinth-template#355,
  coolbress/plinth-template#361). The pull-request form's comments are short pointers to
  `CONTRIBUTING.md` (coolbress/plinth-template#357). GitHub projects get a
  `Look back` issue form, and the end-or-hand-over form saves before it
  deletes (coolbress/plinth-template#356). A `backend` image's SBOM is signed
  and pytest fails an `xfail` test that passes
  (coolbress/plinth-template#346). A new project calls plinth v2.45.0's workflows: the template's
  `plinth_sha` default moved from v2.44.0, and its GitLab checksum with it.
  An existing project gets these through `/plinth:template-update`; the
  release notes name the lines that may conflict
  (<https://github.com/coolbress/plinth-template/releases/tag/v1.52.0>).
