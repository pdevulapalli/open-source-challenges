#!/usr/bin/env bash
set -euo pipefail

# Load shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../../lib/scripts/loader.sh"
set_tracking_context "echoes-lost-in-orbit" "intermediate" "01" "09" "2026"

OBJECTIVE="By the end of this level, you should have:
- Pod info version 6.9.3 deployed successfully in both staging and production environments
- Rollouts automatically progress through canary stages based on health metrics
- Two working PromQL queries in the AnalysisTemplate that validate application health during releases
- All rollouts complete successfully"

DOCS_URL="https://offon.dev/adventures/echoes-lost-in-orbit/levels/intermediate"

print_header \
  'Challenge 01: Echoes Lost in Orbit' \
  '🟡 Intermediate: The Silent Canary' \
  'Verification'

check_prerequisites kubectl curl

print_sub_header "Running verification checks..."

# Init test counters
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_CHECKS=()

# Check if both environments are reachable
is_app_reachable "echo-server" "echo-staging" "version" 8081 80 "Staging" \
  "\"version\": \"6.9.3\"" \
  "Check the Argo Rollouts UI for details on the staging rollout (select the 'echo-staging' namespace in the top right)"

print_new_line

is_app_reachable "echo-server" "echo-prod" "version" 8082 80 "Production" \
  "\"version\": \"6.9.3\"" \
  "Check the Argo Rollouts UI for details on the prod rollout (select the 'echo-prod' namespace in the top right)"

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

check_submission_readiness "echoes-lost-in-orbit" "intermediate"
