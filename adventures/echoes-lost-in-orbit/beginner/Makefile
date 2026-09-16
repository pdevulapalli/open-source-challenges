.DEFAULT_GOAL := help

.PHONY: help apply verify

help:
	@echo "Echoes Lost in Orbit - Beginner: Available Commands:"
	@echo "  make apply    Apply the ApplicationSet to the cluster"
	@echo "  make verify   Run the verification script"

apply:
	@kubectl apply -n argocd -f manifests/appset.yaml

verify:
	@./verify.sh
