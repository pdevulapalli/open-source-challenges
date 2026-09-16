#!/usr/bin/env bash
set -euo pipefail

# Load shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../../lib/scripts/loader.sh"
set_tracking_context "echoes-lost-in-orbit" "expert" "01" "09" "2026"

OBJECTIVE="By the end of this level, you should have:
- Automated rollout progression to HotROD version 1.76.0 driven by observability signals
- OpenTelemetry Collector configured with:
  - OTLP receiver for traces from HotROD
  - Spanmetrics connector converting traces as metrics
  - Trace export to Jaeger, metrics export to Prometheus
- Canary analysis validating deployments with 3 queries:
  - Traffic detection ensuring minimum request rate (>= 0.05 req/s) to the canary to prevent idle canaries that get promoted but never had real traffic. You can use the hotrod_requests_total metric to verify this
  - Error rate thresholds (< 5%)
  - Latency thresholds for the 95th percentile (< 1000ms)"

DOCS_URL="https://offon.dev/adventures/echoes-lost-in-orbit/levels/expert"

print_header \
  'Challenge 01: Echoes Lost in Orbit' \
  '🔴 Expert: Hyperspace Operations & Transport' \
  'Verification'

check_prerequisites kubectl curl

print_sub_header "Running verification checks..."

# Init test counters
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_CHECKS=()

# Check if HotROD is deployed and reachable
is_app_reachable "hotrod" "hotrod" "" 8080 8080 "HotROD" \
  "<title>" \
  "Check the Argo Rollouts UI for details (select the hotrod namespace in the top right) or run: kubectl argo rollouts get rollout hotrod -n hotrod"

print_new_line

# Check if HotROD rollout is healthy and at correct version
check_rollout_status "hotrod" "hotrod" "1.76.0" \
  "Check the Argo Rollouts UI for details or run: kubectl argo rollouts get rollout hotrod -n hotrod. Ensure the rollout has fully promoted and is not stuck in Progressing or Degraded state."

print_new_line

# Check if AnalysisTemplate has 3 metrics
print_test_section "Checking AnalysisTemplate Configuration"
if kubectl get analysistemplate hotrod-analysis -n hotrod &>/dev/null; then
  METRICS_COUNT=$(kubectl get analysistemplate hotrod-analysis -n hotrod -o jsonpath='{.spec.metrics[*].name}' 2>/dev/null | wc -w | tr -d ' ')

  if [ "$METRICS_COUNT" -eq 3 ]; then
    METRIC_NAMES=$(kubectl get analysistemplate hotrod-analysis -n hotrod -o jsonpath='{.spec.metrics[*].name}' 2>/dev/null)
    print_info_indent "✓ AnalysisTemplate has 3 metrics: $METRIC_NAMES"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    print_new_line
    print_success "✅ AnalysisTemplate is healthy!"
  else
    print_error_indent "AnalysisTemplate has $METRICS_COUNT metrics (expected 3)"
    print_hint "Add the missing idle canary detection metric to the AnalysisTemplate"
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
else
  print_error_indent "AnalysisTemplate 'hotrod-analysis' not found"
  print_hint "Check if the hotrod folder was deployed via ArgoCD"
  TESTS_FAILED=$((TESTS_FAILED + 1))
fi

print_new_line

# Check if metrics are available in Prometheus
check_prometheus_metrics "Prometheus Metrics" "prometheus" "prometheus-server" "80" \
  "hotrod_requests_total:Check if HotROD is exposing metrics and Prometheus is scraping them" \
  "traces_span_metrics_duration_milliseconds_bucket:Check if the OTel Collector spanmetrics connector is configured correctly"

print_new_line

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

check_submission_readiness "echoes-lost-in-orbit" "expert"
