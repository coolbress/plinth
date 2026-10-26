import re
import secrets

import pytest
from django.contrib.auth.models import User
from django.test import Client

from probe.notes.models import Note


def page(client: Client) -> tuple[int, str]:
    codes = {}
    for url in ("/stats/", "/stats"):
        response = client.get(url, secure=True)
        codes[url] = response.status_code
        if response.status_code == 200:
            return 200, re.sub(r"<[^>]*>", " ", response.content.decode())
    raise AssertionError(f"no stats page: {codes}")


@pytest.mark.django_db
def test_hidden_stats_counts_only_your_own_notes() -> None:
    alice = User.objects.create_user("alice", password=secrets.token_urlsafe())
    bob = User.objects.create_user("bob", password=secrets.token_urlsafe())
    for i in range(7):
        Note.objects.create(owner=alice, text=f"alice {i}")
    for i in range(4):
        Note.objects.create(owner=bob, text=f"bob {i}")
    client = Client()
    client.force_login(alice)
    _, text = page(client)
    assert re.search(r"(?<!\d)7(?!\d)", text), f"alice's 7 notes are not on the page: {text!r}"
    assert not re.search(r"(?<!\d)(4|11)(?!\d)", text), f"another person's notes are counted: {text!r}"


@pytest.mark.django_db
def test_hidden_stats_asks_an_anonymous_person_to_log_in() -> None:
    for url in ("/stats/", "/stats"):
        response = Client().get(url, secure=True)
        if response.status_code != 404:
            assert response.status_code == 302, f"{url}: {response.status_code}"
            assert response["Location"].startswith("/accounts/login/"), response["Location"]
            return
    raise AssertionError("no stats page")
