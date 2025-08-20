.PHONY: help validate generate clean lint test sanitize install demo
.DEFAULT_GOAL := help

CYAN = \033[0;36m
GREEN = \033[0;32m
YELLOW = \033[1;33m
RED = \033[0;31m
NC = \033[0m

CHART_NAME ?= 
NAMESPACE ?= default
EXTERNAL_CHART ?=
CHART_VERSION ?=

help:
	@echo "$(CYAN)GitOps Platform Development Commands$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "Usage:\n  make $(CYAN)<target>$(NC)\n\nTargets:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(CYAN)%-15s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)


validate:
	@echo "$(CYAN)Validating GitOps configuration...$(NC)"
	@./scripts/validate-gitops.sh

generate:
	@if [ -z "$(CHART_NAME)" ] || [ -z "$(NAMESPACE)" ]; then \
		echo "$(RED)Error: CHART_NAME and NAMESPACE are required$(NC)"; \
		echo "Usage: make generate CHART_NAME=my-app NAMESPACE=default"; \
		exit 1; \
	fi
	@echo "$(CYAN)Generating ApplicationSet for $(CHART_NAME) in namespace $(NAMESPACE)...$(NC)"
	@./scripts/generate-appset.sh $(CHART_NAME) $(NAMESPACE) $(if $(EXTERNAL_CHART),--external-chart $(EXTERNAL_CHART)) $(if $(CHART_VERSION),--chart-version $(CHART_VERSION))

generate-external:
	@if [ -z "$(CHART_NAME)" ] || [ -z "$(NAMESPACE)" ] || [ -z "$(EXTERNAL_CHART)" ]; then \
		echo "$(RED)Error: CHART_NAME, NAMESPACE, and EXTERNAL_CHART are required$(NC)"; \
		echo "Usage: make generate-external CHART_NAME=nginx NAMESPACE=nginx-system EXTERNAL_CHART=https://kubernetes.github.io/ingress-nginx"; \
		exit 1; \
	fi
	@echo "$(CYAN)Generating ApplicationSet for external chart $(CHART_NAME)...$(NC)"
	@./scripts/generate-appset.sh $(CHART_NAME) $(NAMESPACE) --external-chart $(EXTERNAL_CHART) $(if $(CHART_VERSION),--chart-version $(CHART_VERSION))

lint:
	@echo "$(CYAN)Linting YAML files...$(NC)"
	@if command -v yamllint >/dev/null 2>&1; then \
		find . -name "*.yaml" -o -name "*.yml" | grep -v ".git" | xargs yamllint -c .yamllint.yml || echo "$(YELLOW)yamllint issues found$(NC)"; \
	else \
		echo "$(YELLOW)yamllint not installed, skipping YAML linting$(NC)"; \
	fi
	@echo "$(CYAN)Linting Helm charts...$(NC)"
	@if command -v helm >/dev/null 2>&1; then \
		for chart in charts/*/; do \
			if [ -f "$$chart/Chart.yaml" ]; then \
				echo "Linting $$chart"; \
				helm lint "$$chart" || echo "$(YELLOW)Helm lint issues in $$chart$(NC)"; \
			fi; \
		done; \
	else \
		echo "$(YELLOW)helm not installed, skipping Helm chart linting$(NC)"; \
	fi

test: validate lint
	@echo "$(GREEN)All tests passed!$(NC)"

clean:
	@echo "$(CYAN)Cleaning up...$(NC)"
	@find . -name "*.bak" -type f -delete
	@find . -name "*.tmp" -type f -delete
	@find . -name "*~" -type f -delete
	@echo "$(GREEN)Cleanup complete!$(NC)"

install-tools:
	@echo "$(CYAN)Installing development tools...$(NC)"
	@if ! command -v helm >/dev/null 2>&1; then \
		echo "Installing Helm..."; \
		curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash; \
	fi
	@if ! command -v kubectl >/dev/null 2>&1; then \
		echo "$(YELLOW)kubectl not found. Please install kubectl manually.$(NC)"; \
	fi
	@if ! command -v yq >/dev/null 2>&1; then \
		echo "Installing yq..."; \
		if command -v brew >/dev/null 2>&1; then \
			brew install yq; \
		else \
			echo "$(YELLOW)Please install yq manually: https://github.com/mikefarah/yq$(NC)"; \
		fi; \
	fi
	@if ! command -v yamllint >/dev/null 2>&1; then \
		echo "Installing yamllint..."; \
		if command -v pip3 >/dev/null 2>&1; then \
			pip3 install yamllint; \
		else \
			echo "$(YELLOW)Please install yamllint manually: pip install yamllint$(NC)"; \
		fi; \
	fi
	@if ! command -v yq >/dev/null 2>&1; then \
		echo "Installing yq..."; \
		if command -v brew >/dev/null 2>&1; then \
			brew install yq; \
		else \
			echo "$(YELLOW)Please install yq manually: https://github.com/mikefarah/yq$(NC)"; \
		fi; \
	fi
	@echo "$(GREEN)Tool installation complete!$(NC)"

demo:
	@echo "$(CYAN)Creating demo ApplicationSets...$(NC)"
	@make generate CHART_NAME=monitoring-stack NAMESPACE=monitoring
	@make generate CHART_NAME=demo-app NAMESPACE=default
	@make generate-external CHART_NAME=nginx-ingress NAMESPACE=nginx-system EXTERNAL_CHART=https://kubernetes.github.io/ingress-nginx CHART_VERSION=4.10.1
	@echo "$(GREEN)Demo ApplicationSets created! Check the applicationset/ directory.$(NC)"

examples:
	@echo "$(CYAN)GitOps Platform Usage Examples:$(NC)"
	@echo ""
	@echo "$(YELLOW)Generate ApplicationSet for internal chart:$(NC)"
	@echo "  make generate CHART_NAME=my-app NAMESPACE=default"
	@echo ""
	@echo "$(YELLOW)Generate ApplicationSet for external chart:$(NC)"
	@echo "  make generate-external CHART_NAME=prometheus NAMESPACE=monitoring \\"
	@echo "    EXTERNAL_CHART=https://prometheus-community.github.io/helm-charts \\"
	@echo "    CHART_VERSION=15.0.0"
	@echo ""
	@echo "$(YELLOW)Validate and test everything:$(NC)"
	@echo "  make test"
	@echo ""
	@echo "$(YELLOW)Clean up and sanitize:$(NC)"
	@echo "  make clean sanitize"

git-setup:
	@echo "$(CYAN)Setting up git configuration...$(NC)"
	@if [ -d .git ]; then \
		echo "Installing git hooks..."; \
		mkdir -p .git/hooks; \
		echo '#!g/bin/bash\nmake validate' > .git/hooks/pre-commit; \
		chmod +x .git/hooks/pre-commit; \
		echo "$(GREEN)Git hooks installed!$(NC)"; \
	else \
		echo "$(YELLOW)Not a git repository. Run 'git init' first.$(NC)"; \
	fi

status:
	@echo "$(CYAN)GitOps Platform Status:$(NC)"
	@echo ""
	@echo "$(YELLOW)ApplicationSets:$(NC) $$(find applicationset -name "*.yaml" 2>/dev/null | wc -l | tr -d ' ')"
	@echo "$(YELLOW)Helm Charts:$(NC) $$(find charts -maxdepth 1 -type d ! -path charts 2>/dev/null | wc -l | tr -d ' ')"
	@echo "$(YELLOW)Environments:$(NC) $$(find overlays -maxdepth 1 -type d ! -path overlays 2>/dev/null | wc -l | tr -d ' ')"
	@echo "$(YELLOW)Scripts:$(NC) $$(find scripts -name "*.sh" 2>/dev/null | wc -l | tr -d ' ')"
	@echo ""
	@if command -v git >/dev/null 2>&1 && [ -d .git ]; then \
		echo "$(YELLOW)Git Status:$(NC)"; \
		git status --porcelain | head -10; \
		if [ $$(git status --porcelain | wc -l) -gt 10 ]; then \
			echo "... and $$(($$(git status --porcelain | wc -l) - 10)) more files"; \
		fi; \
	fi