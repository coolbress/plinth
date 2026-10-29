"""URL routes."""

from __future__ import annotations

from django.contrib import admin
from django.contrib.auth import views as auth
from django.http import HttpRequest, HttpResponse
from django.urls import path


def healthz(request: HttpRequest) -> HttpResponse:
    """Answers without touching the database: the image check and the host ask it."""
    return HttpResponse("ok", content_type="text/plain")


def home(request: HttpRequest) -> HttpResponse:
    """A page for `ci / web-audit` to read: Lighthouse and axe-core need one that answers."""
    return HttpResponse(
        '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<meta name="description" content="plinth\'s canary for the web archetype">'
        "<title>canary-web</title></head><body><main><h1>canary-web</h1>"
        '<p><a href="/accounts/login/">Log in</a></p></main></body></html>'
    )


urlpatterns = [
    path("admin/", admin.site.urls),
    path("healthz", healthz),
    # Django's log-in view at its default address: the page `ci / web-audit`
    # audits for a visitor.
    path("accounts/login/", auth.LoginView.as_view()),
    path("", home),
]
