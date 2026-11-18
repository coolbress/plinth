"""The command's entry point: `python -m <package>`.

`main()` reads the command line with argparse: `--help`, `--version` and one
optional name. Replace the arguments and the body with what the command does;
the logging setup can stay. `tests/test_entry_point.py` runs this module and
compares what it logs with `tests/entry_point.expected`: change them with it.

What the command produces goes to stdout, where a pipe or a file takes it; logs
are one JSON object per line on stderr, so they never mix into that output
(clig.dev). Standard library only. Metrics, traces and SLOs live outside
the repository, in whatever the deployment uses.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from importlib.metadata import version
from typing import Any

from . import greet

# The fields every LogRecord carries. Anything else came in through
# `logger.info("...", extra={...})` and is kept: context in fields is the
# point of structured logs.
_RESERVED = set(logging.LogRecord("", 0, "", 0, "", None, None).__dict__) | {"message", "asctime"}


class JsonFormatter(logging.Formatter):
    """One JSON object per line."""

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "time": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        payload.update({k: v for k, v in record.__dict__.items() if k not in _RESERVED})
        return json.dumps(payload, ensure_ascii=False, default=str)


def configure(level: int = logging.INFO) -> None:
    """Point the root logger at stderr in JSON. Safe to call more than once."""
    handler = logging.StreamHandler(sys.stderr)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(level)


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(prog="probe", description="Greet someone.")
    parser.add_argument("--version", action="version", version=f"%(prog)s {version('probe')}")
    parser.add_argument("name", nargs="?", default="world", help="who to greet (default: world)")
    args = parser.parse_args(argv)
    configure()
    greeting = greet(args.name)
    logging.getLogger(__package__).info("started", extra={"greeting": greeting})
    print(greeting)


if __name__ == "__main__":
    main()
