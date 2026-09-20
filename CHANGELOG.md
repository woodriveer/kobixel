# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.5] - 2026-09-20

### Changed

- Default "Upscale before sending" factor lowered from 8x to 4x. At the
  old default, a 64x64 sprite was sent as a 512x512 PNG, and the
  generated prompt's "Use canvas size as 512x512 pixels" instruction
  looked disproportionate relative to the actual sprite size. Existing
  saved preferences are unaffected — this only changes the value new
  installs (or a "Reset to defaults") start with.

### Added

- README (English and pt-BR): Linux and macOS commands for opening Chrome
  with the remote-debugging port, alongside the existing Windows one — the
  "Install the CLI first" section previously only documented the Windows
  form.

## [0.2.4] - 2026-09-20

### Fixed

- Linux/macOS: the generated wrapper script now appends the known install
  directories of common Node version managers (nvm, fnm, volta, asdf,
  nodenv) plus `~/.npm-global/bin`, `~/.local/bin`, `/usr/local/bin`, and
  `/opt/homebrew/bin` to `PATH` before running the External command, if
  they exist. Previously the default `kobixel-gemini-web` command only
  resolved if it happened to already be on Aseprite's inherited `PATH`,
  which excludes anything a version manager adds via a shell rc file
  (Aseprite launched from a GUI icon never sources those) — most users
  installing via the documented `npm install -g .` would otherwise always
  need to hand-edit the External command field to an absolute path. This
  runs as plain `[ -d ... ]` checks inside the wrapper's own POSIX script,
  so unlike the 0.2.3 attempt (reverted below) it also works when Aseprite
  itself runs inside a sandboxed launcher (e.g. Steam's Linux Runtime
  container) where the login shell isn't reachable but `$HOME` still is.

### Changed

- README (English and pt-BR): "PATH" troubleshooting section now also
  covers Aseprite installed via Steam, which runs inside the Steam Linux
  Runtime container (`pressure-vessel`) — its own `/usr` hides the login
  shell and anything else under the host's `/usr`, but `$HOME` (and so an
  absolute path under it, e.g. nvm's install path) is still reachable.

### Reverted

- The 0.2.3 attempt to auto-resolve `PATH` by running the External command
  through `"$SHELL" -ilc` (sourcing the login shell's rc file first) turned
  out unreliable in sandboxed launchers: under the Steam Linux Runtime
  container, `$SHELL` itself (e.g. `/usr/bin/zsh`) isn't visible from
  inside the sandbox, which failed with a more confusing "command not
  found" than the original problem. Back to running the External command
  directly; use an absolute path if the bare command isn't found (see the
  README's "PATH" section).

## [0.2.3] - 2026-09-20

### Fixed (later reverted in 0.2.4, see above)

- Linux/macOS: the External command ran through `$SHELL -ilc` instead of
  directly, so it would source the user's shell rc file (`~/.bashrc`,
  `~/.zshrc`, ...) before running — the same place tools like nvm/pyenv add
  themselves to `PATH`.

## [0.2.2] - 2026-09-20

### Added

- `tools/kobixel-gemini-web/package.json` now declares a `bin` field, so
  `npm install -g .` registers a global `kobixel-gemini-web` command. The
  Aseprite extension's default "External command" is now the single,
  OS-independent `kobixel-gemini-web --in ... --out ... --prompt ...`
  (previously an absolute path to `edit.mjs` that had to be hand-edited per
  machine).
- README (English and pt-BR): new "Install the CLI first" section ordering
  the npm install steps before the Aseprite extension install steps, and
  the direct `node "path/to/edit.mjs" ...` form is now documented as an
  explicit opt-out alternative to the global install.

### Fixed

- `edit.mjs`'s direct-execution entry guard compared `import.meta.url`
  against an unresolved `process.argv[1]`. `npm install -g .` on a local
  path symlinks the package rather than copying it, and the generated bin
  shim invokes the file through that symlink — the guard silently
  evaluated false, so `main()` never ran (no output, exit 0). Fixed by
  resolving `process.argv[1]` with `fs.realpathSync()` before the
  comparison.
- `kobixel.lua`'s Windows wrapper invoked the External command bare (no
  `call`). Harmless for a plain `.exe`, but a `.bat`/`.cmd` target (any npm
  global bin, including the new default) never returns control to the
  wrapper — the "done" sentinel file was never written, so every run
  silently polled to the 3-minute timeout regardless of success or
  failure. Fixed by invoking with `call`, a documented no-op for `.exe`
  targets, so existing custom "External command" configurations are
  unaffected.
- The wrapper now appends a hint to the log when the External command
  exits non-zero ("if kobixel-gemini-web is not installed yet, run: npm
  install -g ..."), surfaced through the existing failure alert. Windows
  can't distinguish "command not found" from the CLI's own failures once
  `call` is used (it collapses cmd.exe's specific 9009 errorlevel to a
  generic 1), so the hint is worded as a suggestion rather than a
  diagnosis, and fires the same way on both Windows and POSIX shells.

## [0.2.1] - 2026-09-20

### Added

- "Requirements" section in both READMEs, consolidating what was previously
  scattered across the doc (Aseprite version, Node.js, Google Chrome, a
  Gemini-capable Google account) and clarifying that Nano Banana image
  generation also works on the free tier (lower quota) rather than
  requiring a paid Gemini Pro/Ultra subscription. Also notes the project is
  Windows-tested only, though `kobixel.lua` already has a Linux/macOS code
  path.

### Fixed

- `DEFAULTS.command` in `kobixel.lua` shipped the author's own local dev
  path (`D:\Developer\kobixel\...`) as the default "External command"
  value. Replaced with the same generic placeholder already used in the
  README examples (`C:\path\to\tools\kobixel-gemini-web\edit.mjs`).

## [0.2.0] - 2026-09-20

### Changed

- Renamed the project and extension from `repixel-ai` to `kobixel` (display
  name "Kobixel") — the old name was already established elsewhere in the
  market. Renamed the Lua script (`repixel-ai.lua` → `kobixel.lua`), the
  `package.json` `name`/`displayName`, the release artifact naming
  (`repixel-ai-X.Y.Z.aseprite-extension` → `kobixel-X.Y.Z.aseprite-extension`),
  and the external backend directory (`tools/repixel-gemini-web` →
  `tools/kobixel-gemini-web`). `package.json`'s `version` field itself resets
  to `0.1.0` (a different number from this changelog entry) so Aseprite
  treats this as a brand-new extension — existing `repixel-ai` installs
  won't auto-update; remove the old extension and install the new
  `.aseprite-extension` fresh.
- Added a README section explaining the "Kobixel" name: Japanese *kobo*
  (工房, "workshop"/"atelier") + *pixel*.

## [0.1.1] - 2026-09-14

### Changed

- Translated the dialog's UI text (labels, buttons, dropdown options, the
  "Comando externo" field) and all `repixel-ai.lua` code comments from
  Portuguese to English. Saved preferences are unaffected — they already
  stored language-neutral internal values (e.g. `"cel"`/`"sprite"`), not
  the display strings.

## [0.1.0] - 2026-09-14

First tracked release, published as the project is made open source. Version
numbering restarts at `0.1.0` here; `1.0.0` is reserved for when the
extension is shared with the wider community.

### Added

- Aseprite extension (`Edit > Repixel AI...`) that exports the current
  sprite/cel (or selection) to PNG, runs a user-configured external CLI with
  a text prompt, and pastes the result back into the sprite inside a single
  `app.transaction` (one `Ctrl+Z` undoes everything).
- Configurable "Comando externo" field with `{input}`/`{output}`/`{prompt}`/
  `{width}`/`{height}` placeholders, so any local image-generation CLI can be
  wired in.
- Recommended external backend, `tools/repixel-gemini-web/edit.mjs`: a
  Playwright script that attaches to a Chrome window the user already logged
  into, using the Gemini Pro/Ultra web subscription instead of a paid API
  key.
- "Fator de proximidade" (proximity) slider that translates into a text
  instruction controlling how closely the result should match the original
  drawing.
- Upscale-before-send and downscale-on-return controls (nearest-neighbor or
  box-average), palette snapping, and an alpha cutoff for indexed/paletted
  sprites.
- Non-blocking progress dialog while the external command runs in the
  background.
- MIT license, `CONTRIBUTING.md`, and `CODE_OF_CONDUCT.md` for open-source
  readiness.

### Changed

- Renamed the project and extension from `gemini-edit` to `repixel-ai`
  (display name "Repixel AI"), including the Lua script filename, the
  `package.json` `name`/`displayName`, the release artifact naming, and the
  external backend directory (`tools/gemini-web-edit` →
  `tools/repixel-gemini-web`).

[Unreleased]: https://github.com/woodriveer/kobixel/compare/v0.2.2...HEAD
[0.2.2]: https://github.com/woodriveer/kobixel/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/woodriveer/kobixel/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/woodriveer/kobixel/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/woodriveer/kobixel/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/woodriveer/kobixel/releases/tag/v0.1.0
