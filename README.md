*[Leia em português](README.pt-BR.md)*

# Kobixel — Aseprite extension

<img src="./kobixel.jpg" alt="Kobixel" width="600px"></img>

**Kobixel** comes from *kobo* (工房), Japanese for "workshop"/"atelier", plus
*pixel* — a workshop for your pixel art, built as an Aseprite extension.

Takes the current sprite (or the cel/selection), exports it to PNG, calls a
local image-generation CLI with your prompt, and applies the result back
into the sprite — into a new layer or replacing the current cel. All inside
a single `app.transaction`, so `Ctrl+Z` undoes everything at once.

There is exactly **one** real extension in this project: the
`kobixel-X.Y.Z.aseprite-extension`, installed inside Aseprite. Nothing
here depends on installing anything in Chrome.

## Current status

The Aseprite extension exports the PNG, runs **any external command**
configured in the dialog's "External command" field, and brings the result
back. `tools/kobixel-gemini-web/` (below) is today's default
command and the only path that uses the Gemini Pro subscription's image
quota without an API key. Other options investigated, and why they aren't
the recommendation:

| Option | Result |
|---|---|
| `tools/kobixel-gemini-web/` (Playwright + an already-logged-in Chrome) | **Recommended.** No API key, uses the Gemini Pro subscription. ~20-40s per edit. See setup below. |
| `tools/gemini_edit.py` (direct Gemini API) — **removed from the repo** | Required an API key from [AI Studio](https://aistudio.google.com/apikey) with **billing enabled** — no free tier for image models, and didn't use the Gemini Pro subscription. Removed for that reason; the code is still in git history if you need it. |
| `tools/gemini-edit.ps1` (`gemini` CLI + nanobanana extension) — **removed from the repo** | Didn't work: Google discontinued the `gemini` CLI's free login (`IneligibleTierError`), and the nanobanana extension also required its own paid API key. Removed for that reason; the code is still in git history if you need it. |
| Automation via a Claude agent (`claude --chrome -p`) | Works, but ~5min and ~US$1 of Claude subscription usage per edit — tested and discarded for cost/latency in favor of driving Playwright directly. |
| `nanobanana` / `nano-banana-cli` (third-party CLIs) | Just the field's original example — needs installing and configuring, not a ready-made solution. |

**Note**: `tools/gemini_edit.py` and `tools/gemini-edit.ps1` were removed
from this repo (both required a paid API key, and the second was already
broken). If your "External command" field still points at either one,
replace it with the `edit.mjs` command — see "The CLI" below.

**Known limitation of every path**: Nano Banana doesn't expose a real alpha
channel through any tested route (download, clipboard, or extracting via
canvas). Asking for a "transparent background" in the prompt only produces
an opaque white/checkered background. Remove the background manually in
Aseprite (magic wand) when you need transparency.

## Requirements

- **Aseprite 1.3+** — the script uses `Image:pixels()`, `app.fs`, and
  `app.transaction`.
- **Node.js 18+** and npm — to install and run the recommended
  `tools/kobixel-gemini-web` backend (Playwright).
- **Google Chrome** installed — the recommended backend attaches to a real
  Chrome window through its remote-debugging port; Chromium or another
  browser won't have your existing Google login.
- **A Google account with Gemini image generation.** Nano Banana works on
  the free tier too (a low daily quota that Google adjusts often); a Google
  AI Pro/Ultra subscription raises that quota substantially — see "Current
  status" above for why this project rides the web quota instead of paying
  per image through the API.
- **Operating system**: developed and tested primarily on **Windows**;
  `kobixel.lua` has a Linux/macOS code path too (writes a `.sh` wrapper
  instead of `.bat`), and the Chrome-launch command below is documented
  for all three. It's had less real-world testing on Linux/macOS, though —
  if you hit something that doesn't work there, please open an issue with
  what did or didn't work.

## Install the CLI first

Install `tools/kobixel-gemini-web` **before** installing the Aseprite
extension below — the extension's default "External command" expects it
to already be on your PATH.

```sh
cd tools/kobixel-gemini-web
npm install
npm install -g .
```

The second command registers a global `kobixel-gemini-web` command via
npm's own `bin` mechanism. This works the same way on Windows, macOS, and
Linux — no path to edit afterward — and is exactly what the extension's
default "External command" calls (see "The CLI" below). If you'd rather
not install it globally (e.g. while actively editing `edit.mjs`), you can
skip `npm install -g .` and use the direct `node "path/to/edit.mjs" ...`
form documented in "The CLI" instead.

Then, before each usage session (or just leave the window open), open
Chrome yourself with the debug port:

```powershell
"C:\Program Files\Google\Chrome\Application\chrome.exe" --user-data-dir="%USERPROFILE%\.kobixel\chrome-profile" --remote-debugging-port=9222 https://gemini.google.com/app
```

```sh
# Linux
google-chrome --user-data-dir="$HOME/.kobixel/chrome-profile" --remote-debugging-port=9222 https://gemini.google.com/app
```

```sh
# macOS
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --user-data-dir="$HOME/.kobixel/chrome-profile" --remote-debugging-port=9222 https://gemini.google.com/app
```

The first time, log in normally in that window. The session is saved in
that dedicated profile (separate from your everyday Chrome), so next time
it opens already logged in — but **the window needs to stay open** while
you use the plugin; the script connects to it, it doesn't open its own.

Why it isn't simpler than this: Google blocks Google-account sign-in from
a browser that automation itself opened ("This browser or app may not be
secure"), even with a real Chrome binary — it's a defense against
automated logins, not a bug. The way around it is to never let the
automation log in: you log in by hand in a Chrome window you opened, and
the script only **connects** to that already-authenticated instance.

If the script can't connect (`Could not connect to Chrome's debug port`),
it's because that window isn't open or was closed — open it again.

## Installation

1. Build the `.aseprite-extension` with the release script:
   ```powershell
   .\release.ps1
   ```
   This bumps `version` in `package.json` (patch by default), deletes old
   builds, and generates `kobixel-X.Y.Z.aseprite-extension` at the repo
   root. See "Building a new release" below for more options.
2. In Aseprite: `Edit > Preferences > Extensions` → **remove the old
   version** first (avoids caching) → `Add Extension` → pick the new
   `.aseprite-extension`.
3. Restart Aseprite. The command appears under `Edit > Kobixel...`.

On first run, Aseprite will ask permission for the script to write files
and run commands. Check the option to fully trust the script, or the
dialog will show up on every call.

## Building a new release

After editing `kobixel.lua`, run:

```powershell
.\release.ps1                # bumps the patch: 0.1.0 -> 0.1.1 (default)
.\release.ps1 -Bump minor    # 0.1.0 -> 0.2.0
.\release.ps1 -Bump major    # 0.1.0 -> 1.0.0
```

This does everything: bumps the version number in `package.json`, deletes
any old `.aseprite-extension` at the root, and builds the new zip.

**Why you must always bump the version**: Aseprite identifies the extension
by the `name` field in `package.json`, not by the filename — it only shows
an update if `version` is higher than what's installed. Reinstalling
without bumping the version looks like it does nothing, even with a really
changed `.lua` file (this is exactly the bug the script avoids).

If you'd rather do it by hand instead of using the script:
```powershell
# edit "version" in package.json by hand first
Compress-Archive -Path package.json, kobixel.lua -DestinationPath kobixel-X.Y.Z.zip -Force
Rename-Item kobixel-X.Y.Z.zip kobixel-X.Y.Z.aseprite-extension
```

## The CLI

The plugin doesn't talk to Google's API directly — it runs a shell command.
The template is editable in the dialog and accepts these placeholders:

| Placeholder | Becomes |
|---|---|
| `{input}`  | path to the PNG exported from the sprite |
| `{output}` | path where the CLI **must** write the result |
| `{prompt}` | your prompt, already escaped |
| `{width}` / `{height}` | dimensions of the sent PNG |
| `{animation}` | animation description, when "Generate 16-frame animation" is on (empty otherwise) |

Default (after following "Install the CLI first" above):

```sh
kobixel-gemini-web --in "{input}" --out "{output}" --prompt "{prompt}" --width "{width}" --height "{height}" --animation "{animation}"
```

If you'd rather not install the CLI globally (e.g. while actively editing
`edit.mjs`), point the field at the script directly instead:

```sh
node "C:\path\to\tools\kobixel-gemini-web\edit.mjs" --in "{input}" --out "{output}" --prompt "{prompt}" --width "{width}" --height "{height}" --animation "{animation}"
```

`--width`/`--height`/`--animation` are optional in both forms: `edit.mjs`
uses `--width`/`--height` to tell Gemini the real size of the PNG sent
(instead of a fixed value), and a non-empty `--animation` to switch from a
single-cell edit to filling all 16 grid cells with sequential frames of
that animation. It keeps working normally if you omit all three. Any
custom backend that wants to support the animation mode should implement
this same `--animation` flag.

Before pasting a command into the plugin's field, **test it directly in a
terminal** with any PNG — that way errors show up in the terminal instead
of in a truncated Aseprite dialog.

### PATH

`os.execute` inherits Aseprite's own process environment. If you opened
Aseprite via a graphical launcher or Steam, `PATH` probably lacks things
like `~/.local/bin`, nvm's node, or npm's global bin directory.

On Linux/macOS, the generated wrapper script already checks for the
install directory of every common Node version manager (nvm, fnm, volta,
asdf, nodenv) plus `~/.npm-global/bin`, `~/.local/bin`, `/usr/local/bin`,
and `/opt/homebrew/bin`, and adds whichever of those exist to `PATH`
before running the command — so the default `kobixel-gemini-web` normally
resolves with no extra setup, even from a GUI-launched Aseprite, and even
inside a sandboxed launcher (see the Steam note below, since that check
runs as plain shell script, not by relying on your login shell).

If you still get "command not found" (e.g. a manager not in that list, or
a custom global-prefix), **use an absolute path to the binary** in the
template instead (for the default form, that means finding where
`npm install -g` put `kobixel-gemini-web` — run `npm config get prefix` to
locate it).

If Aseprite was installed through Steam, it runs inside the **Steam Linux
Runtime container** (`pressure-vessel`), which has its own `/usr` — your
login shell and anything else under the host's `/usr` are invisible to it,
only your home directory is shared. An absolute path under `$HOME` still
works from inside it.

## Proximity factor

The "Proximity factor" slider (0-100) controls how closely the result
should resemble the original sprite, versus prioritizing what was asked in
the prompt. There's no "strength"/"denoise"-style
parameter in Gemini's API or UI for this — the slider turns into a text
instruction (in English, alongside the prompt) that changes depending on
the range:

| Range | Instruction |
|---|---|
| 90-100 | Preserve pose, proportions, composition, and silhouette; only apply the requested change. |
| 60-89 | Stay reasonably close to the original composition, but adjust details freely. |
| 30-59 | Use the drawing only as a loose reference (general shape/palette); can reinterpret significantly. |
| 0-29 | Use the drawing only as color/style inspiration; prioritize the prompt over the original composition. |

This is only text guidance for the model — it may not follow it strictly,
especially near the extremes.

## Usage tips

- **Upscale before sending**: image models work at ~1024px. Sending a raw
  32×32 PNG gives a bad result. The default (8×) sends 256×256 with nearest
  neighbor, preserving the pixel grid.
- **Frame in a 4x4 grid before sending** (on by default): confines the edit
  to a marked cell of a 16-cell (4x4) grid instead of letting the model use
  its full native canvas. Gemini/Nano Banana mostly ignores a text-only
  "use this canvas size" request and renders at its own resolution (often
  2048×2048) regardless of what was actually sent — and at that size it
  adds smooth/painterly detail that no downscale can turn back into flat
  pixel-art blocks. A visual boundary drawn into the image itself is
  respected far more reliably. Turn it off only if you're using a custom
  External command whose backend doesn't understand the marker (see
  `BASE_PIXEL_ART_INSTRUCTIONS` in `edit.mjs`) — a mismatched backend would
  otherwise get a fraction of its output silently cropped away.
- **Generate 16-frame animation**: fills all 16 grid cells with sequential
  frames of the same asset (idle, walk, run, jump, ...) instead of just one
  edit, driven by an optional "Animation description" field. Forces the 4x4
  grid on (animation can't work without it) and, on success, drops the 16
  frames onto the sprite's timeline — starting at whichever frame was active
  when you clicked Generate — inside a new Tag named after the description.
  Needs a backend that implements the optional `--animation` flag (see
  `BASE_ANIMATION_INSTRUCTIONS` in `edit.mjs`); a very high "Upscale before
  sending" combined with this mode sends a much larger image (16x the pixel
  area of a single cell) — lower the upscale slider if generation gets slow
  or low-quality.
- **Lock colors to the palette**: essential for indexed sprites and to keep
  the original palette on RGB sprites.
- **Downscale with Average** tends to beat Point when the model returns art
  with anti-aliasing; **Point** wins when it returns clean pixel art.
- Explicitly ask in the prompt: *"pixel art, {width}x{height} grid, no
  anti-aliasing, flat colors"*. Don't ask for a transparent background —
  Nano Banana doesn't return real alpha (see "Current status" above); it
  comes back with an opaque white/solid background, which you can remove
  afterward with the magic wand.

## Progress and execution

The external command runs in the background (via PowerShell's
`Start-Process` on Windows — unique filenames per run, see "Debug" below),
so it doesn't block Aseprite's UI. While it runs, a dialog shows the log's
last line and elapsed time (with a "Cancel" button to stop waiting, without
killing the process itself). `tools/kobixel-gemini-web/edit.mjs` prints step
markers (`[3/6] Uploading input image...` etc.) that show up in that
dialog — if you use a different external command, it'll only show whatever
that command itself prints to the log.

Total wait timeout: 3 minutes (`MAX_WAIT_SECONDS` in the `.lua`). If the
external command finishes without producing `{output}` — or the timeout is
exceeded — the progress dialog closes and shows the full log in an alert.

## Debug

- Log per run: `<temp>/aseprite-kobixel/kobixel-<stamp>.log` (one file per
  run — a fixed name would let a second generation corrupt the first run's
  `.bat` while it's still running in the background).
- Input/output PNGs live in the same folder (`in-*.png`, `out-*.png`) —
  Aseprite doesn't expose `os.remove`, so they aren't deleted automatically.
- Lua error console: `View > Developer Console`.
- Only one generation can run at a time (the plugin blocks a second one
  while the first hasn't finished).

## Known limitations

- Resampling is done in pure Lua, pixel by pixel. A 1024×1024 image takes a
  few seconds (this still runs synchronously, after the external command
  has already finished).
- Requires Aseprite 1.3+.
