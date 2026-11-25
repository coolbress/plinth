"""Run scripts/floor-check.py and record what it gave (#1103).

    python3 floor-check-record.py <record dir> <checker> <checker args...>

tests/floor-check-golden.sh puts a `python3` first on PATH that sends every
`python3 <checker> ...` of tests/floor-check-cases.sh here. The checker runs
unchanged, with its stdin and stderr; its stdout is passed through after it
exits, and one JSON record is written: the arguments, the exit code, stdout,
the --verdicts file, and the ids and states the checker emitted
(FLOOR_CHECK_TRACE). A run that asked for no --verdicts file is run a second
time with one, and that file and exit code are recorded too: --verdicts also
adds the next action to stdout, so the case's own run cannot carry it.
Nothing here judges; the golden test compares.
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

record_dir, checker, *args = sys.argv[1:]
stamp = f"{time.time_ns():020d}.{os.getpid()}"
trace = Path(record_dir) / f"{stamp}.trace"
env = {**os.environ, "FLOOR_CHECK_TRACE": str(trace)}
p = subprocess.run([sys.executable, checker, *args], stdout=subprocess.PIPE, env=env, check=False)
sys.stdout.buffer.write(p.stdout)
sys.stdout.buffer.flush()

verdicts = second = None
if "--verdicts" in args[:-1]:
    v = Path(args[args.index("--verdicts") + 1])
    if not v.is_absolute():
        v = Path.cwd() / v
    verdicts = v.read_text(encoding="utf-8") if v.is_file() else "<no file>"
elif not any(a.startswith("--print-") for a in args):
    v = Path(record_dir) / f"{stamp}.verdicts"
    q = subprocess.run([sys.executable, checker, *args, "--verdicts", str(v)], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL, check=False)
    second = {"exit": q.returncode, "verdicts": v.read_text(encoding="utf-8") if v.is_file() else "<no file>"}
    v.unlink(missing_ok=True)
emitted = trace.read_text(encoding="utf-8").splitlines() if trace.is_file() else []
trace.unlink(missing_ok=True)
(Path(record_dir) / f"{stamp}.json").write_text(json.dumps({
    "args": args, "exit": p.returncode, "stdout": p.stdout.decode("utf-8", "replace"),
    "verdicts": verdicts, "second": second, "emitted": emitted,
}), encoding="utf-8")
sys.exit(p.returncode)
