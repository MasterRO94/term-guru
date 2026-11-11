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
2. Builds `build/TermGuru.app` (`Scripts/build.sh`), generating the `tgr` spec from the CLI itself, and copies it to `~/Applications/TermGuru.app`.
3. Links the CLI to `~/.local/bin/tgr`.
4. Runs `tgr install`, which adds one line to `~/.zshrc` and `~/.bashrc` (it puts `~/.local/bin` on `PATH` when missing, then loads the hook; an older TermGuru line is replaced in place), installs the caret plugin into every JetBrains IDE config folder, adds a login item and starts the app.

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
| Tab | Insert the highlighted suggestion. With no popup, the shell's own completion runs |
| Return | Insert the highlighted suggestion, or run it, depending on the setting. Runs the line as typed when the current word is empty or already matches the top suggestion and you have not moved with ↑/↓ |
| ⌘Return | Insert the highlighted suggestion and run it |
| ⌘I | Show the description beside or below the list. The choice is saved |
| Esc | Hide the popup until you move to another word. In vi mode it also switches to command mode, in the same press |

⌘Return and ⌘I need the Accessibility permission: terminals keep those shortcuts for themselves (Terminal and iTerm open an inspector on ⌘I), so TermGuru takes them over only while the popup is visible. ⌘Return reaches the shell as a plain Return; ⌘I never reaches the terminal.

Rows show the spec's own icon when it has one (emoji, `fig://icon` types and `fig://template` badges) and a file-type icon for files and folders, otherwise a symbol for the kind of suggestion. Icons that specs load from the web are never fetched.

In vi mode (`bindkey -v` in zsh, `set -o vi` in bash) the popup works in insert mode and hides in command mode. zsh waits only 100 ms for Esc while the popup shows, if `KEYTIMEOUT` is at its default; a value you set yourself is kept. bash waits for readline's `keyseq-timeout` (500 ms by default) before it acts on Esc. In bash's emacs mode Esc is left alone, because it starts every Meta and arrow key there, so it does not hide the popup.

After a redirection (`>`, `>>`, `<`, `2>`, `&>` and the like) the popup lists files, whatever the command is. Heredocs (`<<`), here-strings (`<<<`) and fd copies (`2>&1`) get no suggestions.

## Settings

Open with `tgr settings` or from the menu bar item. Stored in `~/.config/term-guru/settings.json`.

| Setting | Key in `settings.json` | Default |
| --- | --- | --- |
| Visible rows | `maxRows` | `8` |
| Show description panel | `showDetails` | `true` |
| Description panel: *Beside the list* / *Below the list* (⌘I switches it) | `detailsPosition`: `side` / `below` | `side` |
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
| `tgr specs [filter]` | List commands that have completion specs (`--source` shows where each loads from) |
| `tgr complete 'git ch'` | Print suggestions without the popup |
| `tgr update` / `tgr update --check` | Install the newest release / only look for one |
| `tgr install` / `tgr uninstall` | Add or remove shell hooks, the JetBrains plugin and the login item |
| `tgr --version` | Installed version |

## Completion specs

Suggestions for a command's arguments come from [Fig completion specs](https://fig.io/docs/reference/subcommand): one compiled JavaScript file per command, named after it (`git.js` for `git`). TermGuru looks in three directories and uses the first file it finds:

| Directory | Holds | Tracked |
| --- | --- | --- |
| `~/.config/term-guru/specs` | Your own specs. Overrides everything below | — |
| `Resources/custom-specs` | Hand-written specs that ship with TermGuru | yes |
| `Resources/specs` | Fig specs from `@withfig/autocomplete`, plus `tgr.js` generated at build time | no |

In the installed app the last two live in `TermGuru.app/Contents/Resources`. `Scripts/fetch-specs.sh` replaces `Resources/specs` entirely, so never edit it by hand.

### Write a spec

Create `~/.config/term-guru/specs/<command>.js`, run `tgr rescan`, and check it with `tgr complete '<command> '`. No rebuild is needed:

```js
var spec = {
  name: "deploy",
  description: "Ship the current branch",
  subcommands: [
    { name: "staging", description: "Deploy to staging" },
    { name: "prod", description: "Deploy to production",
      options: [{ name: ["-f", "--force"], description: "Skip checks" }] },
  ],
  options: [{ name: "--env", args: { name: "file", template: "filepaths" } }],
  args: {
    name: "service",
    generators: { script: ["sh", "-c", "ls services"], splitOn: "\n" },
  },
};
export{spec as default};
```

The file must be plain JavaScript without imports, ending in `export default spec;` or `export{spec as default}`. Fig's TypeScript specs compile to this with `esbuild --format=esm`. Generators (`script`, `postProcess`, `custom`, `generateSpec`) run in JavaScriptCore; their shell commands time out after 2 seconds, or the generator's `timeout` up to 3.

Other Fig fields TermGuru reads:

| Field | Effect |
| --- | --- |
| `exclusiveOn`, `dependsOn` on an option | Hidden while a conflicting option is on the line / until one of the listed options is. Any alias of a used option counts |
| `trigger` on a generator | A string, a `(newToken, oldToken) => boolean` function, `{on: "change"}` or `{on: "threshold", length}`. While it does not fire, the last results are filtered as you type |
| `cache` on a generator | `ttl` in milliseconds and `strategy: "stale-while-revalidate"`, which shows the cached results at once and refreshes them in the background. Without `cache`, results live 5 seconds. They are always kept per folder |
| `filterTemplateSuggestions` | Filters and reprioritizes the files and folders of the generator's `template` |
| `template: "help"` / `"history"` | The sibling subcommands (for `help <command>`) / words used after the same command in your shell history |
| `icon` | See [Keys](#keys) |

To ship a spec with TermGuru instead, put the same file in `Resources/custom-specs` and rebuild.

### The `tgr` spec

`Scripts/build.sh` writes `Resources/specs/tgr.js` from the CLI's own argument definitions, so new `tgr` subcommands, options and help texts appear in suggestions after the next build. To suggest values for an argument, give it a completion kind in `Sources/tgr/main.swift`:

| `completion:` | Suggests |
| --- | --- |
| `.list(["zsh", "bash"])` | Those values |
| `.file()` / `.directory` | Files and folders / folders only |
| `.shellCommand("tgr alias list --names")` | One suggestion per line of the command's output |

`CaseIterable` enum arguments list their cases without a completion kind. Hidden commands and options (`shouldDisplay: false`, `help: .hidden`) are left out.

To regenerate it without a full build:

```bash
swift build && .build/debug/tgr --experimental-dump-help | .build/debug/tgr _fig-spec > Resources/specs/tgr.js
```

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
| Tab does not reach compinit or fzf-tab | It does whenever the popup is hidden or empty. The order of the TermGuru line, `compinit` and fzf-tab in `.zshrc` does not matter: the hook wraps Tab again at every prompt and calls the widget it found |

Logs are in `~/Library/Logs/TermGuru`; `tgr logs` prints the latest lines.
