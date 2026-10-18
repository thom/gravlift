VERSION ?= $(shell sed -n 's/^GRAVLIFT_VERSION="\([^"]*\)"/\1/p' gravlift)
DIST_DIR ?= dist
PKG_NAME := gravlift-v$(VERSION)
ARCHIVE_NAME := $(PKG_NAME).tar.gz

.DEFAULT_GOAL := help
.PHONY: test check lint install dist clean help

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

dist: clean ## Build release tarball and SHA256 checksum in dist/
	@echo "Building distribution package $(ARCHIVE_NAME)..."
	@mkdir -p $(DIST_DIR)/$(PKG_NAME)
	@cp gravlift README.md LICENSE $(DIST_DIR)/$(PKG_NAME)/
	@chmod +x $(DIST_DIR)/$(PKG_NAME)/gravlift
	@tar -czf $(DIST_DIR)/$(ARCHIVE_NAME) -C $(DIST_DIR) $(PKG_NAME)
	@rm -rf $(DIST_DIR)/$(PKG_NAME)
	@cd $(DIST_DIR) && sha256sum $(ARCHIVE_NAME) > $(ARCHIVE_NAME).sha256
	@echo "Release archive created: $(DIST_DIR)/$(ARCHIVE_NAME)"
	@echo "SHA256 checksum: $$(awk '{print $$1}' $(DIST_DIR)/$(ARCHIVE_NAME).sha256)"

clean: ## Clean build and distribution artifacts
	@rm -rf $(DIST_DIR)

help: ## Display this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
