from probe.farewell import farewell


def test_farewell() -> None:
    assert farewell("Ana") == "¡Adiós, Ana!"
