from canary import alive


def test_alive() -> None:
    assert alive() == "canary"
