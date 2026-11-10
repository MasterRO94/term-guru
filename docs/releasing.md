# Releasing

TermGuru ships as source. A release is a version number, a changelog section, a git tag and a GitHub release; no binaries are attached.

## Version

The `VERSION` file at the repository root is the only place the version is written. `Scripts/build.sh` stamps it into the app's `Info.plist` and the JetBrains plugin's `plugin.xml`, and `tgr --version` reads it from the installed app.

Versions follow [Semantic Versioning](https://semver.org/): patch for fixes, minor for new features, major for breaking changes to settings, the CLI or the shell protocol.

## Changelog

Add every user-visible change to the `## [Unreleased]` section of [CHANGELOG.md](../CHANGELOG.md) in the same commit as the change, under *Added*, *Changed*, *Fixed* or *Removed*.

## Cutting a release

1. Set the new number in `VERSION`.
2. In `CHANGELOG.md`, rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD`, add a fresh empty `## [Unreleased]` above it and update the links at the bottom.
3. Run the tests: `swift test` and `Tests/integration/run.sh`.
4. Commit, for example `Release X.Y.Z`.
5. Preview, then publish:

```bash
Scripts/release.sh --dry-run
```

```bash
Scripts/release.sh
```

`make release` runs the tests first and then the same script.

`Scripts/release.sh` refuses to run with uncommitted changes, an existing tag or an empty changelog section. It creates the annotated tag `vX.Y.Z`, pushes the current branch and the tag to `origin`, and creates the GitHub release with that version's changelog section as its notes. It needs the [GitHub CLI](https://cli.github.com) signed in (`gh auth status`).

## What a release triggers

The pushed `vX.Y.Z` tag is the update signal. Every installed app compares the highest such tag on `origin` with its own version and offers the update, so tag only commits that build and whose `VERSION` matches the tag: the updater fast-forwards to the tag and refuses an install that reports an older version. The GitHub release is for people; the app does not read it.
