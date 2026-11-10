# Changelog

All notable changes to TermGuru are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/). Every version has a matching `vX.Y.Z` tag and GitHub release.

## [Unreleased]

## [0.1.0] - 2026-11-10

### Added

- Autocomplete popup at the terminal caret with a Liquid Glass list and description panel.
- zsh and bash 4+ integration: Tab inserts, ↑/↓ select, Esc hides.
- Suggestions from Fig completion specs (subcommands, options, arguments, generators) mixed with aliases, shell history, PATH commands and files.
- JetBrains caret plugin for PhpStorm, IntelliJ IDEA and other JetBrains IDEs; Accessibility-based caret lookup for other terminals.
- Setting for Return on a selected suggestion: insert it or run it. ⌘Return always runs it.
- `tgr` CLI: `doctor`, `rescan`, `alias`, `install`, `uninstall`, `settings`, `status`, `start`, `stop`, `restart`, `logs`, `specs`, `complete`.
- Settings window (General, Aliases, Diagnostics) and menu bar item.

[Unreleased]: https://github.com/MasterRO94/term-guru/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/MasterRO94/term-guru/releases/tag/v0.1.0
