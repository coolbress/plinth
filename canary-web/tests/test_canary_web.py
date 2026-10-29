from __future__ import annotations

from pathlib import Path

import pytest
from django.contrib.auth.models import User
from django.core.management import call_command
from django.test import Client

from canary_web import greet
from canary_web.settings import database


def test_greet() -> None:
    assert greet("world") == "Hello, world!"


def test_healthz_answers_without_the_database(client: Client) -> None:
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.content == b"ok"


def test_admin_asks_an_anonymous_visitor_to_log_in(client: Client) -> None:
    response = client.get("/admin/", secure=True)
    assert response.status_code == 302
    assert "/admin/login/" in response["Location"]


# The mark: closing the response ends the request, which closes database connections.
@pytest.mark.django_db
def test_the_admin_s_static_files_are_served(static_root: Path, client: Client) -> None:
    call_command("collectstatic", "--noinput", verbosity=0)
    response = client.get("/static/admin/css/base.css", secure=True)
    try:
        assert response.status_code == 200
        assert response.headers["Content-Type"].startswith("text/css")
    finally:
        response.close()  # a file response holds the file open until closed


@pytest.mark.django_db
def test_the_migrations_apply_and_users_are_stored() -> None:
    User.objects.create_user("a", password="a-long-test-password")  # noqa: S106
    assert User.objects.count() == 1


def test_database_url_becomes_a_postgres_entry() -> None:
    entry = database("postgres://user:p%40ss@db.internal:5432/app?sslmode=verify-full")
    assert entry["ENGINE"] == "django.db.backends.postgresql"
    assert (entry["NAME"], entry["USER"], entry["PASSWORD"]) == ("app", "user", "p@ss")
    assert (entry["HOST"], entry["PORT"]) == ("db.internal", "5432")
    assert entry["OPTIONS"] == {"sslmode": "verify-full"}


def test_database_url_refuses_another_engine() -> None:
    with pytest.raises(ValueError, match="postgres"):
        database("mysql://u@h/db")


def test_home_answers_with_a_page(client: Client) -> None:
    response = client.get("/", secure=True)
    assert response.status_code == 200
    assert b'<html lang="en">' in response.content


def test_the_log_in_page_answers_a_visitor(client: Client) -> None:
    response = client.get("/accounts/login/", secure=True)
    assert response.status_code == 200
    assert b'name="password"' in response.content
