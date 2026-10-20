# How to set four things by hand that no check covers

Once the first pull request of step 1 in
[Run a project](run-a-project.md#1-start) is merged, settle four things outside the
repository. They are guidance: plinth does not check them, and it cannot,
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
2. Give every paid service the project uses a spend ceiling that stops the
   spending, not an alert that only tells you, for example a monthly limit
   on each API key. Protects against a leaked or runaway key running up a
   bill.
3. Restore once, on purpose, before it matters: roll back one merged change
   with a pull request that reverts it, and if there is a database, restore
   it from a backup yourself, in a place the agent cannot reach, into a new,
   empty database, check your data is there, then delete that database.
   Protects against finding out the way back does not work on the day you
   need it.
4. If the app has a database, put one made-up row in each table that should
   be private and try to read it from outside, with only the public key
   every visitor gets and no login, at the database's own address rather
   than the app's page; what you can read, anyone can. Protects against
   data left open to everyone.
