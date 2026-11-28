### Added

- `/plinth:new-project` takes `--calls-claude` for a `cli`, `dashboard` or
  `backend` on GitHub (#1071): the project gets the Anthropic SDK, the one
  module that calls Claude, tests that use a fake Claude and need no key, and
  README steps for the key and its spend limits. A description about a
  chatbot, an assistant or AI answers recommends the kind its interface fits
  with it on, and the prerequisites line says the key comes later, with a
  spend limit, never typed into the chat. The GitLab door refuses
  `--calls-claude` before anything is read. The door passes the answer once
  plinth's template pin reaches the plinth-template release that asks it;
  until then `--calls-claude` stops before anything is created, saying the
  template does not ask it.
