# TermGuru

Fig-style autocomplete popup for the terminal on macOS. Works in JetBrains IDE terminals (PhpStorm, IntelliJ IDEA…), Terminal and iTerm, with zsh and bash 4+.

TermGuru is distributed as source only: you build it on the machine that runs it.

```bash
git clone git@github.com:MasterRO94/term-guru.git
cd term-guru
Scripts/install.sh
```

`make` lists shortcuts for building, installing, restarting, testing and releasing.

## Documentation

- [App](docs/app.md) — requirements, building on a new machine, settings, keys, `tgr` CLI, troubleshooting
- [JetBrains plugin](docs/jetbrains-plugin.md) — what it does, building and installing it, debugging
- [Releasing](docs/releasing.md) — version, changelog, tags and GitHub releases
- [Changelog](CHANGELOG.md)

## How it works

- `Resources/shell/guru.{zsh,bash}` report the edit buffer over a unix socket and wrap Tab, Return and the arrow keys.
- `Sources/GuruCore` tokenizes the line, walks MIT-licensed Fig specs (`@withfig/autocomplete`, run in JavaScriptCore) and mixes in aliases, history, PATH commands and files.
- `Sources/GuruApp` is the menu bar app: socket server, Liquid Glass popup, settings.
- `Sources/tgr` is the CLI.
- `jetbrains-plugin` reports the terminal caret rectangle from inside the IDE. Other terminals are read through the Accessibility API.

## Tests

```bash
swift test
```

```bash
Tests/integration/run.sh
```
