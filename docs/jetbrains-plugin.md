# TermGuru JetBrains plugin

*TermGuru Caret Bridge* (`dev.termguru.caret`) tells the TermGuru app where the terminal caret is on screen, so the popup can open next to it. It does nothing else: suggestions, keys and the popup itself belong to the [app](app.md) and the shell hooks.

JetBrains terminals do not expose the caret through the macOS Accessibility API, and macOS 27 no longer lets an app enable a hidden input method (how Fig and Kiro CLI found it), so the position has to come from inside the IDE.

## Requirements

- A JetBrains IDE, version 2025.1 or newer (PhpStorm, IntelliJ IDEA, WebStorm, …).
- The TermGuru app, installed and running.

## Install

`Scripts/install.sh` builds the plugin and installs it into every JetBrains IDE config folder it finds. Restart the IDE afterwards. `tgr doctor` lists each IDE and whether it is connected.

After installing a new IDE, or a new major version of one (each has its own plugin folder), start it once and run:

```bash
tgr install
```

## Build on its own

The plugin is compiled with the Java runtime and platform jars of an installed IDE. No Gradle, JDK or SDK download is needed.

```bash
Scripts/build-plugin.sh /Applications/PhpStorm.app
```

The result is `build/jetbrains/termguru-caret`. `Scripts/build.sh` runs this for you, trying each installed IDE until one succeeds, and bundles the plugin into `TermGuru.app`.

### Manual install

Copy the built folder into the IDE's plugin folder and restart the IDE:

```bash
cp -R build/jetbrains/termguru-caret ~/Library/Application\ Support/JetBrains/PhpStorm2026.3/plugins/
```

To remove it, delete that folder, or run `tgr uninstall` to remove it from every IDE.

## How it works

- Source: `jetbrains-plugin/src/dev/termguru/CaretBridge.java`, manifest: `jetbrains-plugin/resources/META-INF/plugin.xml`. The version is stamped from the repository's `VERSION` file at build time.
- On IDE start the plugin connects to the app's unix socket, `~/Library/Application Support/TermGuru/run/guru.sock`, and reconnects every 2 seconds if the app is not running.
- It announces itself with `{"t":"ide","pid":N}`. When the app asks `{"t":"caret?"}`, it replies with the focused component's caret rectangle: `{"t":"caret","ok":true,"terminal":true,"x":…,"y":…,"w":…,"h":…}`.
- The plugin sends nothing but that rectangle and never reads terminal contents.

## Debugging

Check the connection and a live caret reading:

```bash
tgr status
```

For a log of every caret reply, create the debug flag and restart the IDE:

```bash
touch ~/Library/Application\ Support/TermGuru/debug-caret
```

The log is written to `~/Library/Logs/TermGuru/jetbrains.log`. Delete the flag file to stop logging.

| Symptom | Fix |
| --- | --- |
| `tgr doctor` shows the plugin installed but no IDE connected | Restart the IDE; plugins load at start |
| Plugin missing after an IDE update | New IDE versions use a new config folder. Run `tgr install` |
| `Scripts/build.sh` warns that no IDE could build the plugin | No JetBrains IDE found in `/Applications` or `~/Applications`. Install one, or pass its path to `Scripts/build-plugin.sh` |
