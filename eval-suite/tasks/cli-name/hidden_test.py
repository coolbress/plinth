import subprocess
import sys


def test_hidden_name_option() -> None:
    named = subprocess.run(
        [sys.executable, "-m", "probe", "--name", "Ann"], capture_output=True, text=True, check=False
    )
    assert named.returncode == 0, named.stderr
    assert "Ann" in named.stdout


def test_hidden_default_still_world() -> None:
    plain = subprocess.run([sys.executable, "-m", "probe"], capture_output=True, text=True, check=False)
    assert plain.returncode == 0, plain.stderr
    assert "world" in plain.stdout
