#!/usr/bin/env bash
# The step of .github/workflows/uv-pin-reminder.yml (#841). Dependabot never
# raises the uv version written in an environment variable, so this says when it
# is behind: the pinned release is 90 days old or more and a newer one exists.
# Then one issue is open, its title kept current; below that, an open one gets
# its ending and is closed. A release newer than the pin is not urgent by itself:
# uv ships about twice a week, and a raise costs a template release and a pull
# request, so this asks for about one a quarter.
#
# Anything it cannot read stops it, red, before it writes: unknown is never read
# as up to date. The copies agreeing is tests/uv-pin.sh's job; python-ci.yml
# stands for them here. It needs GH_TOKEN with `issues: write`, and
# GITHUB_REPOSITORY and RUN_URL, which Actions gives it.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"
threshold_days=90
marker='<!-- plinth:uv-pin-reminder -->'

pins="$(sed -nE 's/^ *UV_VERSION:[[:space:]]"([^"]+)"$/\1/p' "$root/.github/workflows/python-ci.yml" | sort -u)"
if [ -z "$pins" ] || [ "$(printf '%s\n' "$pins" | wc -l | tr -d ' ')" != 1 ]; then
  echo "python-ci.yml does not name exactly one uv version: ${pins:-none}" >&2
  exit 1
fi
pinned="$pins"

latest_json="$(gh api repos/astral-sh/uv/releases/latest --jq '[.tag_name, .published_at] | @tsv')"
IFS=$'\t' read -r latest latest_at <<<"$latest_json"
pinned_at="$(gh api "repos/astral-sh/uv/releases/tags/$pinned" --jq .published_at)"

# "<days since the pinned release> <1 when the latest release is newer than it>"
read -r days newer < <(python3 - "$pinned_at" "$latest_at" <<'PY'
import datetime, sys
pinned, latest = (datetime.datetime.strptime(x, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc) for x in sys.argv[1:3])
print((datetime.datetime.now(datetime.timezone.utc) - pinned).days, int(latest > pinned))
PY
) || true
if [ -z "${days:-}" ] || [ -z "${newer:-}" ]; then
  echo "could not read the release dates: pinned $pinned_at, latest $latest_at" >&2
  exit 1
fi

# The open reminder this workflow wrote: its body starts with the marker and the
# Actions bot opened it. Someone else's is never touched.
issues="$(gh issue list --repo "$repo" --state open --limit 1000 --json number,body,author)"
ours="$(jq -c --arg m "$marker" '[.[] | select((.author.login == "app/github-actions" or .author.login == "github-actions[bot]") and (.body | startswith($m)))] | first // empty' <<<"$issues")"
open="$(jq -r '.number // empty' <<<"${ours:-null}")"

if [ "$latest" = "$pinned" ] || [ "$newer" != 1 ] || [ "$days" -lt "$threshold_days" ]; then
  echo "no reminder: uv $pinned is pinned ($days days old), the latest release is $latest"
  if [ -n "$open" ]; then
    # A closed issue carries its ending in the body. This run read the pin and
    # the releases only, so the criteria stay for whoever merged the raise.
    ending="$(mktemp)"; trap 'rm -f "$ending"' EXIT
    jq -r .body <<<"$ours" >"$ending"
    if ! grep -qx '## Outcome' "$ending"; then
      printf '\n## Outcome\n\nCompleted: uv %s is pinned and the latest release is %s, read by %s. That is the pin and the releases, not what the merge ran: whoever merged the raise ticks the criteria it met.\n' \
        "$pinned" "$latest" "${RUN_URL:-the scheduled run}" >>"$ending"
      gh issue edit "$open" --repo "$repo" --body-file "$ending"
    fi
    gh issue close "$open" --repo "$repo" --reason completed \
      --comment "uv $pinned is pinned; the latest release is $latest. Closed by ${RUN_URL:-the scheduled run}."
    echo "closed the reminder: issue #$open"
  fi
  exit 0
fi

title="Raise uv from $pinned to $latest: the pinned release is $days days old"
if [ -n "$open" ]; then
  # Only the title: whoever took the issue may have written in the body.
  gh issue edit "$open" --repo "$repo" --title "$title"
  echo "updated the reminder: issue #$open"
  exit 0
fi

body="$(mktemp)"; trap 'rm -f "$body"' EXIT
cat >"$body" <<EOF
$marker
## Parent

The weekly reminder #841 added.

## What to build

Every CI job that installs uv downloads one pinned release and checks it against a checksum. Dependabot does not raise this pin, so this reminder asked: uv $pinned is pinned and [$latest](https://github.com/astral-sh/uv/releases/tag/$latest) is the latest release when this was opened. The title follows the latest release while this is open. Raise to the latest release when you start, in this order:

1. Read the upgrade notes since $pinned ([the changelog](https://github.com/astral-sh/uv/blob/main/CHANGELOG.md)) for what plinth's commands depend on: the lockfile format, \`uv sync\` flags, \`--exclude-newer\`, \`--require-hashes\`.
2. In coolbress/plinth-template, raise the rendered release workflows' \`UV_VERSION\` and \`UV_SHA256\` in a pull request marked as part of this issue, and release the template.
3. In plinth, in one pull request, raise every copy and \`template_ref\` in \`scripts/new-project.sh\` to that tag. \`tests/uv-pin.sh\` lists each copy and fails while any two disagree or a checksum is not the release's own \`.sha256\` asset.

## Acceptance criteria

- [ ] Every uv pin names the same version with its release's checksum: \`tests/uv-pin.sh\` passes.
- [ ] The upgrade notes are read, and any change plinth's commands depend on is named in the pull request.
- [ ] CI passes on plinth and on the e2e run of the release that carries it.
- [ ] CHANGELOG says consumers get it by raising their \`coolbress/plinth\` pin.

## Not building

- Floating to "latest" without a checksum.
- Raising another tool's pin in the same change.

## Blocked by

None.

Opened by ${RUN_URL:-the scheduled run}; the first run after the pin is raised closes it.
EOF
gh issue create --repo "$repo" --title "$title" --label task --label ready-for-agent --body-file "$body"
