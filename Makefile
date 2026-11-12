.DEFAULT_GOAL := help
.PHONY: help build debug plugin specs icon install install.replace update uninstall clean \
        start stop restart status doctor logs settings rescan reset.accessibility \
        test test.unit test.integration version release.dry.run release

TGR := $(HOME)/.local/bin/tgr
# Any installed JetBrains IDE works; override with `make plugin IDE=/Applications/IntelliJ\ IDEA.app`.
IDE ?= $(HOME)/Applications/PhpStorm.app

help: ## List targets
	@awk 'BEGIN { FS = ":.*## " } /^[a-z.]+:.*## / { printf "  \033[1m%-20s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

## Build

build: ## Build build/TermGuru.app (release)
	Scripts/build.sh

debug: ## Compile only, debug configuration
	swift build

plugin: ## Build the JetBrains plugin (IDE=/path/to/IDE.app)
	Scripts/build-plugin.sh "$(IDE)"

specs: ## Re-download the Fig completion specs
	Scripts/fetch-specs.sh

icon: ## Regenerate Resources/app/AppIcon.icns from Scripts/make-icon.swift
	rm -rf build/AppIcon.iconset
	swift Scripts/make-icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o Resources/app/AppIcon.icns

clean: ## Remove build output
	rm -rf .build build

## Install

install: ## Build, install to ~/Applications, hook shells and IDEs
	Scripts/install.sh

install.replace: ## Install and comment out Figxit / Kiro CLI hooks
	Scripts/install.sh --replace-others

update: ## Install the newest release (fetch, rebuild, reinstall)
	$(TGR) update

uninstall: ## Remove shell hooks, JetBrains plugin and login item
	$(TGR) uninstall

## Run

start: ## Start the app
	$(TGR) start

stop: ## Stop the app
	$(TGR) stop

restart: ## Restart the app
	$(TGR) restart

status: ## Show app, shell and IDE connections
	$(TGR) status

doctor: ## Check the installation
	$(TGR) doctor

logs: ## Print recent log lines
	$(TGR) logs

settings: ## Open the settings window
	$(TGR) settings

rescan: ## Reload PATH commands, history and specs
	$(TGR) rescan

reset.accessibility: ## Clear the stale Accessibility grant after a rebuild, then restart
	tccutil reset Accessibility dev.termguru.app
	$(TGR) restart
	@echo "Now enable TermGuru in System Settings › Privacy & Security › Accessibility"

## Test

test: test.unit test.integration ## Run all tests

test.unit: ## Run unit tests
	swift test

test.integration: ## Drive real zsh and bash sessions against a headless app
	Tests/integration/run.sh

## Release

version: ## Print the source version and the installed one
	@echo "source    $$(cat VERSION)"
	@echo "installed $$($(TGR) --version 2>/dev/null || echo none)"

release.dry.run: ## Show what `make release` would publish
	Scripts/release.sh --dry-run

release: test ## Tag VERSION, push and create the GitHub release
	Scripts/release.sh
