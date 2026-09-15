.DEFAULT_GOAL := help
.PHONY: test check lint install help

test: ## Run the full automated test suite
	@bash ./tests/run_tests.sh

check: lint ## Run syntax checks and linting
lint: ## Check bash syntax (and run shellcheck if available)
	@echo "Checking shell script syntax..."
	@bash -n gravlift tests/run_tests.sh
	@if command -v shellcheck >/dev/null 2>&1; then \
		echo "Running shellcheck..."; \
		shellcheck -e SC1091,SC2034 gravlift tests/run_tests.sh; \
	else \
		echo "shellcheck not found, syntax check passed (bash -n)."; \
	fi

install: ## Install or upgrade gravlift locally (to ~/opt and ~/.local/bin)
	@./gravlift self-install

help: ## Display this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
