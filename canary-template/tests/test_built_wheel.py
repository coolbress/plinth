"""The command as a person gets it: built into a wheel, installed, run from PATH.

`tests/test_entry_point.py` runs `python -m probe` from the
source tree. A command `pyproject.toml` does not declare, or one pointing at a
name the wheel leaves out, passes there and fails here. The wheel is built with
`uv build` (its build backend is fetched the first time, as the `uv build`
check does), installed into a new, empty environment with `uv pip install`,
and the command `probe` is found on PATH and run.

When you rename the command or change how the package is built, change this
test with it.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

#: The command `[project.scripts]` in pyproject.toml declares.
COMMAND = "probe"


def run(
    *args: str, cwd: Path, env: dict[str, str] | None = None
) -> subprocess.CompletedProcess[str]:
    done = subprocess.run(  # noqa: S603
        list(args), capture_output=True, text=True, check=False, cwd=cwd, env=env, timeout=120
    )
    assert done.returncode == 0, f"{args[:3]}: exit {done.returncode}\n{done.stdout}\n{done.stderr}"
    return done


def test_the_installed_wheel_puts_the_command_on_path_and_it_runs(tmp_path: Path) -> None:
    uv = shutil.which("uv")
    assert uv, "uv is not on PATH: this test builds the wheel with `uv build`"
    run(uv, "build", "--wheel", "--out-dir", str(tmp_path / "dist"), str(ROOT), cwd=tmp_path)
    (wheel,) = (tmp_path / "dist").glob("*.whl")
    # A new environment holding nothing but the wheel and what it depends on,
    # with this interpreter: nothing from this project's own environment.
    venv = tmp_path / "venv"
    run(uv, "venv", "--python", sys.executable, str(venv), cwd=tmp_path)
    run(uv, "pip", "install", "--python", str(venv), str(wheel), cwd=tmp_path)
    scripts = venv / ("Scripts" if os.name == "nt" else "bin")
    command = shutil.which(COMMAND, path=str(scripts))
    assert command, f"the wheel put no `{COMMAND}` command in {scripts}"
    # Found by name on PATH, as a shell finds it, from a directory with no source.
    env = {**os.environ, "PATH": f"{scripts}{os.pathsep}{os.environ.get('PATH', '')}"}
    env.pop("VIRTUAL_ENV", None)
    done = run(COMMAND, cwd=tmp_path, env=env)
    assert done.stdout == "Hello, world!\n"
    logged = [json.loads(line) for line in done.stderr.splitlines() if line]
    assert [r["message"] for r in logged] == ["started"], done.stderr
    assert run(COMMAND, "--version", cwd=tmp_path, env=env).stdout.startswith(f"{COMMAND} ")
