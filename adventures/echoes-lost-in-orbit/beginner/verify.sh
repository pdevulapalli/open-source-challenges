#!/usr/bin/env bash
set -euo pipefail

# Load shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../../lib/scripts/loader.sh"
set_tracking_context "echoes-lost-in-orbit" "beginner" "01" "09" "2026"

OBJECTIVE="By the end of this level, you should:

- See two distinct Applications in the Argo CD dashboard (one per environment)
- Ensure each Application deploys to its own isolated namespace
- Make the system resilient so Argo CD automatically reverts manual changes made to the cluster
- Confirm that updates happen automatically without leaving stale resources behind"

DOCS_URL="https://offon.dev/adventures/echoes-lost-in-orbit/levels/beginner"

print_header \
  'Challenge 01: Echoes Lost in Orbit' \
  'Level 1: Broken Echoes' \
  'Verification'

check_prerequisites kubectl curl

print_sub_header "Running verification checks..."

# Init test counters
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_CHECKS=()

# Check if both environments are reachable
is_app_reachable "echo-server-staging" "echo-staging" "healthz" 8081 80 "Staging" \
  "Hostname: echo-server-staging" \
  "Check if the ArgoCD ApplicationSet is configured correctly"

print_new_line

is_app_reachable "echo-server-prod" "echo-prod" "healthz" 8082 80 "Production" \
  "Hostname: echo-server-prod" \
  "Check if the ArgoCD ApplicationSet is configured correctly"

# =============================================================================
# Summary & Next Steps
# =============================================================================
failed_checks_json="[]"
if [[ -n "${FAILED_CHECKS[*]:-}" ]]; then
  failed_checks_json=$(printf '%s\n' "${FAILED_CHECKS[@]}" | jq -R . | jq -s .)
fi

if [[ $TESTS_FAILED -gt 0 ]]; then
  track_verification_completed "failed" "$failed_checks_json"
  print_verification_summary "echoes-lost-in-orbit" "$DOCS_URL" "$OBJECTIVE"
  exit 1
fi

track_verification_completed "success" "$failed_checks_json"

print_header "Test Results Summary"
print_success "✅ PASSED: All $TESTS_PASSED verification checks passed!"
print_new_line

check_submission_readiness "echoes-lost-in-orbit" "beginner"
