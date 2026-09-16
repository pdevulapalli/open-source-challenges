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

Content is copied **verbatim** apart from the numbered-slug rename below. Every level's
`devcontainer.json` also gets one added key:

```json
"remoteEnv": { "OFFON_EXTERNAL_SOURCE": "dynatrace-community" }
```

which is what `lib/scripts/tracker.sh` reads to tag usage as coming from the Dynatrace community.

`.upstream-sync.yaml` records which upstream commit each synced path came from, and the PR body
links the compare range since the last sync.

Notes for reviewers and maintainers:

- **Numbered upstream slugs lose the number.** `01-echoes-lost-in-orbit` lands as
  `adventures/echoes-lost-in-orbit/`, and its levels are relabelled from `Adventure 01 | 🟢 Beginner
  (…)` to `🛰️ Echoes Lost in Orbit | 🟢 Beginner (…)`. Re-running a sync is safe and idempotent.
- **On those PRs, check the rewritten paths.** The rename repoints `adventures/<slug>` and
  `.devcontainer/<slug>_*` references inside the copied files. They feed ArgoCD and `post-start.sh`,
  so a miss breaks the challenge. Community thread URLs keep the number.
- **Check the `lib/` diff on every sync PR.** `lib/` is shared by all adventures, so syncing one can
  change behaviour for the others, including live ones.
- **`adventures/lex-imperfecta/` is live and hand-copied.** Syncing `05-lex-imperfecta` now
  overwrites it rather than being rejected. That should work — it even fixes a level name the
  hand-copy missed — but it is untested, so review that PR closely.
- **`adventures/echoes-lost-in-orbit/` deliberately diverges from upstream.** It was authored
  against the old challenge structure — `smoke-test.sh`, no `Makefile`, and a "Verify Adventure"
  GitHub Actions step that does not exist in this repo, so a solved level never produced a
  certificate. It has been moved onto the current structure (`verify.sh` ending in
  `check_submission_readiness`), and `docs/` was dropped. A sync `rm -rf`s both
  `adventures/<slug>/` and `.devcontainer/<slug>_*` before copying, so re-syncing
  `01-echoes-lost-in-orbit` reverts all of it and puts the dead end back. Fix upstream first, or
  re-apply this divergence on top of that PR before merging.

## Attribution

Challenge content originates from [off-on-dev/open-source-challenges](https://github.com/off-on-dev/open-source-challenges). See that repo for license terms.
