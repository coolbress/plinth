#!/usr/bin/env bash
# shellcheck shell=bash disable=SC2034  # template_* are read by the tests that source this file
# One checkout of plinth-template at the commit scripts/new-project.sh pins
# (#953). The tests that compare plinth with the template read files from it,
# so the comparison is local, and a network error is the fetch failing, not a
# test. Each `ci / install-<n>` job makes it once, before its tests, and hands them its
# path in PLINTH_TEMPLATE_DIR.
#
# Run:     tests/lib/template-checkout.sh <dest>
#          fetches template_sha and the tag template_ref into a new git
#          repository at <dest>, fails when the tag does not name that commit,
#          and checks the commit out. Three tries, then exit 1.
# Sourced: template_checkout <work dir>
#          sets template_repo, template_ref, template_sha (the door's pin),
#          template_dir (the checkout) and template_at (how a line names it).
#          With PLINTH_TEMPLATE_DIR set, that checkout is used, and it must
#          be at template_sha with nothing changed; without it, one is fetched
#          under <work dir>. On failure it returns 1 with template_error set.
#          TEMPLATE_REF reads another ref instead, a branch before its tag
#          exists: it is fetched, or PLINTH_TEMPLATE_DIR names a checkout
#          whose HEAD is that ref; nothing is compared with the pin.

template_pin() { # sets template_repo template_ref template_sha from the door
  local door
  door="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/new-project.sh"
  template_repo="$(sed -nE 's/^template_repo="([^"]+)"$/\1/p' "$door")"
  template_ref="$(sed -nE 's/^template_ref="([^"]+)"$/\1/p' "$door")"
  template_sha="$(sed -nE 's/^template_sha="([0-9a-f]{40})"$/\1/p' "$door")"
  [ -n "$template_repo" ] && [ -n "$template_ref" ] && [ -n "$template_sha" ] ||
    { template_error="no template_repo, template_ref and template_sha in $door"; return 1; }
}

template_fetch() { # <dest> <repo> <ref> [<sha>]: with a sha, the tag must name it
  local dest="$1" url="https://github.com/$2" ref="$3" sha="${4:-}" i tagged
  local -a fetch_refs=("$ref")
  [ -z "$sha" ] || fetch_refs=("$sha" "+refs/tags/$ref:refs/tags/$ref")
  git init -q "$dest" || return 1
  for i in 1 2 3; do
    git -C "$dest" fetch -q --depth 1 --no-tags "$url" "${fetch_refs[@]}" 2>/dev/null && break
    [ "$i" = 3 ] && { echo "could not fetch $2 at ${sha:-$ref} from $url (three tries)" >&2; return 1; }
    sleep $((i * 5))
  done
  if [ -n "$sha" ]; then
    tagged="$(git -C "$dest" rev-parse -q --verify "refs/tags/$ref^{commit}")"
    [ "$tagged" = "$sha" ] ||
      { echo "$2's tag $ref names ${tagged:-nothing}, not template_sha $sha: scripts/new-project.sh's pin disagrees with itself" >&2; return 1; }
  else
    sha="$(git -C "$dest" rev-parse FETCH_HEAD)"
  fi
  git -C "$dest" -c advice.detachedHead=false checkout -q "$sha"
}

template_checkout() { # <work dir>
  local head
  template_error=""
  template_pin || return 1
  if [ -n "${TEMPLATE_REF:-}" ]; then
    template_ref="$TEMPLATE_REF"; template_sha=""
    template_at="$template_repo@$TEMPLATE_REF (not the pin)"
    if [ -n "${PLINTH_TEMPLATE_DIR:-}" ]; then
      # Only a checkout of that ref: an exported pinned checkout would
      # otherwise be read under the branch's name.
      template_dir="$PLINTH_TEMPLATE_DIR"
      head="$(git -C "$template_dir" rev-parse -q --verify HEAD 2>/dev/null)"
      [ -n "$head" ] && [ "$(git -C "$template_dir" rev-parse -q --verify "$TEMPLATE_REF^{commit}" 2>/dev/null)" = "$head" ] ||
        { template_error="PLINTH_TEMPLATE_DIR ($template_dir) is not a checkout of $TEMPLATE_REF; unset it to fetch $TEMPLATE_REF"; return 1; }
      return 0
    fi
    template_dir="$1/plinth-template"
    template_fetch "$template_dir" "$template_repo" "$TEMPLATE_REF" 2>"$1/template-fetch.err" ||
      { template_error="$(cat "$1/template-fetch.err")"; return 1; }
    return 0
  fi
  template_at="$template_repo@$template_ref ($template_sha)"
  if [ -n "${PLINTH_TEMPLATE_DIR:-}" ]; then
    template_dir="$PLINTH_TEMPLATE_DIR"
    head="$(git -C "$template_dir" rev-parse HEAD 2>/dev/null)"
    [ "$head" = "$template_sha" ] ||
      { template_error="PLINTH_TEMPLATE_DIR ($template_dir) is at ${head:-no commit}, not the pinned $template_sha"; return 1; }
    [ -z "$(git -C "$template_dir" status --porcelain 2>/dev/null)" ] ||
      { template_error="PLINTH_TEMPLATE_DIR ($template_dir) has changes on top of $template_sha"; return 1; }
    return 0
  fi
  template_dir="$1/plinth-template"
  template_fetch "$template_dir" "$template_repo" "$template_ref" "$template_sha" 2>"$1/template-fetch.err" ||
    { template_error="$(cat "$1/template-fetch.err")"; return 1; }
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -uo pipefail
  [ $# = 1 ] && [ -n "$1" ] || { echo "usage: $0 <dest>" >&2; exit 2; }
  [ ! -e "$1" ] || { echo "$1 exists; give a new path" >&2; exit 2; }
  template_pin || { echo "$template_error" >&2; exit 1; }
  template_fetch "$1" "$template_repo" "$template_ref" "$template_sha" || exit 1
  echo "$template_repo $template_ref at $template_sha in $1"
fi
