### Changed

- After the first merge, only the agent's token stands before step 2 (#1078).
  The agent's own account and the four things by hand stay strongly
  recommended, in that order, but no longer hold the way: `/plinth:guide`
  routes a project with one merge, nothing else open and the token step done
  to step 2, and names the other two in a `then also:` line. While the token
  step is not done or not verified, the first-merge row and the `token step:`
  line name the token page first and the other two as recommended. For a
  `web` project, that `then also:` line also names what waits for the first
  deploy: the host's deploy-failure notification, an uptime monitor and an
  error tracker, one copy of the data off the host, a restore rehearsal that
  counts rows, and the bill to expect.
- `docs/how-to/set-four-things-by-hand.md`, read 2026-11-26: step 2 gives each
  provider's spend limit with its link (Anthropic, OpenAI, Railway, Fly.io,
  Render, GitHub Actions, the agent's subscription) and says to set each
  below what you can afford to lose; step 3's restore counts one table's rows
  before and after; "After the first deploy" starts with Render's own
  deploy-failure notification, names Better Stack beside UptimeRobot, and
  adds a copy of the data off the host and the bill to expect on Render.
  `docs/how-to/run-a-project.md` step 1 and the token and account pages say
  the same order.
