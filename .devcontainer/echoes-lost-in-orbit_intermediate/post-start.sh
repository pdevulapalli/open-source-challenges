#!/usr/bin/env bash
set -e

echo "✨ Starting level 2 - Intermediate"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/scripts/repository-url.sh"

REPO_URL="$(get_repository_url)"
echo "Using repository URL: $REPO_URL"
sed -i "s|__REPO_URL__|${REPO_URL}|g" "$REPO_ROOT"/adventures/echoes-lost-in-orbit/intermediate/manifests/appset.yaml

kubectl apply -n argocd -f "$REPO_ROOT"/adventures/echoes-lost-in-orbit/intermediate/manifests/appset.yaml

# Give ArgoCD some time to process the ApplicationSet and create the Rollout application
sleep 10

# Update podinfo image to trigger a rollout
sed -i 's|podinfo:6.8.0|podinfo:6.9.3|g' "$REPO_ROOT"/adventures/echoes-lost-in-orbit/intermediate/manifests/base/rollout.yaml
# Only commit when the bump is actually new: on a Codespace restart the file is
# already at podinfo 6.9.3, and an empty commit would abort this script under `set -e`.
git add "$REPO_ROOT"/adventures/echoes-lost-in-orbit/intermediate/manifests/base/rollout.yaml
if git diff --cached --quiet -- "$REPO_ROOT"/adventures/echoes-lost-in-orbit/intermediate/manifests/base/rollout.yaml; then
  echo "Already at podinfo 6.9.3 — skipping commit."
else
  git commit -m "Update podinfo image to 6.9.3"
  git push
fi

# Refresh ArgoCD to pick up the new commit
argocd app get echo-server-staging --refresh
argocd app get echo-server-prod --refresh

# Track that the environment is ready
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/scripts/tracker.sh"
set_tracking_context "echoes-lost-in-orbit" "intermediate" "01" "09" "2026"
track_container_initialized

"$REPO_ROOT"/lib/argo-rollouts/connect.sh