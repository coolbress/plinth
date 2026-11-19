# canary-web's image, the template's web Dockerfile with one change: no
# `__main__.py` here, so uvicorn is the command. `ci / web-audit` builds and
# starts it (plinth #709). The two FROM lines are the pinned template's
# `template/Dockerfile.jinja`; tests/template-render.sh fails until a pin raise
# copies them here (#975).

# ── build stage ───────────────────────────────────────────────────────────
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim@sha256:e5b65587bce7de595f299855d7385fe7fca39b8a74baa261ba1b7147afa78e58 AS build

WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy

COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-install-project --no-dev

COPY src/ ./src/
COPY README.md LICENSE ./
RUN uv sync --locked --no-dev
RUN DJANGO_SETTINGS_MODULE=canary_web.settings .venv/bin/python -m django collectstatic --noinput

# ── run stage ─────────────────────────────────────────────────────────────
FROM python:3.12-slim@sha256:5e2bdb1b0d542d5039cffb8181c65930093949194a65c365dfb1b0fe13a4fa5b

RUN useradd --create-home --uid 10001 app
WORKDIR /app

COPY --from=build --chown=app:app /app/.venv /app/.venv
COPY --from=build --chown=app:app /app/src /app/src
ENV PATH="/app/.venv/bin:$PATH" PYTHONUNBUFFERED=1

USER app

CMD ["uvicorn", "canary_web.asgi:application", "--host", "0.0.0.0", "--port", "8000"]
