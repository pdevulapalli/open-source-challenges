#!/usr/bin/env bash
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "$REPO_ROOT/lib/scripts/tracker.sh"
set_tracking_context "echoes-lost-in-orbit" "beginner" "01" "09" "2026"
track_container_created

"$REPO_ROOT"/lib/shared/init.sh --version v0.17.0 # https://github.com/charmbracelet/gum/releases
# kind: https://github.com/kubernetes-sigs/kind/releases | kubectl: https://dl.k8s.io | kubens: https://github.com/ahmetb/kubectx/releases | k9s: https://github.com/derailed/k9s/releases | helm: https://github.com/helm/helm/releases
"$REPO_ROOT"/lib/kubernetes/init.sh \
  --kind-version v0.30.0 \
  --kubectl-version v1.34.1 \
  --kubens-version v0.9.5 \
  --k9s-version v0.50.16 \
  --helm-version v4.0.1
"$REPO_ROOT"/lib/argocd/init.sh --read-only --version v3.2.0 # https://github.com/argoproj/argo-cd/releases
