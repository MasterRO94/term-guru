# TermGuru

Fig-style autocomplete for the terminal on macOS. As you type a command, a popup opens next to the cursor with subcommands, options, arguments, files, aliases and commands from your history, each with a short description. Pick one with the arrow keys and press Tab.

It works in JetBrains IDE terminals (PhpStorm, IntelliJ IDEA, WebStorm…), Terminal and iTerm, with zsh and bash 4+.

## Fig, Kiro CLI and JetBrains terminals

[Fig](https://fig.io) made this kind of popup popular, then shut down and became Amazon Q / Kiro CLI. In JetBrains terminals, whose cursor is invisible to the macOS Accessibility API, those tools found it through a hidden input method, which macOS 27 no longer allows, so the popup stopped working there.

TermGuru differs from them in three ways:

- A small IDE plugin reports where the JetBrains terminal cursor is, so the popup opens next to it.
- It reads the same completion specs as Fig. The open-source [`@withfig/autocomplete`](https://github.com/withfig/autocomplete) specs cover hundreds of tools (`git`, `docker`, `npm`, `kubectl`, `brew`…), and you can add your own.
- It runs only on your Mac, with no account and no telemetry. The shell hook talks to the app over a local socket. The only network access is downloading specs and icons at build time and checking this repository for new releases.

## System requirements

| Requirement | Notes |
| --- | --- |
| macOS 26 (Tahoe) or newer | The popup uses Liquid Glass |
| Xcode 26 or newer, or its Command Line Tools | Swift 6 toolchain and the macOS 26 SDK. Install the tools with `xcode-select --install` |
| Node.js with `npm` | Downloads the completion specs and icons once, at build time. `brew install node` |
| zsh, or bash 4 or newer | zsh is the macOS default. The bash that ships with macOS is 3.2 and is not supported; `brew install bash` |
| Git with a GitHub SSH key | The repository is cloned over SSH, and updates are fetched the same way. See [Connecting to GitHub with SSH](https://docs.github.com/en/authentication/connecting-to-github-with-ssh); `ssh -T git@github.com` should greet you by name |
| A JetBrains IDE 2025.1 or newer | Optional. Only needed for the popup in JetBrains terminals; the plugin is built with the IDE's own runtime |

Supported terminals: JetBrains IDE terminals, Terminal and iTerm. Warp is not supported, because it replaces the shell's line editor.

## Install

There are no prebuilt downloads: TermGuru is built from source on the Mac that runs it. It takes a few minutes.

1. Clone the repository over SSH:

   ```bash
   git clone git@github.com:MasterRO94/term-guru.git ~/term-guru
   ```

2. Build and install:

   ```bash
   cd ~/term-guru && Scripts/install.sh
   ```

   This builds the app, copies it to `~/Applications/TermGuru.app`, links the `tgr` command into `~/.local/bin`, adds one line to `~/.zshrc` and `~/.bashrc`, installs the plugin into your JetBrains IDEs, adds a login item and starts the app. A TermGuru icon appears in the menu bar.

   If you used Figxit or Kiro CLI before, run `Scripts/install.sh --replace-others` instead to comment out their shell hooks.

3. **Grant Accessibility permission** (needed for Terminal and iTerm, and for ⌘Return and ⌘I everywhere): open **System Settings › Privacy & Security › Accessibility** and turn on **TermGuru**.

4. **Restart your JetBrains IDE** if you use one, so it loads the plugin.

5. Open a **new** terminal tab and check that everything is connected:

   ```bash
   tgr doctor
   ```

   Each failed check prints how to fix it.

Keep the cloned folder: the app updates itself from it.

> After every rebuild, macOS may show the Accessibility switch as on while it no longer works. Run `make reset-accessibility` and turn it on again. To avoid this, sign builds with your own certificate; see [Accessibility permission](docs/app.md#accessibility-permission).

## Use

Start typing in a terminal, for example `git ch`. The popup opens below the cursor.

| Key | Action |
| --- | --- |
| ↑ / ↓ | Select a suggestion |
| Tab | Insert the selected suggestion. With no popup, your shell's normal Tab completion runs |
| Return | Insert the selected suggestion (or run it, if you change the setting). Runs the line as typed when there is nothing to complete |
| ⌘Return | Insert the selected suggestion and run it |
| ⌘I | Move the description panel beside or below the list |
| Esc | Hide the popup until you move to the next word |

A few useful commands:

| Command | What it does |
| --- | --- |
| `tgr doctor` | Check the installation |
| `tgr settings` | Open the settings window (also in the menu bar item) |
| `tgr rescan` | Pick up newly installed tools |
| `tgr alias add gs 'git status'` | Create an alias |
| `tgr update` | Install the newest release |
| `tgr uninstall` | Remove the shell hooks, IDE plugin and login item |

Run `tgr --help` for the full list, or see [CLI](docs/app.md#cli).

## Update

The app checks this repository for new releases. When one is out, the menu bar item offers **Update to X.Y.Z…**; nothing is installed until you confirm. `tgr update` does the same from a terminal. The update fast-forwards your checkout to the release tag and rebuilds, so the checkout must have no local changes. See [Update](docs/app.md#update).

## Uninstall

```bash
tgr uninstall
```

Then delete `~/Applications/TermGuru.app`, `~/.local/bin/tgr`, `~/.config/term-guru`, `~/Library/Application Support/TermGuru` and the cloned folder.

## Documentation

- [App](docs/app.md): build details, settings, keys, all `tgr` commands, writing your own completion specs, troubleshooting
- [JetBrains plugin](docs/jetbrains-plugin.md): what it does, building and installing it, debugging
- [Releasing](docs/releasing.md): version, changelog, tags and GitHub releases
- [Changelog](CHANGELOG.md)

## For developers

`make` lists shortcuts for building, installing, restarting, testing and releasing.

Source layout:

- `Resources/shell/guru.{zsh,bash}` report the edit buffer over a unix socket and wrap Tab, Return and the arrow keys.
- `Sources/GuruCore` tokenizes the line, walks MIT-licensed Fig specs (`@withfig/autocomplete`, run in JavaScriptCore) and mixes in aliases, history, PATH commands and files.
- `Sources/GuruApp` is the menu bar app: socket server, Liquid Glass popup, settings. File, folder and tool icons come from the MIT-licensed Material Icon Theme (`Scripts/fetch-icons.sh`).
- `Sources/tgr` is the CLI.
- `jetbrains-plugin` reports the terminal caret rectangle from inside the IDE. Other terminals are read through the Accessibility API.

Tests:

```bash
swift test
```

```bash
Tests/integration/run.sh
```
