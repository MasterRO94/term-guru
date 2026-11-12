# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

TermGuru is a Fig-style terminal autocomplete popup for macOS 26+ (Swift 6 toolchain, SwiftPM, no Xcode project). Shipped as source only: users build it on their own Mac. User docs live in `docs/app.md`, `docs/jetbrains-plugin.md`, `docs/releasing.md`.

## Commands

`make` lists all targets. The ones that matter while developing:

| Task | Command |
| --- | --- |
| Compile (debug) | `swift build` |
| Full app bundle `build/TermGuru.app` | `Scripts/build.sh` (fetches specs/icons via npm if missing) |
| Build + install + restart installed app | `Scripts/install.sh` |
| Unit tests | `swift test` |
| One suite / one test (Swift Testing) | `swift test --filter TokenizerTests` / `swift test --filter "TokenizerTests/handlesQuotesAndEscapes"` |
| Integration tests (real zsh/bash in a pty) | `Tests/integration/run.sh` |
| Query the engine without the popup | `.build/debug/tgr complete 'git ch'` (`--icons` shows icon per row) |
| Regenerate `tgr.js` spec only | `swift build && .build/debug/tgr --experimental-dump-help \| .build/debug/tgr _fig-spec > Resources/specs/tgr.js` |
| JetBrains plugin only | `Scripts/build-plugin.sh /Applications/PhpStorm.app` |

`Resources/specs/` and `Resources/icons/` are gitignored and downloaded by `Scripts/fetch-specs.sh` / `Scripts/fetch-icons.sh`; never edit them by hand. After rebuilding and reinstalling, ad-hoc signing invalidates the Accessibility grant: `make reset.accessibility`.

## Architecture

Four pieces talk over one unix socket, `~/Library/Application Support/TermGuru/run/guru.sock` (`GuruPaths.socket`):

- **Shell hooks** (`Resources/shell/guru.zsh`, `guru.bash`) send the edit buffer on every redraw and wrap Tab, Return, arrows and Esc. While the popup is visible, a key is forwarded as `K<name>` and the hook blocks briefly for the app's answer.
- **App** (`Sources/GuruApp`, menu bar, AppKit + SwiftUI). `Coordinator` owns the socket server, one `ShellSession` per connection, the popup, the key tap and updates. Engine work runs on a single serial `engineQueue`; results are dropped unless `generation` still matches, so stale suggestions never open the popup.
- **Core** (`Sources/GuruCore`, everything testable). `Engine.suggest` tokenizes the line left of the cursor (`Tokenizer`), walks Fig specs executed in JavaScriptCore (`Specs/SpecRuntime`, `SpecModel`), and merges aliases, history, PATH executables and files (`Personal/`). `Engine` is not thread-safe.
- **CLI** (`Sources/tgr`, swift-argument-parser) controls the app by sending `C` commands on the same socket, and installs/uninstalls hooks (`Installer`), runs `Doctor` and the updater (`Update/`).
- **JetBrains plugin** (`jetbrains-plugin/`, plain Java compiled with an installed IDE's JBR, no Gradle) speaks JSON lines (`{"t":"ide"}`, `{"t":"caret"}`) to report the terminal caret rect. Other terminals use the Accessibility API (`CaretLocator`).

### Shell wire protocol

Line-based, fields split by `\x1f`, embedded newlines sent as `\x1e` (`Wire`). Lines starting with `{` are JSON (IDE plugin). Shell → app: `H` hello (pid, shell, PATH), `A` aliases, `E` edit (cursor, cwd, buffer), `K` key, `X`/`L` hide / new line, `C` CLI command. App → shell: `V` visible 0/1, `I`/`R` insert / insert-and-run (replace count, text, cursor-back), `N` key consumed, `P` pass key through to the shell's own binding. Changing this protocol is a breaking change (major version) and must be mirrored in both hooks.

### Resources and specs

`GuruResources.root` resolves to the app bundle's `Contents/Resources`, else `$GURU_RESOURCES`, else `./Resources` relative to the CWD (so run dev binaries from the repo root). Spec lookup order: `~/.config/term-guru/specs` → `Resources/custom-specs` (tracked) → `Resources/specs` (fetched + generated `tgr.js`, `icons.json`). New `tgr` arguments get suggestion values through `completion:` kinds in `Sources/tgr/main.swift`.

### Test isolation env vars

`GURU_SOCKET`, `GURU_CONFIG`, `GURU_RESOURCES` redirect paths; `GURU_HEADLESS=1` runs the app without status item, updates or the foreground-app check. `Tests/integration/run.sh` uses all of them to drive a private app instance, so it never touches the installed one. Unit tests (`Tests/GuruCoreTests`, Swift Testing `@Suite`/`@Test`) build a `Sandbox` with inline specs in a temp dir.

## Conventions

- `VERSION` is the only place the version is written; `Scripts/build.sh` stamps it into `Info.plist` and `plugin.xml`.
- Every user-visible change goes into `## [Unreleased]` in `CHANGELOG.md` (Keep a Changelog: Added/Changed/Fixed/Removed) in the same commit.
- Release: `Scripts/release.sh --dry-run`, then `Scripts/release.sh` (see `docs/releasing.md`). Installed apps update by fast-forwarding their checkout to the highest `vX.Y.Z` tag, so only tag commits that build and whose `VERSION` matches.
- Docs use SSH clone URLs (`git@github.com:MasterRO94/term-guru.git`), never HTTPS.
- Package uses Swift 6 tools with `swiftLanguageModes: [.v5]`.

## Writing style

Write clear, direct, specific prose. Avoid these AI writing patterns:

- Eyebrow headings: Don't add category labels above headings.
- Decorative numbering: Only number sections when order matters.
- Rhythmic or contrasting titles: Avoid formulas like "Hard to describe. Easy to recognize."
- Metaphorical headings: Prefer literal descriptions over personification or clever imagery.
- Slogans and clichés: Avoid phrases like "Built for teams that ship" or "Unlock your potential."
- Vague headings: Replace "A closer look" or "Why it matters" with specific descriptions.

### Principles

- Write headings like email subject lines, not movie trailers.
- Prefer information over cleverness.
- Don't manufacture rhythm, drama, or contrast.
- Be concrete enough that the copy couldn't describe any product.
- Let interesting facts speak for themselves.
- Sound like a thoughtful human, not a marketing department.
