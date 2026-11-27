"""Run scripts/floor-check.py and record what it gave (#1103).

    python3 floor-check-record.py <record dir> <checker> <checker args...>

tests/floor-check-golden.sh puts a `python3` first on PATH that sends every
`python3 <checker> ...` of tests/floor-check-cases.sh here. The checker runs
unchanged, with its stdin and stderr; its stdout is passed through after it
exits, and one JSON record is written: the arguments, the exit code, stdout,
the --verdicts file, and the ids and states the checker emitted
(FLOOR_CHECK_TRACE, copied to the caller's own trace when it set one). A run
that asked for no --verdicts file is run a second time with one, and that
file and exit code are recorded too: --verdicts also adds the next action to
stdout, so the case's own run cannot carry it. The same run is made once
more with --format json (#1105), its document and exit code recorded for the
golden test to validate against the schema.
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
as_json = None
if not any(a.startswith("--print-") for a in args) and "--format" not in args:
    plain = [a for i, a in enumerate(args) if a != "--verdicts" and (i == 0 or args[i - 1] != "--verdicts")]
    j = subprocess.run([sys.executable, checker, *plain, "--format", "json"], stdout=subprocess.PIPE,
                       stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL, check=False,
                       env={k: v for k, v in os.environ.items() if k != "FLOOR_CHECK_TRACE"})
    as_json = {"exit": j.returncode, "stdout": j.stdout.decode("utf-8", "replace")}
# Whether the run read a root with a .plinth-adoption.yml (#1112): the runs
# without one stay byte for byte the golden ones through every ticket that reads it.
root = Path(args[args.index("--root") + 1]) if "--root" in args[:-1] else Path.cwd()
adoption = (root / ".plinth-adoption.yml").exists()
emitted = trace.read_text(encoding="utf-8").splitlines() if trace.is_file() else []
trace.unlink(missing_ok=True)
# tests/floor-check-cases.sh reads its own trace to judge by id and state:
# the lines go there too when it set one.
if os.environ.get("FLOOR_CHECK_TRACE") and emitted:
    with open(os.environ["FLOOR_CHECK_TRACE"], "a", encoding="utf-8") as t:
        t.write("".join(f"{line}\n" for line in emitted))
(Path(record_dir) / f"{stamp}.json").write_text(json.dumps({
    "args": args, "exit": p.returncode, "stdout": p.stdout.decode("utf-8", "replace"),
    "verdicts": verdicts, "second": second, "emitted": emitted, "adoption": adoption, "json": as_json,
}), encoding="utf-8")
sys.exit(p.returncode)
