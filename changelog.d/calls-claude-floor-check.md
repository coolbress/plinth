### Added

- `/plinth:floor-check` requires `.env.example` naming `ANTHROPIC_API_KEY`
  when `.copier-answers.yml` says `calls_claude: true` (#1071), for a `cli`
  and a `dashboard` as for a `backend`, even where no line under `src/`
  reads the key.
