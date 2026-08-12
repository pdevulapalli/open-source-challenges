#!/usr/bin/env bash
# sync-adventure.sh - Copy one adventure plus the shared lib/ from the upstream
# OffOn repo into this repo, adding the Dynatrace tracking source.
#
# Paths are kept verbatim: adventures/<slug>/ and .devcontainer/<slug>_*/ land at
# the same paths they occupy upstream. Nothing is renamed, so no copied file
# needs its contents rewritten except one key per devcontainer.json.
#
# Only adventures whose slug has no NN- number prefix are supported — see
# validate_slug for why.
#
# Usage: sync-adventure.sh <adventure-slug> <upstream-checkout-dir> <repo-root>

set -euo pipefail

UPSTREAM_REPO_URL="https://github.com/off-on-dev/open-source-challenges"
EXTERNAL_SOURCE="dynatrace-community"
MANIFEST_NAME=".upstream-sync.yaml"

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <adventure-slug> <upstream-checkout-dir> <repo-root>" >&2
  exit 2
fi

SLUG=$1
UPSTREAM=$(cd "$2" && pwd)
REPO=$(cd "$3" && pwd)
MANIFEST="$REPO/$MANIFEST_NAME"

die() {
  echo "❌ $*" >&2
  exit 1
}

# -----------------------------------------------------------------------------
# Validate the slug against what upstream actually publishes.
#
# Numbered slugs (01-echoes-lost-in-orbit ... 05-lex-imperfecta) are rejected on
# purpose. They predate upstream's move to structured docs/*.yaml and still use
# docs/*.md, so they do not share a format with anything this script is built
# for. 01-echoes-lost-in-orbit additionally ships docs/solutions/ with full
# answers. Unnumbered slugs are upstream's current convention and the only ones
# supported here.
# -----------------------------------------------------------------------------
validate_slug() {
  [[ -d "$UPSTREAM/adventures" ]] || die "No adventures/ directory in upstream checkout $UPSTREAM"

  if [[ "$SLUG" =~ ^[0-9]+- ]]; then
    die "'$SLUG' is a numbered adventure. Those use the older docs/*.md layout and are not supported — only unnumbered slugs can be synced."
  fi

  local valid=() d name
  for d in "$UPSTREAM/adventures"/*/; do
    name=$(basename "$d")
    # planned/ holds unpublished drafts, not an adventure.
    [[ "$name" == "planned" ]] && continue
    # Skip the legacy numbered adventures, as above.
    [[ "$name" =~ ^[0-9]+- ]] && continue
    valid+=("$name")
  done

  [[ ${#valid[@]} -gt 0 ]] || die "Upstream has no unnumbered adventures to sync."

  local found=false v
  for v in "${valid[@]}"; do
    [[ "$v" == "$SLUG" ]] && found=true
  done

  if [[ "$found" != true ]]; then
    echo "❌ '$SLUG' is not a syncable adventure in upstream. Valid slugs:" >&2
    printf '   - %s\n' "${valid[@]}" >&2
    exit 1
  fi
}

# -----------------------------------------------------------------------------
# Locate the adventure's devcontainer directories. Upstream is inconsistent
# about number prefixes on the level segment (dead-reckoning_beginner vs
# 05-lex-imperfecta_01-beginner), so glob rather than assume a naming scheme.
# -----------------------------------------------------------------------------
find_devcontainers() {
  local d
  DEVCONTAINER_DIRS=()
  for d in "$UPSTREAM/.devcontainer/${SLUG}"_*/; do
    [[ -d "$d" ]] || continue
    DEVCONTAINER_DIRS+=("$(basename "${d%/}")")
  done

  if [[ ${#DEVCONTAINER_DIRS[@]} -eq 0 ]]; then
    die "No .devcontainer/${SLUG}_* directories upstream. The adventure looks incompletely packaged upstream — fix it there first."
  fi
}

# -----------------------------------------------------------------------------
# Replace a directory wholesale: delete first, so files removed upstream also
# disappear here instead of lingering. -p preserves the executable bit, which
# several init.sh/verify.sh rely on (they are invoked directly, not via bash).
# -----------------------------------------------------------------------------
replace_dir() {
  local src=$1 dest=$2
  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  cp -Rp "$src" "$dest"
}

# -----------------------------------------------------------------------------
# The adventure's display name, from the structured docs. Not used to rewrite
# anything — it goes in the PR body — but its absence means the adventure is not
# in the docs/*.yaml format this script expects, which is worth failing on.
# index.yaml is flat and the key sits at column 0, so grep -m1 is sufficient.
# -----------------------------------------------------------------------------
read_display_name() {
  local index="$REPO/adventures/$SLUG/docs/index.yaml"
  [[ -f "$index" ]] || die "Missing adventures/$SLUG/docs/index.yaml. This adventure is not in the expected structured-docs format."

  local name
  name=$(grep -m1 '^name:' "$index" | sed -e 's/^name:[[:space:]]*//' \
    -e 's/[[:space:]]*$//' \
    -e 's/^"\(.*\)"$/\1/' \
    -e "s/^'\(.*\)'\$/\1/")

  [[ -n "$name" ]] || die "Could not read a top-level 'name:' from adventures/$SLUG/docs/index.yaml"
  printf '%s' "$name"
}

# -----------------------------------------------------------------------------
# The only content transform: set remoteEnv.OFFON_EXTERNAL_SOURCE, which
# lib/scripts/tracker.sh reads to tag every bizevent with external.source. That
# is the whole reason this repo exists. Merged rather than assigned, in case
# upstream later adds remoteEnv keys of its own.
#
# The devcontainer "name" is deliberately left alone: unnumbered adventures
# already label their levels with the adventure name (e.g. "🧭 Dead Reckoning |
# 🟢 Beginner"), so there is nothing to fix. Only the legacy numbered adventures
# say "Adventure NN", and those cannot be synced.
#
# Every upstream devcontainer.json is strict JSON (no comments, no trailing
# commas), so jq round-trips them safely. jq does decode \uXXXX escapes to
# literal UTF-8, so emoji in some files change bytes without changing meaning.
# -----------------------------------------------------------------------------
apply_transform() {
  local dir f tmp
  for dir in "${DEVCONTAINER_DIRS[@]}"; do
    f="$REPO/.devcontainer/$dir/devcontainer.json"
    [[ -f "$f" ]] || die "Expected $f after copying, but it is missing."

    tmp=$(mktemp)
    jq --indent 2 --arg src "$EXTERNAL_SOURCE" '
      .remoteEnv = ((.remoteEnv // {}) + {"OFFON_EXTERNAL_SOURCE": $src})
    ' "$f" >"$tmp"
    mv "$tmp" "$f"
    echo "   transformed .devcontainer/$dir/devcontainer.json"
  done
}

# -----------------------------------------------------------------------------
# Upstream keeps level solutions under docs/solutions/ for some adventures.
# Copying verbatim is the rule here, so they are not stripped — but the operator
# should know they are in the PR and decide.
# -----------------------------------------------------------------------------
warn_on_solutions() {
  if [[ -d "$REPO/adventures/$SLUG/docs/solutions" ]]; then
    echo "⚠️  adventures/$SLUG/docs/solutions/ was copied — it contains level solutions." >&2
    echo "    Confirm this is intended before merging." >&2
  fi
}

# -----------------------------------------------------------------------------
# Provenance manifest. Records which upstream commit each synced path came from,
# so staleness is answerable and the PR can link a real compare range.
# Format is ours and deliberately trivial, so it needs no YAML library.
# -----------------------------------------------------------------------------
read_previous_sha() {
  [[ -f "$MANIFEST" ]] || return 0
  awk -v key="$SLUG" '
    $0 ~ "^  " key ":$" { found = 1; next }
    found && $1 == "sha:" { print $2; exit }
    found && $0 ~ /^  [^ ]/ { exit }
  ' "$MANIFEST"
}

update_manifest() {
  local sha=$1 today
  today=$(date -u +%Y-%m-%d)

  MANIFEST="$MANIFEST" SLUG="$SLUG" SHA="$sha" TODAY="$today" \
    UPSTREAM_REPO_URL="$UPSTREAM_REPO_URL" python3 - <<'PY'
import os
import re

manifest = os.environ["MANIFEST"]
entries = {}

# Parse our own fixed format: two-space-indented slug keys, each with sha and
# synced_at beneath. Anything unrecognised is dropped on rewrite, which is fine
# because this file has no other content.
try:
    with open(manifest, encoding="utf-8") as fh:
        current = None
        for line in fh:
            key = re.match(r"^  ([^\s:]+):\s*$", line)
            if key:
                current = key.group(1)
                entries[current] = {}
                continue
            field = re.match(r"^    (sha|synced_at):\s*(\S+)\s*$", line)
            if field and current:
                entries[current][field.group(1)] = field.group(2)
except FileNotFoundError:
    pass

for key in (os.environ["SLUG"], "lib"):
    entries[key] = {"sha": os.environ["SHA"], "synced_at": os.environ["TODAY"]}

lines = [
    "# Provenance for content copied from upstream. Maintained by",
    "# .github/workflows/sync-upstream-adventure.yaml — do not edit by hand.",
    f"upstream: {os.environ['UPSTREAM_REPO_URL']}",
    "entries:",
]
for key in sorted(entries):
    data = entries[key]
    if "sha" not in data:
        continue
    lines.append(f"  {key}:")
    lines.append(f"    sha: {data['sha']}")
    lines.append(f"    synced_at: {data.get('synced_at', 'unknown')}")

with open(manifest, "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines) + "\n")
PY
}

# -----------------------------------------------------------------------------
main() {
  command -v jq >/dev/null || die "jq is required"
  command -v python3 >/dev/null || die "python3 is required"

  validate_slug
  find_devcontainers

  local upstream_sha previous_sha display_name
  upstream_sha=$(git -C "$UPSTREAM" rev-parse HEAD)
  previous_sha=$(read_previous_sha)

  echo "🔄 Syncing '$SLUG' from upstream ${upstream_sha:0:8}"
  echo "   devcontainers: ${DEVCONTAINER_DIRS[*]}"

  replace_dir "$UPSTREAM/adventures/$SLUG" "$REPO/adventures/$SLUG"
  echo "   copied adventures/$SLUG/"

  local dir
  for dir in "${DEVCONTAINER_DIRS[@]}"; do
    replace_dir "$UPSTREAM/.devcontainer/$dir" "$REPO/.devcontainer/$dir"
    echo "   copied .devcontainer/$dir/"
  done

  # lib/ is shared by every adventure, so this can change behaviour for
  # adventures other than the one being synced. That is why the workflow opens a
  # PR instead of pushing to main — review lib/ diffs before merging.
  replace_dir "$UPSTREAM/lib" "$REPO/lib"
  echo "   copied lib/"

  display_name=$(read_display_name)
  echo "   adventure: $display_name"
  apply_transform
  warn_on_solutions

  update_manifest "$upstream_sha"
  echo "   updated $MANIFEST_NAME"

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "upstream_sha=$upstream_sha"
      echo "previous_sha=$previous_sha"
      echo "display_name=$display_name"
      echo "devcontainers=${DEVCONTAINER_DIRS[*]}"
    } >>"$GITHUB_OUTPUT"
  fi

  echo "✅ Done"
}

main "$@"
