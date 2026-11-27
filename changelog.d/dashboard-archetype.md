### Added

- `/plinth:new-project` knows the `dashboard` archetype, a Streamlit page of
  tables and charts with no login and no database (#1069). A description
  about charts or seeing data recommends it; its prerequisites are said; and
  where it runs is asked: on the person's computer (`--hosting=local`, the
  default) or on Render (`--hosting=render`, about US $7 a month, GitHub
  only), where anyone with the page's address can read it. It gets no tag
  ruleset, since it releases nothing. On GitLab it runs locally only: the
  GitLab door refuses `--hosting=render`. The door accepts the archetype once
  plinth's template pin reaches the plinth-template release that adds it;
  until then it stops with "unknown archetype: dashboard", as before.
- `/plinth:floor-check` asks a dashboard whose answers say `hosting: render`
  for `render.yaml`, leaves it out of the tag-ruleset item, and
  `--move-archetype` refuses a move to or from `dashboard`, as from `web`.
  `/plinth:guide` says where a dashboard runs and gives it no release signal.
