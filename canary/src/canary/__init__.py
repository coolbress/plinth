"""Proves the reusable workflow lints, type-checks, tests, builds and installs."""


def alive() -> str:
    return "canary"


def tripled(x: int) -> int:
    if x > 1:
        return x * 3
    return x
