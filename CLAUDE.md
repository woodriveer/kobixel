# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An Aseprite extension (`repixel-ai`) that sends the current sprite/cel + a text prompt to an external image-generation CLI and pastes the result back into the sprite, inside a single `app.transaction` (one `Ctrl+Z` undoes everything). The extension itself never talks to any AI API directly — it shells out to whatever command is configured in the "Comando externo" field of the dialog, templated with `{input}` `{output}` `{prompt}` `{width}` `{height}` placeholders.

There is exactly one real extension artifact: `repixel-ai-X.Y.Z.aseprite-extension`, built from `package.json` + `repixel-ai.lua`. Everything under `tools/` is an external CLI candidate for the "Comando externo" field, not part of the extension package.

The README (in Portuguese) is the source of truth for user-facing setup/usage instructions — read it for details beyond architecture (installation steps, prompt-crafting tips, known limitations). Don't duplicate its content into code comments.

`CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Add an entry under `## [Unreleased]` for any user-facing change (new option, behavior change, removed backend, etc.) in the same commit/PR that makes the change; move `Unreleased` into a new `## [X.Y.Z] - YYYY-MM-DD` section as part of the version bump described below.

## Commands

Build/release a new extension version (from repo root, PowerShell):

```powershell
.\release.ps1                # bump patch: 0.1.0 -> 0.1.1 (default)
.\release.ps1 -Bump minor    # 0.1.0 -> 0.2.0
.\release.ps1 -Bump major    # 0.1.0 -> 1.0.0
```

This bumps `version` in `package.json`, deletes old `repixel-ai-*.aseprite-extension` files, and zips `package.json` + `repixel-ai.lua` into the new `.aseprite-extension`. **Always bump the version after editing `repixel-ai.lua`** — Aseprite identifies the extension by the `name` field, not the filename, and only offers an update if `version` increased; reinstalling without bumping silently keeps the old script even though the `.lua` changed.

There is no automated test suite for the Lua side (it only runs inside Aseprite). To verify a Lua change: run `.\release.ps1`, install the resulting `.aseprite-extension` in Aseprite (`Edit > Preferences > Extensions` — remove the old version first, then `Add Extension`), restart Aseprite, and exercise `Edit > Repixel AI...` manually. The `edit.mjs` backend has a small `node --test` suite for its pure prompt-building logic — run it with `node --test tools/repixel-gemini-web/edit.test.mjs` (Node's built-in test runner, no dependency to install; the directory form `node --test tools/repixel-gemini-web` fails with `MODULE_NOT_FOUND` on Windows/Node 22 — always cite the test file directly).

For the recommended external CLI (`tools/repixel-gemini-web/`):

```sh
cd tools/repixel-gemini-web
npm install
```

Before wiring a command into the Aseprite dialog, always test it standalone in a terminal first (e.g. `node tools/repixel-gemini-web/edit.mjs --in foo.png --out out.png --prompt "..."`) — Aseprite's dialog truncates error output, so debug from the terminal instead.

## Architecture

### `repixel-ai.lua` (the extension)

Single-file Lua script, structured top-to-bottom as:

1. **System/file utilities** — temp-dir handling, shell escaping (Windows `cmd.exe` has no reliable quote-escaping, so `escapeForShell` strips shell metacharacters instead of escaping them), `{placeholder}` template substitution.
2. **Async command execution** (`runCommandAsync`) — Aseprite is single-threaded, so a blocking `os.execute` would freeze the whole UI for the 20-90s+ an image generation takes. On Windows this writes a uniquely-stamped `.bat` wrapper (stamped by timestamp+counter, because a second run could otherwise overwrite the `.bat` of a still-running first run mid-read, corrupting it) and launches it via `Start-Process` from PowerShell (not `start /B`, which reuses the caller's ephemeral console and can kill the child before it runs). The wrapper redirects output to a log file and writes an exit-code sentinel to a "done" file.
3. **Color conversion** — `toRGBA` (any sprite color mode → RGBA for export) and `toSpriteColorMode` (RGBA back → the sprite's native mode, with optional nearest-palette snapping and an alpha cutoff for transparency).
4. **Resampling** — `upscaleNearest` (nearest-neighbor upscale before sending, so image models get non-trivial resolution instead of a raw tiny sprite) and `resampleTo` (nearest-point or box-average downscale on the way back).
5. **Image I/O** (`savePNG`/`loadPNG`) — each tries the direct `Image` API first, falling back to a throwaway `Sprite` if that API path isn't available in the running Aseprite version.
6. **Main pipeline** (`run`) — captures `app.frame`/`app.layer` *at click time* (not when the background job finishes, since the user can switch frames/layers during the 30-90s wait — reading them late would silently paste the result in the wrong place); crops to the active selection if any; converts/upscales to a PNG; fires the external command asynchronously; polls via a `Timer` for the output file or a "done" sentinel, updating a non-blocking progress dialog from the log's last line; on success, calls `finalizeResult` to downscale/color-convert/paste the result inside a single `app.transaction`.
7. **Fidelity slider → text instruction** (`fidelityInstruction`) — there is no numeric "strength" parameter in any image-gen API/UI, so the 0-100 "Fator de proximidade" slider is translated into an English text instruction appended to the prompt, banded into 4 ranges (90-100 preserve pose/composition, ..., 0-29 use only as loose color/style inspiration).
8. **Dialog/config** (`showDialog`, `init`) — builds the settings UI, persists it to `plugin.preferences.cfg`, and registers the `Edit > Repixel AI...` command (`group = "file_scripts"` must match an existing group id in Aseprite's own `gui.xml`, or the command becomes invisible in all menus).

Only one generation can run at a time (`activeRun` flag) — the plugin refuses a second concurrent request.

### `tools/` (external CLI backend — wire it into the dialog's command field)

- **`tools/repixel-gemini-web/edit.mjs`** (the sole shipped backend, default in `DEFAULTS.command`) — Playwright script that *attaches* (via `chromium.connectOverCDP`) to a Chrome window the user already opened and logged into themselves (`--remote-debugging-port=9222`), rather than launching/logging in its own browser. This is a deliberate workaround: Google blocks Google-account sign-in from a browser that automation itself launched, even with a real Chrome binary. Uses the user's Gemini Pro/Ultra web quota, no API key. Extracts the generated image losslessly via `<canvas>.toDataURL` rather than the UI's download button (re-encodes as JPEG) or clipboard (flattens alpha) — canvas is the only path that preserves real pixel data, though Nano Banana itself never returns a real alpha channel regardless of extraction method. Its browser-automation entrypoint is guarded behind an `import.meta.url` check so `buildPixelArtInstructions` (the function that turns `--width`/`--height` into the canvas-size sentence sent to Gemini) can be imported and unit-tested (`edit.test.mjs`, run via `node --test tools/repixel-gemini-web/edit.test.mjs`) without connecting to Chrome.

Two alternative backends (`tools/gemini_edit.py`, a direct-API script; `tools/gemini-edit.ps1`, a `gemini` CLI + nanobanana wrapper) were removed — both required a paid API key/tier, and the `.ps1` one was already broken (Google discontinued the free `gemini` CLI login). See README.md's "Estado atual" table for the historical rationale; do not resurrect either without addressing the paid-API-key issue first.

Any new backend must implement the same `--in/--out/--prompt` contract dictated by the Lua side's `{input}/{output}/{prompt}` placeholders to drop into the same dialog field, and should accept the optional `--width`/`--height` flags (real dimensions of the sent PNG) the way `edit.mjs` does, so the model gets an accurate canvas-size instruction instead of a guess or a hardcoded value.

## Key constraints to keep in mind when editing

- `os.execute` in the Lua script inherits Aseprite's own process environment. If Aseprite was launched via a GUI launcher/Steam, `PATH` often lacks things like `~/.local/bin` or nvm's node — prefer absolute paths in example commands.
- Windows `.bat` wrapper files must stay uniquely named per run (see `stamp` in `runCommandAsync`) — do not "simplify" this back to a fixed filename.
- `package.json` must be saved without a BOM (`release.ps1` writes it via `System.Text.UTF8Encoding($false)` explicitly) — Aseprite's JSON parser fails on a BOM. Don't switch this to `Set-Content -Encoding utf8` in Windows PowerShell 5.1, which adds one back.
- Nano Banana (the image model behind all current backends) never returns a true alpha channel through any tested extraction path — don't promise transparent-background output in prompts or UI copy; document it as a manual post-step (magic wand) instead.
