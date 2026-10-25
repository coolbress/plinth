from probe import greet


def test_hidden_hi() -> None:
    assert greet("Ann") == "Hi, Ann!"
