# Open Source Challenges: Dynatrace Community Edition

This repo hosts a curated selection of challenges from [off-on-dev/open-source-challenges](https://github.com/off-on-dev/open-source-challenges), adapted for the [Dynatrace community](https://community.dynatrace.com/).

## Why this repo exists

The OffOn open source challenges are designed to run in a devcontainer, both locally and via GitHub Codespaces. To give the Dynatrace community dedicated usage tracking, each challenge run needs to report where it came from.

Rather than adding Dynatrace-specific devcontainer configs into the core OffOn repo, which would clutter a partner-agnostic project with community-specific setup, we maintain this separate repo. It contains the subset of challenges relevant to the Dynatrace community, with its own devcontainer configuration.

## Staying in sync with OffOn

Challenge content in this repo is sourced from the upstream OffOn repo and should not diverge. Please make content fixes upstream in [off-on-dev/open-source-challenges](https://github.com/off-on-dev/open-source-challenges) rather than here. This repo only adds the devcontainer configuration on top.

### Sync process

Run the **Sync adventure from upstream** workflow from the Actions tab and give it an adventure slug
(e.g. `dead-reckoning`). It copies that adventure plus the shared `lib/` from upstream `main` and
opens a PR, so maintainers pick exactly which challenges get synced rather than pulling in
everything automatically.

Content is copied **verbatim** — paths keep their upstream names, and the only change to any copied
file is one added key per level's `devcontainer.json`:

```json
"remoteEnv": { "OFFON_EXTERNAL_SOURCE": "dynatrace-community" }
```

which is what `lib/scripts/tracker.sh` reads to tag usage as coming from the Dynatrace community.

`.upstream-sync.yaml` records which upstream commit each synced path came from, and the PR body
links the compare range since the last sync.

Notes for reviewers and maintainers:

- **Only unnumbered adventure slugs can be synced.** Upstream's older numbered adventures
  (`01-*` … `05-*`) use a `docs/*.md` layout instead of the current structured `docs/*.yaml`, so the
  workflow rejects them. Re-running for an already-synced adventure is safe and idempotent.
- **`adventures/lex-imperfecta/` is live and hand-copied.** It predates this workflow and uses a
  prefix-stripped layout. Leave it alone; the numbered-slug restriction means the workflow can't
  reach it.
- **Check the `lib/` diff on every sync PR.** `lib/` is shared by all adventures, so syncing one can
  change behaviour for the others, including live ones.

## Attribution

Challenge content originates from [off-on-dev/open-source-challenges](https://github.com/off-on-dev/open-source-challenges). See that repo for license terms.
