### Changed

- `/plinth:template-update` raises the plinth pin first and updates the
  template second (#1183). When a project's workflows call a plinth older
  than the one the target template tag was tested with, the plan stops
  (exit 1) before it writes anything, and `--apply` stops before it creates
  a worktree or branch. It names both commits, the compare link, and the
  open pull request that raises the pin (Dependabot's, or one a person
  opened), by number, to merge first. When no such pull request is open, it
  prints the change to make in one: every workflow that calls plinth moved
  to the same SHA (on GitLab, the include's ref and checksum). Once that is
  merged, the update runs with the pin the workflows call, with no pin
  choice, and the plinth `uses:` lines are not in conflict for the pin. A
  comparison that cannot be read stops the plan too. The update no longer
  mixes a template change and a plinth change in one pull request.
  `/plinth:floor-check` prints the same "raise it first" line in place of
  an update line when the pin is behind. MINOR: no check, job, workflow
  input or secret changes; the flags removed below were used only by
  plinth's own skill, which ships with this script, and the monthly
  template reminder in rendered projects runs `--print-update-command`
  without them.

### Removed

- `template-update.sh --plinth-pin live|tested` and `floor-check.py
  --print-update-command --plinth-pin tested`, with the plan's
  `With the tested pin:` and `Recommended:` lines, its second `--apply`
  line, and the pull request description's "The plinth pin: moved / kept"
  sentence (#1183). `template-update.sh --plinth-pin`, in any form, exits 2
  with a message naming the new order.
