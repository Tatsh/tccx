# tccx — build helpers for the tcc-preapprove Swift package.
# Run `make help` for the list of targets. macOS only (links Security + SQLite3).

SWIFT   ?= swift
YARN    ?= yarn
PRODUCT := tcc-preapprove
PREFIX  ?= /usr/local
ARGS    ?=

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help.
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[1m%-14s\033[0m %s\n", $$1, $$2}'

.PHONY: build
build: ## Build the package (debug).
	$(SWIFT) build

.PHONY: release
release: ## Build the package (release).
	$(SWIFT) build -c release

.PHONY: test
test: ## Run the test suite.
	$(SWIFT) test

.PHONY: run
run: ## Run tcc-preapprove (pass arguments via ARGS='...').
	$(SWIFT) run $(PRODUCT) $(ARGS)

.PHONY: install
install: release ## Build release and install the binary into $(PREFIX)/bin.
	install -d "$(PREFIX)/bin"
	install -m 0755 .build/release/$(PRODUCT) "$(PREFIX)/bin/$(PRODUCT)"

.PHONY: clean
clean: ## Remove build products.
	$(SWIFT) package clean
	rm -rf .build

.PHONY: format
format: ## Format docs/JSON (prettier + markdownlint).
	$(YARN) format

.PHONY: qa
qa: ## Run spelling + formatting checks.
	$(YARN) qa
