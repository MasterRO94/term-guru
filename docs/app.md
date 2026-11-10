# TermGuru app

## Requirements

| Needed | Why |
| --- | --- |
| macOS 26 or newer | Liquid Glass popup |
| Xcode 26 or newer (or its command line tools) | Swift 6 toolchain and the macOS 26 SDK |
| Node.js with `npm` | Downloads the completion specs once, at build time |
| A JetBrains IDE in `/Applications` or `~/Applications` | Optional. Compiles the [caret plugin](jetbrains-plugin.md) |
| bash 4 or newer (`brew install bash`) | Optional. Only for bash; macOS ships 3.2, which is not supported |

## Build and install

There are no prebuilt binaries. On each machine:

```bash
git clone https://github.com/MasterRO94/term-guru.git
```

```bash
cd term-guru && Scripts/install.sh
```

To build a specific release, check out its tag first, for example `git checkout v0.1.0`.

`Scripts/install.sh` does the following:

1. Downloads the Fig completion specs into `Resources/specs` if they are missing (`Scripts/fetch-specs.sh`).
2. Builds `build/TermGuru.app` (`Scripts/build.sh`) and copies it to `~/Applications/TermGuru.app`.
3. Links the CLI to `~/.local/bin/tgr`. Make sure `~/.local/bin` is on your `PATH`.
4. Runs `tgr install`, which adds one line to `~/.zshrc` and `~/.bashrc`, installs the caret plugin into every JetBrains IDE config folder, adds a login item and starts the app.

Pass `--replace-others` to also comment out Figxit and Kiro CLI hooks in your shell files:

```bash
Scripts/install.sh --replace-others
```

Afterwards restart your JetBrains IDE, open a new terminal tab and run:

```bash
tgr doctor
```

### Accessibility permission

Terminal, iTerm and other non-JetBrains terminals need **System Settings › Privacy & Security › Accessibility › TermGuru**. JetBrains IDEs do not need it for the popup, but ⌘Return does (see [Keys](#keys)).

Builds are ad-hoc signed by default, so macOS ties the permission to one exact build. After every rebuild the old entry stops working even though its switch still looks on. Reset it and grant it again:

```bash
tccutil reset Accessibility dev.termguru.app
```

```bash
tgr restart
```

To keep the permission across rebuilds, sign with a stable certificate. Create a self-signed certificate of type *Code Signing* in Keychain Access (Certificate Assistant › Create a Certificate), then build with its name:

```bash
CODESIGN_IDENTITY="My Code Signing Cert" Scripts/install.sh
```

### Update

TermGuru checks the repository for a newer release tag when it starts and every 30 minutes after that. When one exists the menu bar item offers **Update to X.Y.Z…** and a notification appears; nothing is installed until you confirm. The same from a terminal:

```bash
tgr update
```

`tgr update --check` only reports the installed and the newest version.

An update runs in the checkout the app was built from (its path is recorded in the app at build time):

1. Stops if the checkout has uncommitted changes, before touching anything.
2. Fetches `origin` and fast-forwards `main` to the release tag. It never pulls, stashes or merges; a checkout that cannot fast-forward is left alone.
3. Runs `Scripts/install.sh`, with the same `CODESIGN_IDENTITY` as the previous build.
4. For ad-hoc builds, resets the stale Accessibility grant, restarts the app and asks you to enable TermGuru again.

The old app keeps running until the new build has succeeded. Each run is logged to `~/Library/Logs/TermGuru/update-<version>-<time>.log`. Turn the automatic check off in **Settings › General › Updates**.

The check reads tags over the checkout's `origin` remote, so it needs the same SSH access as `git fetch`. To update by hand instead:

```bash
git pull && Scripts/install.sh
```

Run `Scripts/fetch-specs.sh` to refresh the completion specs; the install script only downloads them when they are missing.

### Uninstall

```bash
tgr uninstall
```

This removes the shell hooks, the JetBrains plugin and the login item, and stops the app. Then delete `~/Applications/TermGuru.app`, `~/.local/bin/tgr`, `~/.config/term-guru` and `~/Library/Application Support/TermGuru`.

## Keys

While the popup shows:

| Key | Action |
| --- | --- |
| ↑ / ↓ | Select a suggestion |
| Tab | Insert the highlighted suggestion |
| Return | Insert the highlighted suggestion, or run it, depending on the setting. Runs the line as typed when the current word is empty or already matches the top suggestion and you have not moved with ↑/↓ |
| ⌘Return | Insert the highlighted suggestion and run it |
| Esc | Hide the popup until you move to another word |

⌘Return needs the Accessibility permission: terminals keep that shortcut for themselves, so TermGuru hands it to the shell as a plain Return while the popup is visible.

## Settings

Open with `tgr settings` or from the menu bar item. Stored in `~/.config/term-guru/settings.json`.

| Setting | Key in `settings.json` | Default |
| --- | --- | --- |
| Visible rows | `maxRows` | `8` |
| Show description panel | `showDetails` | `true` |
| Return on a selected suggestion: *Inserts it* / *Runs it* | `enterAction`: `insert` / `execute` | `insert` |
| Suggest commands from shell history | `historySuggestions` | `true` |

The **Aliases** tab manages `~/.config/term-guru/aliases.sh`; open shells pick up changes at their next prompt. The **Diagnostics** tab shows the same checks as `tgr doctor`.

## CLI

| Command | What it does |
| --- | --- |
| `tgr doctor` | Check the installation and print fixes |
| `tgr rescan` | Reload PATH commands, history and specs after installing new tools |
| `tgr alias add gs 'git status'` | Create an alias (`--last` uses the previous command) |
| `tgr alias` / `tgr alias rm gs` | List / remove aliases |
| `tgr settings` | Open the settings window |
| `tgr status`, `start`, `stop`, `restart`, `logs` | App control |
| `tgr specs [filter]` | List commands that have completion specs |
| `tgr complete 'git ch'` | Print suggestions without the popup |
| `tgr update` / `tgr update --check` | Install the newest release / only look for one |
| `tgr install` / `tgr uninstall` | Add or remove shell hooks, the JetBrains plugin and the login item |
| `tgr --version` | Installed version |

## Troubleshooting

Start with `tgr doctor`; it names the fix for each failed check.

| Symptom | Cause and fix |
| --- | --- |
| No popup in a terminal tab that was already open | The hook loads when a shell starts. Open a new tab |
| No popup in a JetBrains terminal | The plugin loads at IDE start. Restart the IDE; see [JetBrains plugin](jetbrains-plugin.md) |
| "Accessibility permission not granted" although the switch is on | Stale grant from an older build. See [Accessibility permission](#accessibility-permission) |
| No popup in bash | bash is older than 4. `brew install bash` |
| No popup in Warp | Not supported: Warp replaces the shell's line editor, so no shell hook can see its input |
| A newly installed command has no suggestions | `tgr rescan` |

Logs are in `~/Library/Logs/TermGuru`; `tgr logs` prints the latest lines.
