# Prompt Context Fix, Backend Cleanup & English README Specification

## Problem Statement

The Aseprite extension's dialog exposes nine input parameters, and `gemini-edit.lua` computes `{width}`/`{height}` placeholders for the external-command template — but only `prompt` and `fidelity` actually reach the text sent to the image-generation backend. `edit.mjs` hardcodes an unrelated "Use canvas size as 256x256 pixels" instruction regardless of the real upscaled image size, and it doesn't accept `--width`/`--height` at all, so the computed dimensions are silently dropped. Separately, the repo carries two alternative backends (`tools/gemini_edit.py`, `tools/gemini-edit.ps1`) that both require a paid API key or tier and, in the `.ps1` case, are already broken upstream — contradicting the project's own stated goal (README "Estado atual": use the Gemini Pro/Ultra subscription quota, no API key) and creating doubt about what's actually in use. README.md also exists only in pt-BR, blocking English-speaking users/contributors.

## Goals

- [ ] The one remaining, shipped backend (`edit.mjs`) receives and uses the real image dimensions in its prompt text, verified by inspecting the string built before it's sent to the model.
- [ ] `tools/gemini_edit.py` and `tools/gemini-edit.ps1` are removed from the repo (both require a paid API key/tier, and the `.ps1` path is already broken), and every doc that references them (`README.md`, `CLAUDE.md`) is updated so nothing describes a script that no longer exists.
- [ ] English-speaking users have a `README.en-US.md` with full parity to `README.md`, discoverable from both files.

## Out of Scope

| Feature | Reason |
| ------- | ------ |
| New dialog controls (e.g. a checkbox to toggle sending width/height) | Always-on; no UI surface needed for this fix |
| Sending `source`/`target`/`resample`/`snapPalette`/`alphaCut`/`upscale` as prompt text | Mechanical/local parameters (export selection, post-processing after the model responds) — confirmed out of scope by the user |
| Building a replacement paid-API or CLI-based backend | Not being replaced — the subscription-based `edit.mjs` path is now the only shipped backend |
| Automatically migrating a user's existing "Comando externo" field if it references a removed script | Stored in Aseprite's own `plugin.preferences`, outside this repo — cannot be edited by this refactor; documented as a breaking change instead (see CTX-05) |
| Localizing dialog UI strings or error messages | Only `README.md` is being localized |
| Adding an automated test framework | None exists (Lua only runs inside Aseprite); verification stays manual/scripted CLI checks, consistent with current project convention |
| Changing Gemini API auth, model wiring, or the browser-login flow for `edit.mjs` | Unrelated to prompt-context or the backend cleanup |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --------------------- | --------------- | --------- | ---------- |
| README structure for en-US | Separate file `README.en-US.md`, cross-linked via a one-line language-switcher at the top of both files | Matches common OSS convention; avoids fragile in-file toggling | y |
| Scope of "adding context" | Only image dimensions (width/height); the other five mechanical params stay local-only | User confirmed: they describe file plumbing/post-processing, not desired visual outcome | y |
| `tools/gemini_edit.py` disposition | Delete the file entirely | User: "remover se for para usar api paga" — it requires a paid, billing-enabled API key with no free tier for image models | y |
| `tools/gemini-edit.ps1` disposition | Delete the file entirely | User: same logic applies — it needs a paid nanobanana API key and is already broken (Google discontinued the free `gemini` CLI login) | y |
| README's existing comparison table (the "options investigated and why not" table in "Estado atual") | Keep the table as historical rationale, but mark the `gemini_edit.py`/`gemini-edit.ps1` rows as **removed from the repo**, not just "not recommended" | Preserves the decision context (why paid/CLI paths were rejected) for future readers without leaving docs pointing at files that no longer exist | y |
| Existing users whose "Comando externo" still points at a deleted script | Not migrated automatically (see Out of Scope); README gets an explicit note that these two paths were removed and `edit.mjs` is the replacement | Their custom command lives in Aseprite's own preferences storage, outside this repo's reach | y |

**Open questions:** none — all resolved above.

---

## User Stories

### P1: `edit.mjs` prompt reflects actual image dimensions ⭐ MVP

**User Story**: As a user who adjusts the "Ampliar antes de enviar" (upscale) slider, I want the text sent to the image model to state the real width/height of the image I'm sending, so the model isn't given a false/mismatched canvas-size claim.

**Why P1**: Factual bug — `edit.mjs` always claims "256x256" even when the actually-sent image is a different size (e.g. a 64×64 sprite at the default 8× upscale sends 512×512).

**Acceptance Criteria**:

1. WHEN `gemini-edit.lua` builds the command from `DEFAULTS.command` THEN the system SHALL include the `{width}` and `{height}` placeholders in that template, filled with the real sent-image pixel dimensions (`sent.width`/`sent.height`, already computed in `run()`).
2. WHEN `edit.mjs` receives `--width` and `--height` arguments THEN the system SHALL include those exact integer values in the text typed into the Gemini prompt box, replacing the hardcoded string "Use canvas size as 256x256 pixels".
3. IF `edit.mjs` is invoked without `--width` or without `--height` THEN the system SHALL omit the canvas-size sentence entirely rather than falling back to the old fixed "256x256" claim, and SHALL NOT exit with an error.

**Independent Test**: Extract `edit.mjs`'s prompt-building logic into a directly callable function and invoke it with (a) `width=512 height=512` — assert the resulting string contains `"512x512"` and not `"256x256"`; (b) neither argument — assert the string contains no digit-based canvas-size claim and the call does not throw.

---

### P1: Remove paid/broken alternative backends and correct docs

**User Story**: As a maintainer, I want backends that require a paid API key or are already broken removed from the repo, so the project only ships what actually works at no extra cost, and no doc references a script that doesn't exist.

**Why P1**: Directly requested — both `tools/gemini_edit.py` (paid, billing-enabled API key, no free tier for image models) and `tools/gemini-edit.ps1` (paid nanobanana key, and already broken since Google discontinued free `gemini` CLI login) contradict the project's stated no-API-key goal.

**Acceptance Criteria**:

1. The system SHALL delete `tools/gemini_edit.py` and `tools/gemini-edit.ps1` from the repository.
2. WHEN `README.md`'s "Estado atual" comparison table is updated THEN the system SHALL retain the investigated-alternatives rationale (why the paid-API and CLI paths were rejected) but mark both rows as **removed from the repo**, not merely "not recommended".
3. The system SHALL remove the `### tools/gemini_edit.py` and `### tools/gemini-edit.ps1` subsections (setup instructions, usage examples) from `README.md`.
4. The system SHALL update `CLAUDE.md`'s Architecture section so it no longer describes `tools/gemini_edit.py` or `tools/gemini-edit.ps1` as active backends, reflecting `tools/gemini-web-edit/edit.mjs` as the sole shipped backend.
5. WHEN README.md is updated THEN the system SHALL add an explicit note that these two paths were removed and that a "Comando externo" field still pointing at either one must be replaced with the `edit.mjs` command.

**Independent Test**: Confirm `tools/gemini_edit.py` and `tools/gemini-edit.ps1` no longer exist on disk; grep the repo (excluding `.git`) for `gemini_edit.py` and `gemini-edit.ps1` and confirm every remaining hit is inside the historical-rationale note, not an install/usage instruction.

---

### P2: English README parity

**User Story**: As an English-speaking user/contributor, I want a `README.en-US.md` with the same content as the (now cleaned-up) `README.md`, so I can install and use the extension without reading Portuguese.

**Why P2**: Explicitly requested but not blocking the P1 fixes; ships independently, after the pt-BR content is finalized.

**Acceptance Criteria**:

1. The system SHALL provide `README.en-US.md` containing an English translation of every section present in the post-cleanup `README.md` (Estado atual, Instalação, Gerando uma nova release, O CLI + the single remaining `tools/gemini-web-edit` subsection, Fator de proximidade, Dicas de uso, Progresso e execução, Debug, Limitações conhecidas).
2. WHEN a reader opens either `README.md` or `README.en-US.md` THEN the system SHALL show a one-line language-switcher link at the very top pointing to the other file.
3. WHEN `README.en-US.md` documents the external-command placeholder table THEN the system SHALL describe `{width}`/`{height}` per the corrected, post-fix behavior (real dimensions, now consumed by `edit.mjs`) and SHALL NOT document `gemini_edit.py` or `gemini-edit.ps1` as available options.

**Independent Test**: Open `README.en-US.md`, follow the language-switcher link to `README.md` and back; diff section headers between both files to confirm 1:1 coverage; confirm neither removed script is mentioned as an available option.

---

## Edge Cases

- IF a user has a hand-edited "Comando externo" template that already references `{width}`/`{height}` pointed at `edit.mjs` THEN the system SHALL continue to work unchanged (the flags are additive/optional).
- IF a user's custom command targets the now-deleted `gemini_edit.py` or `gemini-edit.ps1` THEN it SHALL fail at execution (file not found) — this is an accepted, documented breaking change (see CTX-05), not something this refactor auto-fixes.
- WHEN width/height values are passed THEN the system SHALL treat them as plain integers (Lua's `tostring(sent.width)` never produces fractional or unit-suffixed values) — no parsing/rounding logic needed in `edit.mjs`.
- IF `--width`/`--height` are passed but non-numeric (a hand-edited command with a typo) THEN the system SHALL NOT crash; the value is only interpolated into a text sentence, never parsed as a number.

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| --------------- | ----------------------------------------- | ------ | ------- |
| CTX-01 | P1: edit.mjs reflects actual dimensions | Verify | ✅ Verified |
| CTX-02 | P1: edit.mjs reflects actual dimensions | Verify | ⚠️ Needs Fix — see `validation.md` (discrimination sensor found the `width && height` boundary case untested) |
| CTX-03 | P1: Remove paid/broken backends | Verify | ✅ Verified |
| CTX-04 | P1: Remove paid/broken backends | Verify | ✅ Verified |
| CTX-05 | P1: Remove paid/broken backends | Verify | ✅ Verified |
| DOC-01 | P2: English README parity | Verify | ✅ Verified |
| DOC-02 | P2: English README parity | Verify | ✅ Verified |

**ID format:** `[CATEGORY]-[NUMBER]` — `CTX` = prompt-context fix + backend cleanup, `DOC` = documentation/i18n.

**Status values:** Pending → In Design → In Tasks → Implementing → Verified

**Coverage:** 7 total, 6 Verified, 1 Needs Fix — see `.specs/features/prompt-context-audit-i18n/validation.md` for full evidence.

---

## Success Criteria

- [ ] Invoking `edit.mjs`'s prompt-building logic with `--width`/`--height` produces a string containing the real dimensions; omitting them produces a string with no size claim at all (never the stale "256x256").
- [ ] `tools/gemini_edit.py` and `tools/gemini-edit.ps1` no longer exist; `README.md` and `CLAUDE.md` contain no install/usage instructions for either, only the historical rationale note.
- [ ] `README.en-US.md` exists, covers every post-cleanup pt-BR section, and both files cross-link via a language switcher.
