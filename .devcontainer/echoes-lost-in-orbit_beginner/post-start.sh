#!/usr/bin/env bash
set -e

echo "✨ Starting level 1 - Beginner"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/scripts/repository-url.sh"

REPO_URL="$(get_repository_url)"
echo "Using repository URL: $REPO_URL"
sed -i "s|__REPO_URL__|${REPO_URL}|g" "$REPO_ROOT"/adventures/echoes-lost-in-orbit/beginner/manifests/appset.yaml

kubectl apply -n argocd -f "$REPO_ROOT"/adventures/echoes-lost-in-orbit/beginner/manifests/appset.yaml

# Track that the environment is ready
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/scripts/tracker.sh"
set_tracking_context "echoes-lost-in-orbit" "beginner" "01" "09" "2026"
track_container_initialized