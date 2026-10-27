# How to choose where a web app runs

A `web` project from `/plinth:new-project` is a Django app with a Postgres
database. To let other people use it, it has to run on a computer that is
always on and that the internet can reach. This page lists the places it can
run, from the least work for you to the most, and says for each one what it
gives you, what becomes your job, about what it costs, and how to turn it off.

plinth builds and checks one of them: Render. The others are **listed, not
checked by plinth**: plinth does not deploy there, and nobody working on plinth
has tried the steps below on them. They come from each provider's own pages,
read on 2026-10-27 without signing up or deploying anything
(plinth's issue [#639](https://github.com/coolbress/plinth/issues/639) has the
research).

Prices are in US dollars unless marked, before tax, and as read on the date
given; providers change them, so check the linked page before you pay. "Not
confirmed" means the provider's own page did not say it, or only a
second-hand source did.

## The choices at a glance

| Choice | About a month (read 2026-10-27) | Checked by plinth |
| --- | --- | --- |
| [Render](#render-recommended) | $13 | Yes, recommended |
| [Railway](#railway) | $10, an estimate | Listed, not checked by plinth |
| [DigitalOcean App Platform](#digitalocean-app-platform) | $20 | Listed, not checked by plinth |
| [Fly.io](#flyio) | $42 | Listed, not checked by plinth |
| [A rented server](#a-rented-server) | €6, plus a domain name | Listed, not checked by plinth |
| [A computer at home](#a-computer-at-home) | The computer and its electricity | Listed, not checked by plinth |

What every choice needs from the app is the same: the `Dockerfile`, the
`/healthz` page, and four settings in the place's environment
(`DJANGO_SETTINGS_MODULE`, `DJANGO_SECRET_KEY`, `DJANGO_ALLOWED_HOSTS`,
`DATABASE_URL`). Only Render also reads `render.yaml`. Before each new
version, the step `python -m <package>.predeploy` waits for the database and
applies the migrations once; a migration that fails should stop the new
version, so the old one keeps serving.

On any choice, five things decide whether you can trust it. On Render, plinth checked
them in [#607](https://github.com/coolbress/plinth/issues/607); on the
others, check each one yourself:

1. **HTTPS**: the address starts with `https://`, and its certificate renews
   by itself.
2. **A new version only after the checks pass**: a pull request that fails
   its checks never reaches the people using the app.
3. **Backups, and a restore you have tried**: you have brought the data back
   once, into a new database, before you need to.
4. **Secrets kept out of the repository**: the secret key and the database
   password live in the place's own settings, never in a file you commit.
5. **Updates, and turning it off**: who keeps the system up to date, and what
   you delete to stop paying.

## Render (recommended)

plinth builds and checks this one. The template's `render.yaml` describes the
app and its database, and every step below was run and then removed in
[#607](https://github.com/coolbress/plinth/issues/607).

**What it costs.** About $13 a month: a $0 Hobby workspace, a $7 web service
(0.5 CPU, 512 MB) and a $6 Postgres (256 MB) with 1 GB of disk included, then
$0.30 a GB ([Render pricing](https://render.com/pricing), read 2026-10-27).
The free web service sleeps after 15 minutes without visitors, and the free
Postgres expires after 30 days and has no backups
([free instances](https://render.com/docs/free), read 2026-10-27), so the
template uses neither.

**What it gives you.**

- HTTPS on the `onrender.com` address.
- A new version only after the checks pass: Render's "After CI Checks Pass"
  does not deploy a commit whose check failed or that ran none
  ([deploys](https://render.com/docs/deploys), read 2026-10-27).
- The migrations before each version, through the step above.
- Point-in-time recovery: a new database as yours was at a moment in the past
  3 days on Hobby, 7 on Pro or higher, never the last 10 minutes
  ([Postgres backups](https://render.com/docs/postgresql-backups), read
  2026-10-27).
- The secret key made by Render and kept in its settings; the database is
  reachable only from Render's private network.

**What you take on.** Setting the address in `DJANGO_ALLOWED_HOSTS`, trying a
restore once (step 3 of [four things by hand](set-four-things-by-hand.md)),
and the bill. Keeping the machine and Postgres running is Render's job.

**Steps.** The rendered `README.md` has them; in short:

1. In Render's dashboard, choose New > Blueprint and pick this repository.
2. Type the address you expect in `DJANGO_ALLOWED_HOSTS` when it asks.
3. In the Blueprint's Settings, set Auto Sync to No, so a change to
   `render.yaml` waits for the checks like any other.
4. Merge a pull request and watch the new version go out after its checks.

**Turning it off.** Delete the web service, the database and the Blueprint in
the dashboard (done and checked in #607).

## Railway

Listed, not checked by plinth: plinth does not deploy here, and nobody has
tried these steps for plinth. A trial is planned in
[#680](https://github.com/coolbress/plinth/issues/680).

**What it costs.** About $10 a month, an estimate from the rates, not
measured. The Hobby plan is $5 a month and includes $5 of use; beyond that,
memory is $10 a GB, CPU $20 a vCPU, disk $0.15 a GB and traffic $0.05 a GB, each
a month ([plans](https://docs.railway.com/reference/pricing/plans), read
2026-10-27). The Free plan gives $1 of credit a month, and a trial's disks are
deleted 30 days after its credit ends
([free trial](https://docs.railway.com/reference/pricing/free-trial), read
2026-10-27).

**Compared with Render.**

- HTTPS: yes, on the `railway.app` address, with certificates "automatically
  provisioned and renewed"
  ([public networking](https://docs.railway.com/guides/public-networking),
  read 2026-10-27).
- A new version only after the checks: yes, with "Wait for CI". It waits for
  GitHub Actions only, and needs a workflow that runs on a push to the branch;
  the template's CI has one
  ([GitHub autodeploys](https://docs.railway.com/guides/github-autodeploys),
  read 2026-10-27).
- Backups: **off until you turn them on.** Then daily copies kept 6 days,
  weekly kept 27, monthly kept 89
  ([backups](https://docs.railway.com/reference/backups), read 2026-10-27).
  Point-in-time recovery is a separate switch: about 4 weeks back, counted
  only from when you switched it on, restored into a new service
  ([point-in-time recovery](https://docs.railway.com/volumes/point-in-time-recovery),
  read 2026-10-27). Which plans get these: not confirmed.
- Railway's file for describing an app in the repository is "deprecated" and
  works for existing services until 2026-12-01; what replaces it was not read
  ([config as code](https://docs.railway.com/reference/config-as-code), read
  2026-10-27). The steps below use the dashboard instead.

**Steps**, from Railway's pages linked above:

1. Make a project from this GitHub repository; Railway builds the
   `Dockerfile`.
2. Add a Postgres to the project
   ([PostgreSQL](https://docs.railway.com/guides/postgresql), read
   2026-10-27), and turn on its backups and, if you want it, point-in-time
   recovery.
3. In the app's variables, set `DJANGO_SETTINGS_MODULE`, a long random
   `DJANGO_SECRET_KEY`, `DJANGO_ALLOWED_HOSTS` (the `railway.app` address, or
   your own domain) and `DATABASE_URL` (the Postgres's connection address).
4. Set the pre-deploy command to `python -m <package>.predeploy`; if it fails,
   the new version does not go out
   ([pre-deploy command](https://docs.railway.com/guides/pre-deploy-command),
   read 2026-10-27).
5. Turn on "Wait for CI" for the branch `main`.
6. Make a public address for the app, then merge a pull request and check
   that the new version went out only after its checks.

**What you take on.** Turning backups on and trying a restore; the secret key
you make and keep in Railway's variables; checking that "Wait for CI" stays
on; moving to Railway's new configuration method when it changes. Keeping
the machine running is Railway's job. Its Postgres is a template service
that "Railway maintains"; how it is updated was not read.

**Turning it off.** Delete the project. Railway's page on deleting was not
read: check the bill afterwards.

## DigitalOcean App Platform

Listed, not checked by plinth: plinth does not deploy here, and nobody has
tried these steps for plinth.

**What it costs.** About $20 a month: a $5 container with 512 MB
([App Platform pricing](https://docs.digitalocean.com/products/app-platform/details/pricing/),
read 2026-10-27) and a managed Postgres from $15.15
([managed database pricing](https://www.digitalocean.com/pricing/managed-databases),
read 2026-10-27). A $7 "development database" exists; whether it has backups
is not confirmed.

**Compared with Render.**

- HTTPS: not confirmed (the page was not read).
- A new version only after the checks: **no such option documented.** A new
  version goes out on every push to the branch, or never on its own
  (`deploy_on_push`,
  [app spec](https://docs.digitalocean.com/products/app-platform/reference/app-spec/),
  read 2026-10-27). Waiting for the checks would need a deploy job in CI that
  holds a DigitalOcean token as a repository secret: a new key you make,
  keep and replace.
- Backups: the managed Postgres keeps a daily copy for 7 days and restores
  "to the latest transaction" or "a point in time" into a new database
  ([PostgreSQL restore](https://docs.digitalocean.com/products/databases/postgresql/how-to/restore-from-backups/),
  read 2026-10-27).

**Steps**, from DigitalOcean's pages linked above:

1. Make a managed Postgres.
2. Make an app from this GitHub repository; it builds the `Dockerfile`.
3. In the app's environment, set the four settings: `DATABASE_URL` from the
   managed Postgres, a long random `DJANGO_SECRET_KEY`, and the app's address
   in `DJANGO_ALLOWED_HOSTS`.
4. Add a job of kind `PRE_DEPLOY` that runs `python -m <package>.predeploy`.
5. Choose how new versions go out: on every push (they do not wait for the
   checks), or from a deploy job in CI with a token.

**What you take on.** Either a new version that does not wait for the
checks, or a token in the repository's secrets that you rotate; trying a
restore; the secret key. Keeping the machine and Postgres running is
DigitalOcean's job.

**Turning it off.** Delete the app and the database. DigitalOcean's page on
deleting was not read: check the bill afterwards.

## Fly.io

Listed, not checked by plinth: plinth does not deploy here, and nobody has
tried these steps for plinth.

**What it costs.** About $42 a month. New organisations get no free allowance;
a 512 MB machine is $3.69 a month, and Managed Postgres starts at $38 a month
([pricing](https://docs.fly.io/about/pricing), read 2026-10-27). A Postgres
you run yourself on a Fly disk costs less, but its backups are daily disk
copies kept 5 days, and keeping it running is your job.

**Compared with Render.**

- HTTPS: not confirmed for the `fly.dev` address; a `force_https` setting
  exists
  ([configuration reference](https://docs.fly.io/reference/configuration),
  read 2026-10-27).
- A new version only after the checks: only through a deploy job in GitHub
  Actions that holds a Fly deploy token as a repository secret. Not
  confirmed: this comes from a search summary of Fly's
  [integrating flyctl](https://docs.fly.io/flyctl/integrating) page, and its
  continuous-deployment guide did not load when read on 2026-10-27.
- Backups: Managed Postgres "includes … backups"
  ([Managed Postgres](https://docs.fly.io/mpg/), read 2026-10-27); how far
  back a restore goes is not stated.

**Steps**, from Fly's pages linked above:

1. Make a Managed Postgres.
2. Make an app from this repository's `Dockerfile`, with `force_https` on.
3. Set the four settings as Fly secrets, `DATABASE_URL` from the Postgres.
4. Set `release_command` to `python -m <package>.predeploy`; if it exits with
   an error, the new version does not go out.
5. Add a deploy job to CI that runs after the checks, with a Fly deploy token
   as a repository secret.

**What you take on.** The deploy token: you make it, keep it secret and
replace it; the deploy job; finding out how far back a restore goes, and
trying one; the secret key. Keeping the machine running is Fly's job.

**Turning it off.** Delete the app and the Postgres. Fly's page on deleting
was not read: check the bill afterwards.

## A rented server

Listed, not checked by plinth: plinth does not deploy here, and nobody has
tried these steps for plinth. Read
[putting a computer on the internet](#putting-a-computer-on-the-internet)
first.

A rented server (a VPS) is a computer in a data centre that is yours to run.
More power for less money, but everything a hosting service does becomes your
job, every month.

**What it costs.** From about €6 a month: Hetzner's CX23 (2 CPUs, 4 GB, 40 GB
of disk, 20 TB of traffic in the EU) is €5.99 excluding VAT, and its backups
start at €1.20, marked "not available" when read
([cost-optimized servers](https://www.hetzner.com/cloud/cost-optimized/), read
2026-10-27). DigitalOcean's smallest server is $4 with 512 MB
([Droplet pricing](https://www.digitalocean.com/pricing/droplets), read
2026-10-27): too little, in #639's judgement, for the app and Postgres
together. A domain name is extra; its price was not read.

**Compared with Render.** Nothing comes with it:

- HTTPS: you set it up. Caddy, for example, gets and renews certificates once
  your domain points at the server and ports 80 and 443 are open
  ([Caddy automatic HTTPS](https://caddyserver.com/docs/automatic-https),
  read 2026-10-27).
- A new version only after the checks: only if you build it: a deploy job in
  CI holding an SSH key, or the server pulling a version whose checks passed.
- Backups: yours. PostgreSQL's three ways are a database dump, a copy of its
  files, or continuous archiving
  ([backup and restore](https://www.postgresql.org/docs/current/backup.html),
  read 2026-10-27). Hetzner keeps 7 daily copies of the whole disk
  ([backups and snapshots](https://docs.hetzner.com/cloud/servers/backups-snapshots/overview/),
  read 2026-10-27); whether such a copy of a running database can be restored
  is not stated. Nothing brings your data back unless you set up backups and
  try a restore yourself.
- When the server stops, the site is down until you notice and fix it.

**Steps.**

1. Rent the server and point your domain name at it.
2. Install Docker, then run Postgres and the app's image on the server, with
   the four settings in a file only the server can read.
3. Put a proxy in front of the app, Caddy for example, for HTTPS. Open only
   ports 80 and 443 to the internet.
4. Run `python -m <package>.predeploy` before starting each new version.
5. Set up a database dump every day, copied to somewhere other than this
   server, and restore one into a new database once to see that it works.

**Never open these ports to the internet:**

- **The app's own port (8000 by default).** The app trusts the
  `X-Forwarded-Proto` header to tell it a visitor came over HTTPS. A proxy
  such as Caddy sets that header itself; without one, anyone can send it and
  make a plain, unencrypted connection look secure to the app. Only the proxy
  should reach the app.
- **The database's port (5432 for Postgres), ever.** Anyone on the internet
  could then try passwords against your data, all day, without going through
  the app. Only the app, on the same server, should reach it.

**What you take on.** HTTPS; deploys and waiting for the checks; backups, a
copy kept elsewhere, and a restore you have tried; the secrets in a file on
the server; updates to the system, Docker, Postgres and the app; a firewall;
noticing when it is down.

**Turning it off.** Delete the server; its data goes with it, so keep a dump
first if you want the data.

## A computer at home

Listed, not checked by plinth: plinth does not deploy here, and nobody has
tried these steps for plinth. Read
[putting a computer on the internet](#putting-a-computer-on-the-internet)
first.

**What it costs.** The computer and its electricity. Publishing it may add a
domain name: a named Cloudflare Tunnel needs a domain added to Cloudflare
([publishing an application](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/get-started/create-remote-tunnel/),
read 2026-10-27), and Cloudflare's price for a tunnel is not confirmed.
Tailscale Funnel is "available for all plans"
([Tailscale Funnel](https://tailscale.com/kb/1223/funnel), read 2026-10-27).

There are two ways to use it.

**Only on your own network.** Free to try, and the safest home choice. The
app as made turns on HTTPS-only outside development, so run it in development
mode (`DJANGO_DEBUG=1`, as the rendered `README.md` shows) or behind a proxy
on the same computer. It is off whenever the computer is.

**Published on the internet**, through a tunnel or a port opened on your
router. This is the riskiest choice.

- A tunnel is safer than an opened port: the computer calls out, so nothing
  on your router has to be opened, and Cloudflare's documentation says
  incoming traffic can then be blocked entirely
  ([Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/),
  read 2026-10-27). The app itself is still public.
- Cloudflare's Quick Tunnels, which need no account, are "for testing and
  development", have "no uptime guarantee", get a new address each time, and
  take 200 requests at once
  ([Quick Tunnels](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/),
  read 2026-10-27).
- Tailscale Funnel is "currently in beta", serves only addresses ending in
  your `ts.net` name, on ports 443, 8443 and 10000, with traffic limits you
  cannot change (read 2026-10-27).
- Both tunnels give the address HTTPS. An opened port needs your own proxy
  and certificates, as on [a rented server](#a-rented-server), and the same
  two ports never opened: the app's own port without a proxy in front, and
  the database's port.

**Steps.** As on [a rented server](#a-rented-server), steps 2 to 5, on your
own computer; then either start a tunnel to the proxy's address, or open only
ports 80 and 443 on your router to that computer.

**What you take on.** Everything a rented server needs, and also: the site
is down whenever the computer sleeps, restarts or the home connection drops;
a flaw in the app is a way into your home network; and a backup on the same
disk is lost with that disk.

**Turning it off.** Stop the tunnel, or close the port on the router, then
stop the app.

## Putting a computer on the internet

What it means to put your own server or home computer on the internet, in
plain words:

- Once it is public, anyone on the internet can reach it, not only the people
  you send the link to. Programs scan the internet all the time for open
  machines and known login pages; they do not need to know you exist.
- Opening a port on your home router points the internet at that computer.
  If the app, or anything else on that computer, has a flaw, it is a way into
  your home network: your other computers, phones and cameras sit behind the
  same router.
- A tunnel avoids opening a port, but the app is still public, and its flaws
  can be reached the same way.
- Updates become yours: the operating system, Docker, Postgres and the app. A
  machine you forget about keeps running old software with known holes.
- Secrets sit in a file on that machine. A lost or stolen laptop, or a copy
  of its disk, carries the secret key and the database password.
- A backup on the same disk dies with that disk. Keep a copy somewhere else,
  and try a restore before you need one.
- Never open the database's port, or the app's own port without a proxy in
  front: the app trusts the `X-Forwarded-Proto` header, which is safe only
  when a proxy sets it.

## Changing your mind later

The app is the same everywhere, so moving means setting the four settings in
the new place and moving the data by hand: a `pg_dump` from the old database,
a `pg_restore` into the new one. Nobody has tried a move for plinth. Delete
the old place only after the new one shows your data.
