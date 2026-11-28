### Changed

- `scripts/merge-when-green.sh` reads what is already visible before
  `--update` and before it waits on the checks (#1264). These stop it with no
  merge commit made on the branch and no CI run waited for: an inline comment
  with no reply, a check that finished on the head and is not green, or a
  merge conflict with the base. A read that fails stops nothing, as before.
  The checks wait now has a bound. A job that GitHub leaves in progress after
  its run has completed stops the wait within five minutes, and the stop
  names the job with its `gh run rerun <run> --job <job>` line. A check still
  pending after two hours is reported as not green. Nothing is re-run by the
  script. Every stop still exits 1.
