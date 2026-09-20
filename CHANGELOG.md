# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/woodriveer/kobixel/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/woodriveer/kobixel/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/woodriveer/kobixel/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/woodriveer/kobixel/releases/tag/v0.1.0
