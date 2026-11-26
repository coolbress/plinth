# How to set four things by hand that no check covers

Before this page: [the agent's token](give-the-agent-a-token.md), the one
step that comes before step 2 of [Run a project](run-a-project.md). This page
and [its own account](give-the-agent-its-own-account.md) are strongly
recommended next; neither blocks step 2. The part [after the first
deploy](#after-the-first-deploy) waits until the app has an address.

Settle four things outside the repository. They are guidance: plinth does not check them, and it cannot,
because every check the host requires reads a pull request or the
repository's settings, and these live somewhere else
([what plinth does not do](../explanation/concepts.md#about-what-plinth-does-not-do)).
[The agent's token](give-the-agent-a-token.md) limits what the agent can do on GitHub; these are meant to
limit what it, or anyone, can do elsewhere. Each is the safeguard whose
absence a reported incident turned on; what writing them down changes has
not been measured.

1. Keep production credentials and the production database out of the
   agent's session: give the agent a development database filled with
   made-up or scrubbed data, not a copy of production's. Protects against
   an agent deleting live data or reading real people's records.
2. For every paid service the project uses, set a limit that stops the
   spending where the service has one, and know where it has none. Protects
   against a leaked or runaway key running up a bill. Set each limit below
   what you can afford to lose: several are checked every few minutes, not
   at each request, so spending can go past them before they stop it. What
   these services offered, read 2026-11-04, and on 2026-11-26 where dated:
   - The Anthropic API stops: a monthly spend limit for the organisation, on
     its Billing page; once it is reached, requests fail until the month ends
     or the limit is raised. Set the organisation's: a limit on the default
     workspace might not count or stop some usage in it (2026-11-26,
     [spend limits](https://platform.claude.com/docs/en/api/rate-limits#spend-limits)).
   - The OpenAI API: a project's spend limit only watches, unless **Enforce a
     hard limit** is on; then requests fail once the tracked spending reaches
     it, a little past it at times (2026-11-26,
     [projects](https://help.openai.com/en/articles/9186755-managing-your-work-in-the-api-platform-with-projects)).
   - Railway: at the hard limit you set, every workload is taken offline
     until you raise or remove it (2026-11-26,
     [usage limits](https://docs.railway.com/reference/usage-limits)).
   - Fly.io: on Pay As You Go there is no cap, and it sends no billing
     alerts; choose a fixed plan size and read the bill after the first
     month (2026-11-26,
     [cost management](https://docs.fly.io/about/cost-management)).
   - GitHub Actions, once a payment method is added: a budget with stopping
     usage turned on stops Actions at the amount; it counts only usage from
     the day it is created, and the first cycle can still go past it
     (2026-11-26,
     [budgets](https://docs.github.com/en/billing/concepts/budgets-and-alerts)).
   - The agent's own subscription: a session limit that resets every five
     hours and a weekly limit. Past them, usage credits bill at API rates,
     and turning them on is your choice; if you do, set a monthly spending
     cap, not "unlimited" (2026-11-26,
     [usage credits](https://support.claude.com/en/articles/12429409-extra-usage-for-paid-claude-plans)).
     In Claude Code, `/usage` shows where you are against both limits.
   - Google Cloud: an alerts-only budget only tells you and does not cap
     usage; a spend cap budget, where Google offers one, pauses the services
     until you lift it
     ([budgets](https://docs.cloud.google.com/billing/docs/how-to/budgets)).
   - Render's docs describe no limit that stops spending on the whole
     account, and an account-level spending limit is a request on its
     feedback board
     ([account spending limits](https://feedback.render.com/features/p/account-spending-limits)).
     - Its one documented spend limit is on build pipeline minutes; reaching
       it stops builds for the rest of the month
       ([build pipeline](https://render.com/docs/build-pipeline)).
     - Outbound bandwidth past the included amount is billed per GB, and the
       page describes no limit to set
       ([outbound bandwidth](https://render.com/docs/outbound-bandwidth)).
     - The nearest controls: the plans' fixed monthly prices, which the
       template's `render.yaml` sets; `diskSizeGB: 1` there, the disk size
       the database price includes; and storage autoscaling, off for a new
       database when `storageAutoscalingEnabled` is left out, as the
       template leaves it
       ([Blueprint spec](https://render.com/docs/blueprint-spec)).
     - So: the fixed plans, and the Billing page read yourself after the
       first month.
3. Restore once, on purpose, before it matters: roll back one merged change.
   On the merged pull request's page press **Revert**, or run
   `gh pr revert <n>` (gh 2.83.0 or newer); either opens a new pull request
   that undoes the change, which goes through the checks and the merge like
   any other. If there is a database, count the rows of one table you care
   about, then restore it from a backup yourself, in a place the agent cannot
   reach, into a new, empty database; count that table's rows there: the
   same number says your data came back, a different one that it did not.
   Then delete that database.
   Protects against finding out the way back does not work on the day you
   need it.
4. If the app has a database, put one made-up row in each table that should
   be private and try to read it from outside, with only the public key
   every visitor gets and no login, at the database's own address rather
   than the app's page; what you can read, anyone can. Protects against
   data left open to everyone.

## After the first deploy

Once the app has an address. None of these goes in the repository, and no
check reads them either. Read 2026-11-26 unless dated otherwise.

1. Your host's own deploy-failure notification, which tells you when a
   change did not go out. On Render it needs no other account: notifications
   go by email, or to Slack once you connect it; you set a default for every
   service in the workspace, choosing failure notifications only or all of
   them, and a service's own setting overrides it. Render's page does not
   say which is on by default, so look
   ([notifications](https://render.com/docs/notifications)).
2. An uptime monitor on the app's `/healthz` address, which tells you when
   it stops answering. For example UptimeRobot's free plan: 50 monitors,
   checked every 5 minutes, commercial use allowed
   ([pricing](https://uptimerobot.com/pricing/)); or Better Stack's: 10
   monitors and heartbeats and one status page; its page does not give the
   free plan's check interval
   ([pricing](https://betterstack.com/pricing)). It needs no key in the
   app: the monitor and its alerts live in that service's account.
3. An error tracker, which tells you when the app fails for someone. For
   example Sentry's Developer plan: free, one user, 5,000 errors
   ([pricing](https://sentry.io/pricing/)). Adding its SDK is a change to the
   app, made in a pull request like any other. Its key, the DSN, goes in the
   host's dashboard as the `SENTRY_DSN` environment variable (on Render, the
   service's Environment settings), never in the repository; the Python SDK
   reads `SENTRY_DSN` by itself when the code passes no DSN
   ([options](https://docs.sentry.io/platforms/python/configuration/options/)).
   Sentry's plan as read 2026-11-04.
4. One copy of the data kept off the host, in a place the agent cannot
   reach, at least weekly. On Render's Hobby workspace a database can be
   restored to any point in the past 3 days only, and the logical backups
   you export from its dashboard are kept 7 days, in the same region as the
   database; so download one, or run `pg_dump` against the database's
   external address, and keep the file somewhere else
   ([backups](https://render.com/docs/postgresql-backups)). Restore from it
   once, as step 3 above says, with the row count.
5. The bill to expect, and when to read it. The template's plans on Render:
   a US$7 a month web service and a US$6 a month Postgres; the Hobby
   workspace includes 5 GB of bandwidth a month, then US$0.15 a GB
   ([pricing](https://render.com/pricing)). The template avoids the free
   instances: a free web service spins down after 15 minutes without
   traffic, and a free Postgres expires 30 days after it is made and has no
   backups at all ([free instances](https://render.com/docs/free)). A domain
   is optional: the `onrender.com` address already serves HTTPS. Read the
   Billing page after the first month. If the agent's subscription runs out
   while you work, its usage credits bill at API rates: set a monthly limit
   before you turn them on (step 2 above).
