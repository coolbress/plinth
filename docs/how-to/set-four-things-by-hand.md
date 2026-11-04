# How to set four things by hand that no check covers

Before this page: [the agent's token](give-the-agent-a-token.md) and
[its own account](give-the-agent-its-own-account.md). After it: step 2 of
[Run a project](run-a-project.md).

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
   against a leaked or runaway key running up a bill. What these services
   offered, read 2026-11-04:
   - The Anthropic API stops: a monthly spend limit on the organisation's
     Billing page, and one on each workspace but the default one; once it is
     reached, requests fail until the month ends or the limit is raised
     ([spend limits](https://platform.claude.com/docs/en/api/rate-limits#spend-limits)).
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
     - Check the Billing page yourself after the first month.
3. Restore once, on purpose, before it matters: roll back one merged change.
   On the merged pull request's page press **Revert**, or run
   `gh pr revert <n>` (gh 2.83.0 or newer); either opens a new pull request
   that undoes the change, which goes through the checks and the merge like
   any other. If there is a database, restore
   it from a backup yourself, in a place the agent cannot reach, into a new,
   empty database, check your data is there, then delete that database.
   Protects against finding out the way back does not work on the day you
   need it.
4. If the app has a database, put one made-up row in each table that should
   be private and try to read it from outside, with only the public key
   every visitor gets and no login, at the database's own address rather
   than the app's page; what you can read, anyone can. Protects against
   data left open to everyone.

## After the first deploy

Two more, once the app has an address. Neither goes in the repository, and
no check reads them either. The free plans are as read 2026-11-04.

1. An uptime monitor on the app's `/healthz` address, which tells you when
   it stops answering. For example UptimeRobot's free plan: 50 monitors,
   checked every 5 minutes, commercial use allowed
   ([pricing](https://uptimerobot.com/pricing/)). It needs no key in the
   app: the monitor and its alerts live in your UptimeRobot account.
2. An error tracker, which tells you when the app fails for someone. For
   example Sentry's Developer plan: free, one user, 5,000 errors
   ([pricing](https://sentry.io/pricing/)). Adding its SDK is a change to the
   app, made in a pull request like any other. Its key, the DSN, goes in the
   host's dashboard as the `SENTRY_DSN` environment variable (on Render, the
   service's Environment settings), never in the repository; the Python SDK
   reads `SENTRY_DSN` by itself when the code passes no DSN
   ([options](https://docs.sentry.io/platforms/python/configuration/options/)).
