.DEFAULT_GOAL := help

.PHONY: help apply verify

help:
	@echo "Echoes Lost in Orbit - Intermediate: Available Commands:"
	@echo "  make apply    Apply the ApplicationSet to the cluster"
	@echo "  make verify   Run the verification script"

# The AnalysisTemplate and Rollout are delivered by ArgoCD from git, so commit and
# push your changes and let ArgoCD sync them. This only re-applies the ApplicationSet.
apply:
	@kubectl apply -n argocd -f manifests/appset.yaml

verify:
	@./verify.sh
