#!/usr/bin/env bash
# `ci / migrations` and `ci / deploy-check` (#614) on fixture projects, against
# a real Postgres. The steps are not copied here; they are extracted from
# python-ci.yml and run as the runner runs them, so the rule tested is the rule
# shipped. Each case is a git repository: a base commit, then a head commit.
#
# The fixture is canary-web with one app, `notes`, a model and its migration,
# and rows for it and for two users in tests/migration_rows.json.
#
# Needs docker (Postgres), uv and python3. Without docker it stops: on CI that
# is a FAIL, never a skip; on a laptop it says so and exits 0.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wf="$root/.github/workflows/python-ci.yml"

if ! command -v docker >/dev/null || ! docker info >/dev/null 2>&1; then
  if [ -n "${CI:-}" ]; then echo "  FAIL  docker is not available on CI: the web checks were not run"; exit 1; fi
  echo "  SKIP  docker is not available here; CI runs these cases"; exit 0
fi
command -v uv >/dev/null || { echo "  FAIL  uv is not installed"; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/web-checks.XXXXXX")"
pg="web-checks-$$-$RANDOM"
trap 'docker rm -f "$pg" >/dev/null 2>&1; rm -rf "$tmp"' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  PASS  %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | tail -15 | sed 's/^/        | /'; }

# A step's `run: |` block, dedented, by job and step id or name.
job_step() {
  python3 - "$wf" "$1" "$2" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
job, name = sys.argv[2], sys.argv[3]
j = next((i for i, l in enumerate(lines) if l == f"  {job}:"), None)
end = next((i for i in range(j + 1, len(lines)) if lines[i][:3].strip() and lines[i].startswith("  ") and not lines[i].startswith("   ")), len(lines)) if j is not None else 0
at = next((i for i in range(j or 0, end) if lines[i].strip() in (f"- name: {name}", f"- id: {name}")), None)
if j is None or at is None:
    sys.exit(f"step not found: {job} / {name}")
i = next(k for k in range(at, end) if lines[k].strip() == "run: |")
indent = None
for l in lines[i + 1:end]:
    if l.strip() and indent is None:
        indent = len(l) - len(l.lstrip())
    if l.strip() and len(l) - len(l.lstrip()) < indent:
        break
    print(l[indent:] if l.strip() else "")
PY
}
for s in "migrations missing" "migrations empty" "migrations rows" "deploy-check deploy"; do
  set -- $s
  job_step "$1" "$2" > "$tmp/$1.$2.sh" || { echo "  FAIL  $1 / $2: step not found in python-ci.yml"; exit 1; }
done

echo "-- a disposable Postgres"
docker run -d --name "$pg" -e POSTGRES_PASSWORD=ci -p 127.0.0.1::5432 \
  postgres:17-alpine@sha256:b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24 >/dev/null \
  || { echo "  FAIL  postgres did not start"; exit 1; }
# Over TCP, as python-ci.yml waits: the image's first-start server is socket only.
for _ in $(seq 60); do docker exec "$pg" pg_isready -h 127.0.0.1 -U postgres -q && break; sleep 1; done
port="$(docker port "$pg" 5432/tcp | head -1 | sed 's/.*://')"
docker exec "$pg" pg_isready -h 127.0.0.1 -U postgres -q || { echo "  FAIL  postgres is not ready"; exit 1; }
# A new database per call. Called in $( ), so the name cannot come from a
# counter (a subshell's increment is lost): every case once shared one database.
db() {
  local name; name="d$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
  docker exec "$pg" createdb -U postgres "$name" || return 1
  echo "postgres://postgres:ci@127.0.0.1:$port/$name"
}

# The base commit: canary-web, the notes app with its migration, the rows.
base_repo() { # [no-rows]
  r="$tmp/r$((pass+fail))"; rm -rf "$r"; mkdir -p "$r"
  cp -R "$root/canary-web/." "$r/"
  rm -rf "$r/.venv"
  mkdir -p "$r/src/canary_web/notes/migrations"
  touch "$r/src/canary_web/notes/__init__.py" "$r/src/canary_web/notes/migrations/__init__.py"
  printf 'from django.db import models\n\n\nclass Note(models.Model):\n    text = models.CharField(max_length=100)\n' \
    > "$r/src/canary_web/notes/models.py"
  sed -i.bak 's/    "django.contrib.staticfiles",/    "django.contrib.staticfiles",\n    "canary_web.notes",/' "$r/src/canary_web/settings.py"
  rm -f "$r/src/canary_web/settings.py.bak"
  (cd "$r" && uv sync --locked --quiet && uv run --quiet python manage.py makemigrations notes >/dev/null) \
    || { bad "the fixture's base could not be made"; return 1; }
  if [ "${1:-}" = no-rows ]; then rm -f "$r/tests/migration_rows.json"
  else
    python3 - "$r/tests/migration_rows.json" <<'PY'
import json, sys
p = sys.argv[1]
rows = json.load(open(p))
rows += [{"model": "notes.note", "pk": i, "fields": {"text": f"note {i}"}} for i in (1, 2)]
json.dump(rows, open(p, "w"), indent=1)
PY
  fi
  git -C "$r" init -q -b main
  git -C "$r" -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false add -A
  git -C "$r" -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false commit -qm base
}
head_commit() { git -C "$r" add -A; git -C "$r" -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false commit -qm head; }

# run <job.step> <database url> -- sets $out, $rc; RUNNER_TEMP is per case
run() {
  local rt="$r.rt"; mkdir -p "$rt"
  out="$(cd "$r" && env RUNNER_TEMP="$rt" WD=. DATABASE_URL="$2" \
    DJANGO_ALLOWED_HOSTS=deploy-check.invalid bash -e "$tmp/$1.sh" 2>&1)"; rc=$?
  verdict="$(cat "$rt/rows.verdict" 2>/dev/null)"
}
migrations() { # every step of the job, in order: sets $rc_missing $rc_empty $rc_rows
  rc_missing=x rc_empty=x rc_rows=x verdict="" out_missing="" out_empty="" out_rows=""
  local empty rows; empty="$(db)" && rows="$(db)" || { bad "a database could not be created"; return 1; }
  run migrations.missing "$empty"; rc_missing=$rc; out_missing="$out"
  run migrations.empty "$empty"; rc_empty=$rc; out_empty="$out"
  run migrations.rows "$rows"; rc_rows=$rc; out_rows="$out"
}

echo "-- ci / migrations"
base_repo && { printf '\nA line.\n' >> "$r/README.md"; head_commit; migrations
  if [ "$rc_missing$rc_empty$rc_rows" = 000 ] && grep -q "^pass: .*every count the same" <<<"$verdict"; then
    ok "must pass: a head that does not touch the schema; the base rows keep their counts ($verdict)"
  else bad "must pass: an untouched schema did not pass ($rc_missing$rc_empty$rc_rows)" "$out_missing$out_empty$out_rows$verdict"; fi; }

base_repo && { printf '    done = models.BooleanField(default=False)\n' >> "$r/src/canary_web/notes/models.py"; head_commit; migrations
  [ "$rc_missing" != 0 ] && ok "must fail: a model change without its migration fails makemigrations --check" \
    || bad "a model change without its migration passed" "$out_missing"; }

base_repo && { git -C "$r" mv src/canary_web/notes/migrations src/canary_web/notes/old_migrations; head_commit; migrations
  [ "$rc_missing" != 0 ] && ok "must fail: migrations moved out of the app's migrations package (#614 criterion 4)" \
    || bad "moved migrations passed" "$out_missing"; }

base_repo && { git -C "$r" rm -rq src/canary_web/notes/migrations; head_commit; migrations
  [ "$rc_missing" != 0 ] && ok "must fail: the app's migrations deleted (#614 criterion 4)" \
    || bad "deleted migrations passed" "$out_missing"; }

base_repo && {
  cat > "$r/src/canary_web/notes/migrations/0002_clean_up.py" <<'EOF'
from django.db import migrations


def forget(apps, schema_editor):
    apps.get_model("notes", "Note").objects.all().delete()


class Migration(migrations.Migration):
    dependencies = [("notes", "0001_initial")]
    operations = [migrations.RunPython(forget, migrations.RunPython.noop)]
EOF
  head_commit; migrations
  if [ "$rc_missing$rc_empty" = 00 ] && [ "$rc_rows" != 0 ] && grep -q "^fail: .*notes_note 2 -> 0" <<<"$verdict"; then
    ok "must fail: a migration that deletes the base's rows, naming the table and both counts"
  else bad "a row-deleting migration did not fail on the rows ($rc_missing$rc_empty$rc_rows)" "$out_rows$verdict"; fi; }

base_repo no-rows && { printf '\nA line.\n' >> "$r/README.md"; head_commit; migrations
  if [ "$rc_rows" = 0 ] && grep -q "^not yet confirmed: .*has no tests/migration_rows.json" <<<"$verdict"; then
    ok "a base without the rows file: not yet confirmed, never a pass"
  else bad "a base without the rows file did not read as not yet confirmed" "$out_rows$verdict"; fi; }

base_repo && {
  python3 - "$r/tests/migration_rows.json" <<'PY'
import json, sys
p = sys.argv[1]
rows = json.load(open(p)) + [{"model": "auth.permission", "pk": 999, "fields": {"name": "x", "content_type": 1, "codename": "x"}}]
json.dump(rows, open(p, "w"))
PY
  git -C "$r" -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false commit -qam "rows with a permission"
  printf '\nA line.\n' >> "$r/README.md"; head_commit; migrations
  if [ "$rc_rows" != 0 ] && grep -q "auth.permission" <<<"$out_rows"; then
    ok "must fail: base rows holding a model migrate rewrites (auth.permission), named"
  else bad "rows holding auth.permission did not fail" "$out_rows$verdict"; fi; }

echo "-- ci / deploy-check"
base_repo && { printf '\nA line.\n' >> "$r/README.md"; head_commit
  run deploy-check.deploy "postgres://deploy-check@localhost:5432/none"
  [ "$rc" = 0 ] && ok "must pass: the rendered settings with debug off" || bad "the rendered settings failed check --deploy" "$out"; }

base_repo && { printf '\nDEBUG = True\n' >> "$r/src/canary_web/settings.py"; head_commit
  run deploy-check.deploy "postgres://deploy-check@localhost:5432/none"
  if [ "$rc" != 0 ] && grep -q "security.W018" <<<"$out"; then ok "must fail: DEBUG on in the production settings (security.W018)"
  else bad "DEBUG on passed check --deploy" "$out"; fi; }

echo "-- $pass passed, $fail failed"
[ "$fail" = 0 ]
