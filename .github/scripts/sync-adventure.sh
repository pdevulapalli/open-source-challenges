#!/usr/bin/env bash
# sync-adventure.sh - Copy one adventure plus the shared lib/ from the upstream
# OffOn repo into this repo, adding the Dynatrace tracking source.
#
# Upstream numbers its older adventures (01-echoes-lost-in-orbit) and sometimes
# their level segments too (05-lex-imperfecta_01-beginner). This repo publishes
# them unprefixed, so those NN- prefixes are stripped on the way in and the
# in-file references that point at the old location are rewritten to match — see
# strip_prefix and rewrite_paths. Content is otherwise copied verbatim: the only
# other change is one key per devcontainer.json.
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

# Upstream still numbers its older adventures, and sometimes the level segment
# of their devcontainer dirs. This repo publishes them unprefixed — which is what
# the hand-copied lex-imperfecta already does — so strip a leading NN-.
strip_prefix() {
  printf '%s' "$1" | sed -E 's/^[0-9]+-//'
}

SLUG=$1
UPSTREAM=$(cd "$2" && pwd)
REPO=$(cd "$3" && pwd)
MANIFEST="$REPO/$MANIFEST_NAME"

# Where this adventure lands in this repo. Differs from SLUG only for the legacy
# numbered upstream slugs.
LOCAL_SLUG=$(strip_prefix "$SLUG")

die() {
  echo "❌ $*" >&2
  exit 1
}

# -----------------------------------------------------------------------------
# Validate the slug against what upstream actually publishes.
#
# Numbered slugs are accepted and land here with the prefix stripped. They
# predate upstream's move to structured docs/*.yaml and mostly still use
# docs/*.md, which only affects the display name read for the PR body.
# 01-echoes-lost-in-orbit additionally ships docs/solutions/ with full answers —
# copied like everything else, but warned about, so the operator decides before
# merging.
# -----------------------------------------------------------------------------
validate_slug() {
  [[ -d "$UPSTREAM/adventures" ]] || die "No adventures/ directory in upstream checkout $UPSTREAM"

  local valid=() d name
  for d in "$UPSTREAM/adventures"/*/; do
    name=$(basename "$d")
    # planned/ holds unpublished drafts, not an adventure.
    [[ "$name" == "planned" ]] && continue
    valid+=("$name")
    # Two upstream slugs differing only by number prefix would land on the same
    # local path and silently overwrite each other.
    if [[ "$name" != "$SLUG" && "$(strip_prefix "$name")" == "$LOCAL_SLUG" ]]; then
      die "'$SLUG' and '$name' both map to adventures/$LOCAL_SLUG. Sync one of them by hand."
    fi
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
#
# DEVCONTAINER_DIRS holds the upstream names, LOCAL_DEVCONTAINER_DIRS the names
# they take here with the prefix stripped from both segments. The two arrays stay
# index-aligned; rewrite_paths pairs them up.
# -----------------------------------------------------------------------------
find_devcontainers() {
  local d name level
  DEVCONTAINER_DIRS=()
  LOCAL_DEVCONTAINER_DIRS=()
  for d in "$UPSTREAM/.devcontainer/${SLUG}"_*/; do
    [[ -d "$d" ]] || continue
    name=$(basename "${d%/}")
    level=$(strip_prefix "${name#"${SLUG}_"}")
    DEVCONTAINER_DIRS+=("$name")
    LOCAL_DEVCONTAINER_DIRS+=("${LOCAL_SLUG}_${level}")
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
# Repoint in-file references at the stripped paths. Only the two path prefixes
# are rewritten — "adventures/<upstream-slug>" and ".devcontainer/<upstream-dir>"
# — never the bare slug, because the docs link to community threads whose URLs
# embed it (.../t/adventure-01-echoes-lost-in-orbit-easy-broken-echoes/117) and
# those have to keep pointing where they point.
#
# This is not cosmetic. Each level's manifests/appset.yaml feeds those paths to
# ArgoCD's git generator, and post-start.sh sed/kubectl/git-adds the same paths;
# left unrewritten they address a directory that does not exist here. The
# hand-copied lex-imperfecta shipped with exactly that bug — see commit 81bc383.
#
# Substitution is bytes-level, so images and anything else binary pass through
# untouched rather than needing an encoding guess.
# -----------------------------------------------------------------------------
rewrite_paths() {
  [[ "$LOCAL_SLUG" != "$SLUG" ]] || return 0

  local -a pairs=("adventures/$SLUG" "adventures/$LOCAL_SLUG")
  local -a roots=("$REPO/adventures/$LOCAL_SLUG")
  local i

  for i in "${!DEVCONTAINER_DIRS[@]}"; do
    pairs+=(".devcontainer/${DEVCONTAINER_DIRS[$i]}" ".devcontainer/${LOCAL_DEVCONTAINER_DIRS[$i]}")
    roots+=("$REPO/.devcontainer/${LOCAL_DEVCONTAINER_DIRS[$i]}")
  done

  python3 - "${#pairs[@]}" "${pairs[@]}" "${roots[@]}" <<'PY'
import os
import sys

npairs = int(sys.argv[1])
args = sys.argv[2:]
pairs = [(args[i].encode(), args[i + 1].encode()) for i in range(0, npairs, 2)]

changed = 0
for root in args[npairs:]:
    for dirpath, _, filenames in os.walk(root):
        for filename in filenames:
            path = os.path.join(dirpath, filename)
            with open(path, "rb") as fh:
                original = fh.read()
            data = original
            for old, new in pairs:
                data = data.replace(old, new)
            if data != original:
                with open(path, "wb") as fh:
                    fh.write(data)
                changed += 1

print(f"   rewrote path references in {changed} file(s)")
PY
}

# -----------------------------------------------------------------------------
# The adventure's display name, from the structured docs. Not used to rewrite
# anything — it goes in the PR body — but its absence means the adventure is not
# in the docs/*.yaml format this script expects. The legacy numbered adventures
# are not, so fall back to the first H1 of docs/index.md rather than failing a
# whole sync over a string that only decorates the PR body.
# -----------------------------------------------------------------------------
read_display_name() {
  local docs="$REPO/adventures/$LOCAL_SLUG/docs"
  local name=""

  if [[ -f "$docs/index.yaml" ]]; then
    # index.yaml is flat and the key sits at column 0, so grep -m1 is sufficient.
    name=$(grep -m1 '^name:' "$docs/index.yaml" | sed -e 's/^name:[[:space:]]*//' \
      -e 's/[[:space:]]*$//' \
      -e 's/^"\(.*\)"$/\1/' \
      -e "s/^'\(.*\)'\$/\1/")
  elif [[ -f "$docs/index.md" ]]; then
    # The legacy H1s read "# 🛰️ Adventure 01: Echoes Lost in Orbit". Drop the
    # leading emoji and the "Adventure NN:" so this yields a bare adventure name
    # ("Echoes Lost in Orbit"), the same shape index.yaml's name: gives.
    name=$(grep -m1 '^# ' "$docs/index.md" \
      | sed -e 's/^#[[:space:]]*//' \
        -e 's/^[^[:alnum:]]*//' \
        -e 's/^Adventure[[:space:]][0-9][0-9]*:*[[:space:]]*//' \
        -e 's/[[:space:]]*$//')
  else
    die "adventures/$LOCAL_SLUG/docs/ has neither index.yaml nor index.md — this adventure has no recognisable docs."
  fi

  [[ -n "$name" ]] || die "Could not read a display name from adventures/$LOCAL_SLUG/docs/"
  printf '%s' "$name"
}

# -----------------------------------------------------------------------------
# The adventure's emoji, if its docs H1 carries one ("# 🛰️ Adventure 01: …").
# Needed only for adventure 01, whose devcontainer labels are the one set with no
# emoji of their own; 02-05 already carry theirs.
# -----------------------------------------------------------------------------
read_display_emoji() {
  local index="$REPO/adventures/$LOCAL_SLUG/docs/index.md"
  [[ -f "$index" ]] || return 0
  grep -m1 '^# ' "$index" | sed -e 's/^#[[:space:]]*//' -e 's/[[:alnum:]].*$//' -e 's/[[:space:]]*$//'
}

# -----------------------------------------------------------------------------
# Swap the "Adventure NN" token in a level label for the adventure's name,
# keeping everything else upstream wrote:
#
#   "⚖️ Adventure 05 | 🟢 Beginner (The Twelve Tables)"
#     -> "⚖️ Lex Imperfecta | 🟢 Beginner (The Twelve Tables)"
#   "Adventure 01 | 🟢 Beginner (Broken Echoes)"
#     -> "🛰️ Echoes Lost in Orbit | 🟢 Beginner (Broken Echoes)"
#
# The emoji is prepended only when the label did not already start with one,
# which is adventure 01 alone. The swap is a literal bash replacement rather than
# sed, so a name containing & or / cannot corrupt the result.
# -----------------------------------------------------------------------------
relabel() {
  local name=$1 display=$2 emoji=$3 out

  [[ "$name" =~ (Adventure[[:space:]]+[0-9]+) ]] || { printf '%s' "$name"; return 0; }

  out=${name/"${BASH_REMATCH[1]}"/$display}
  if [[ "$out" == "$display"* && -n "$emoji" ]]; then
    out="$emoji $out"
  fi

  printf '%s' "$out"
}

# -----------------------------------------------------------------------------
# The only content transform: set remoteEnv.OFFON_EXTERNAL_SOURCE, which
# lib/scripts/tracker.sh reads to tag every bizevent with external.source. That
# is the whole reason this repo exists. Merged rather than assigned, in case
# upstream later adds remoteEnv keys of its own.
#
# The devcontainer "name" is relabelled for renamed adventures only. Unnumbered
# ones already name themselves ("🧭 Dead Reckoning | 🟢 Beginner (Laying the
# Keel)") and are left alone. The numbered ones say "⚖️ Adventure 05 | 🟢
# Beginner (The Twelve Tables)", which would still read "Adventure 05" here after
# the path prefix is stripped, so the "Adventure NN" token — and only that token
# — is swapped for the adventure's display name. The emoji and the level segment
# after the pipe are upstream's and stay untouched.
#
# This reproduces the live hand-copied lex-imperfecta names exactly, including
# the one its hand-edit missed: .devcontainer/lex-imperfecta_intermediate still
# says "Adventure 05" today.
#
# Every upstream devcontainer.json is strict JSON (no comments, no trailing
# commas), so jq round-trips them safely. jq does decode \uXXXX escapes to
# literal UTF-8, so emoji in some files change bytes without changing meaning.
# -----------------------------------------------------------------------------
apply_transform() {
  local display=$1 emoji=$2
  local dir f tmp before after

  for dir in "${LOCAL_DEVCONTAINER_DIRS[@]}"; do
    f="$REPO/.devcontainer/$dir/devcontainer.json"
    [[ -f "$f" ]] || die "Expected $f after copying, but it is missing."

    before=$(jq -r '.name // ""' "$f")
    after=$before
    # Only the renamed numbered adventures carry an "Adventure NN" label.
    if [[ "$LOCAL_SLUG" != "$SLUG" && -n "$before" ]]; then
      after=$(relabel "$before" "$display" "$emoji")
    fi

    tmp=$(mktemp)
    jq --indent 2 --arg src "$EXTERNAL_SOURCE" --arg name "$after" '
      .remoteEnv = ((.remoteEnv // {}) + {"OFFON_EXTERNAL_SOURCE": $src})
      | if $name != "" then .name = $name else . end
    ' "$f" >"$tmp"
    mv "$tmp" "$f"

    echo "   transformed .devcontainer/$dir/devcontainer.json"
    [[ "$before" == "$after" ]] || echo "     relabelled: $before → $after"
  done
}

# -----------------------------------------------------------------------------
# Upstream keeps level solutions under docs/solutions/ for some adventures.
# Copying verbatim is the rule here, so they are not stripped — but the operator
# should know they are in the PR and decide.
# -----------------------------------------------------------------------------
warn_on_solutions() {
  if [[ -d "$REPO/adventures/$LOCAL_SLUG/docs/solutions" ]]; then
    echo "⚠️  adventures/$LOCAL_SLUG/docs/solutions/ was copied — it contains level solutions." >&2
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
  awk -v key="$LOCAL_SLUG" '
    $0 ~ "^  " key ":$" { found = 1; next }
    found && $1 == "sha:" { print $2; exit }
    found && $0 ~ /^  [^ ]/ { exit }
  ' "$MANIFEST"
}

update_manifest() {
  local sha=$1 today
  today=$(date -u +%Y-%m-%d)

  MANIFEST="$MANIFEST" SLUG="$SLUG" LOCAL_SLUG="$LOCAL_SLUG" SHA="$sha" TODAY="$today" \
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
            field = re.match(r"^    (sha|synced_at|upstream_slug):\s*(\S+)\s*$", line)
            if field and current:
                entries[current][field.group(1)] = field.group(2)
except FileNotFoundError:
    pass

for key in (os.environ["LOCAL_SLUG"], "lib"):
    entries[key] = {"sha": os.environ["SHA"], "synced_at": os.environ["TODAY"]}

# A renamed adventure records where it came from, so a local path stays
# traceable to the upstream slug it was copied from.
if os.environ["SLUG"] != os.environ["LOCAL_SLUG"]:
    entries[os.environ["LOCAL_SLUG"]]["upstream_slug"] = os.environ["SLUG"]

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
    if data.get("upstream_slug"):
        lines.append(f"    upstream_slug: {data['upstream_slug']}")

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
  [[ "$LOCAL_SLUG" == "$SLUG" ]] || echo "   number prefix stripped — landing as '$LOCAL_SLUG'"
  echo "   devcontainers: ${LOCAL_DEVCONTAINER_DIRS[*]}"

  replace_dir "$UPSTREAM/adventures/$SLUG" "$REPO/adventures/$LOCAL_SLUG"
  echo "   copied adventures/$LOCAL_SLUG/"

  local i
  for i in "${!DEVCONTAINER_DIRS[@]}"; do
    replace_dir "$UPSTREAM/.devcontainer/${DEVCONTAINER_DIRS[$i]}" \
      "$REPO/.devcontainer/${LOCAL_DEVCONTAINER_DIRS[$i]}"
    echo "   copied .devcontainer/${LOCAL_DEVCONTAINER_DIRS[$i]}/"
  done

  # lib/ is shared by every adventure, so this can change behaviour for
  # adventures other than the one being synced. That is why the workflow opens a
  # PR instead of pushing to main — review lib/ diffs before merging.
  replace_dir "$UPSTREAM/lib" "$REPO/lib"
  echo "   copied lib/"

  rewrite_paths

  display_name=$(read_display_name)
  echo "   adventure: $display_name"
  apply_transform "$display_name" "$(read_display_emoji)"
  warn_on_solutions

  update_manifest "$upstream_sha"
  echo "   updated $MANIFEST_NAME"

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "upstream_sha=$upstream_sha"
      echo "previous_sha=$previous_sha"
      echo "display_name=$display_name"
      echo "local_slug=$LOCAL_SLUG"
      echo "devcontainers=${LOCAL_DEVCONTAINER_DIRS[*]}"
    } >>"$GITHUB_OUTPUT"
  fi

  echo "✅ Done"
}

main "$@"
