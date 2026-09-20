# Contributing to Kobixel

Thanks for taking the time to contribute. This project is a small Aseprite
extension plus an external CLI backend — the notes below should be enough to
get a change from idea to merged PR.

## Project layout

Read [`CLAUDE.md`](CLAUDE.md) first — it's the up-to-date architecture
reference (how `kobixel.lua` is structured, why the Windows async
execution path looks the way it does, the `{input}/{output}/{prompt}`
contract external backends must implement, etc.). This file only covers the
contribution *process*; `CLAUDE.md` covers the *code*.

In short:

- `kobixel.lua` + `package.json` → the actual Aseprite extension.
- `tools/kobixel-gemini-web/` → the recommended external CLI backend
  (Playwright, attaches to a Chrome window you already logged into).
- `README.md` (English) / `README.pt-BR.md` (Portuguese) → user-facing
  setup and usage docs.

## Before you start

- **Bug fixes / small changes**: open a pull request directly, no need to
  file an issue first.
- **New features or behavior changes**: please open an issue first to
  discuss the approach. This project intentionally has a narrow scope (see
  "Estado atual" / "Current state" in the README) — some things that look
  like obvious additions (e.g. a new backend requiring a paid API key) have
  already been tried and reverted for documented reasons.
- **New external CLI backends**: must implement the same `--in/--out/--prompt`
  contract as `edit.mjs` (see `CLAUDE.md`) to drop into the "Comando
  externo" field, and should accept optional `--width`/`--height`.

## Making changes

### `kobixel.lua`

There's no automated test suite for the Lua side — it only runs inside
Aseprite. To verify a change:

```powershell
.\release.ps1
```

Then in Aseprite: `Edit > Preferences > Extensions` → remove the old
version first → `Add Extension` → pick the new `.aseprite-extension` →
restart Aseprite → exercise `Edit > Kobixel...` manually.

**Always bump the version** (`release.ps1` does this for you, patch by
default) after editing `kobixel.lua` — Aseprite only offers an update
when `version` increases, so reinstalling without bumping silently keeps the
old script.

### `tools/kobixel-gemini-web/edit.mjs`

```sh
cd tools/kobixel-gemini-web
npm install
node --test tools/kobixel-gemini-web/edit.test.mjs
```

(Run the test file directly — the directory form `node --test
tools/kobixel-gemini-web` fails with `MODULE_NOT_FOUND` on Windows/Node 22.)

Before wiring a command change into the Aseprite dialog, test it standalone
in a terminal first (`node tools/kobixel-gemini-web/edit.mjs --in foo.png
--out out.png --prompt "..."`) — Aseprite's dialog truncates error output.

### Documentation

If you change user-facing behavior, update **both** `README.md` (Portuguese)
and `README.en-US.md` (English) — they're meant to stay in sync. If you
change architecture, update `CLAUDE.md` too.

## Commit messages

This repo uses [Conventional Commits](https://www.conventionalcommits.org/)
(`feat:`, `fix:`, `docs:`, `chore:`, `test:`, `refactor:`, optionally scoped
like `fix(edit.mjs): ...`). Look at `git log` for examples. One logical
change per commit.

## Pull requests

- Keep PRs focused — one change per PR is easier to review and revert if
  needed.
- Describe what you tested and how (Aseprite version, OS, which backend).
- Link the related issue if there is one.
- Be patient — this is maintained on a best-effort basis.

## Code of Conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md). By
participating, you're expected to uphold it.
