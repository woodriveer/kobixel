# Prompt Context Fix, Backend Cleanup & English README Tasks

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill: **activate it by name and follow its Execute flow and Critical Rules.** Do not search for skill files by filesystem path. The skill is the source of truth for the full flow (per-task cycle, sub-agent delegation, adequacy review, Verifier, discrimination sensor).

**If the skill cannot be activated, STOP and tell the user - do not proceed without it.**

---

**Spec**: `.specs/features/prompt-context-audit-i18n/spec.md`
**Status**: Draft

---

## Test Coverage Matrix

> Generated from codebase sampling (no existing test files anywhere in the repo, no test-runner config, no CI). No project quality/testing guideline files found (no `AGENTS.md`, `CONTRIBUTING.md`, no CI workflows, no linter config). User confirmed approach: extract `edit.mjs`'s prompt-building logic into a pure function and cover it with Node's built-in test runner (`node --test`) — no new dependency added, consistent with the project's existing no-framework convention. Everything else (Lua, file removal, docs) has no runtime to test against and is verified by manual read/grep, matching the project's documented convention ("no automated test suite... verification stays manual").

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| ---------- | ------------------- | --------------------- | ----------------- | ------------ |
| `edit.mjs` prompt-building function (pure, extracted) | unit | 1:1 to CTX-02: with both dims present → contains the real `WxH`; with either dim missing → no digit-based size clause at all | `tools/gemini-web-edit/*.test.mjs` | `node --test tools/gemini-web-edit` |
| `gemini-edit.lua` (`DEFAULTS.command` template) | none | Build gate only — no Lua interpreter available outside Aseprite itself | `gemini-edit.lua` | manual read/trace |
| File removal (`gemini_edit.py`, `gemini-edit.ps1`) | none | Build gate only — existence check | `tools/` | `ls tools/gemini_edit.py tools/gemini-edit.ps1` (expect "No such file or directory") |
| Documentation (`README.md`, `README.en-US.md`, `CLAUDE.md`) | none | Build gate only — grep/read verification, section-header parity for the two READMEs | `*.md` | `grep -rn` + manual header diff |

## Gate Check Commands

> Generated from codebase - confirm before Execute.

| Gate Level | When to Use | Command |
| ---------- | ----------- | ------- |
| Quick | After T1 (unit test on the extracted prompt-building function) | `node --test tools/gemini-web-edit` |
| Build | After every Lua/removal/doc task (T2-T8) | Task-specific manual check listed in that task's `Done when` (grep for stale references / `ls` for absence / header diff) |

---

## Execution Plan

Phases are ordered and run sequentially - each phase completes before the next begins, and tasks within a phase execute in order.

### Phase 1: Backend prompt-context fix

```
T1 ------→ T2
```

### Phase 2: Remove paid/broken backends

```
T3
T4
```

(T3 and T4 are independent of each other - no dependency edge between them - executed one after the other only because tasks within a phase run in listed order.)

### Phase 3: Documentation cleanup (pt-BR + CLAUDE.md)

```
T5
T6
```

(T5 and T6 are independent of each other; both depend only on earlier phases.)

### Phase 4: English README

```
T7 ------→ T8
```

---

## Task Breakdown

### T1: Add `--width`/`--height` to edit.mjs and use real dimensions in the prompt ✅ Complete

**What**: Extract a pure `buildPixelArtInstructions({ width, height })` function in `edit.mjs`, accept optional `--width`/`--height` CLI args, and use the function's output in place of the hardcoded `"Use canvas size as 256x256 pixels"` string.
**Where**: `tools/gemini-web-edit/edit.mjs`
**Depends on**: None
**Reuses**: The existing `arg(name)` helper pattern in `edit.mjs` (needs a new optional variant, since `arg()` exits the process when a flag is missing - `--width`/`--height` must not be required).
**Requirement**: CTX-02

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] `edit.mjs` accepts optional `--width` and `--height` CLI args without exiting when either is absent (existing `arg()` throws/exits on a missing flag - add a non-exiting optional lookup instead of reusing `arg()` for these two).
- [ ] `buildPixelArtInstructions({ width, height })` is a standalone exported function: when both `width` and `height` are provided, its return value contains the literal substring `` `${width}x${height}` `` (e.g. `"512x512"`); when either is missing, the returned string contains no digit-based canvas-size clause at all.
- [ ] The static `PIXEL_ART_INSTRUCTIONS` hardcoded `"256x256"` string is removed; the prompt sent to Gemini (`` `${prompt} ${PIXEL_ART_INSTRUCTIONS}` ``) is updated to use `buildPixelArtInstructions(...)`'s output instead.
- [ ] A co-located `tools/gemini-web-edit/edit.test.mjs` (or equivalent) uses `node:test` + `node:assert` to cover both branches (dims present / dims absent) of `buildPixelArtInstructions`.
- [ ] Gate check passes: `node --test tools/gemini-web-edit`
- [ ] Test count: 2 tests pass (one per branch; no silent deletions)

**Tests**: unit
**Gate**: quick

**Commit**: `fix(edit.mjs): replace hardcoded 256x256 with real dimensions`

---

### T2: Forward `{width}`/`{height}` through the default external command ✅ Complete

**What**: Update `DEFAULTS.command` in `gemini-edit.lua` to append `--width "{width}" --height "{height}"` to the shipped `edit.mjs` invocation, so the dimensions `run()` already computes actually reach the CLI.
**Where**: `gemini-edit.lua`
**Depends on**: T1
**Reuses**: `run()`'s existing `fillTemplate(data.command, {..., width = tostring(sent.width), height = tostring(sent.height)})` call - the `width`/`height` keys are already populated; only the `DEFAULTS.command` string template needs the placeholders added.
**Requirement**: CTX-01

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] `DEFAULTS.command`'s literal string includes `--width "{width}" --height "{height}"` appended after the existing `--prompt "{prompt}"`.
- [ ] Manually trace one substitution example (e.g. `width=512`, `height=512`) confirming the filled command string has balanced quotes and is shell-valid.
- [ ] No other `fillTemplate` call site or map needs changes - `width`/`height` keys already exist in `run()`.

**Tests**: none (matches the Test Coverage Matrix: Lua template has no runtime outside Aseprite)
**Gate**: build

**Commit**: `feat(gemini-edit): forward width/height to external command`

---

### T3: Remove `tools/gemini_edit.py` ✅ Complete

**What**: Delete the file — it requires a paid, billing-enabled Gemini API key with no free tier for image models, contradicting the project's no-API-key goal.
**Where**: `tools/gemini_edit.py`
**Depends on**: None
**Reuses**: N/A (deletion)
**Requirement**: CTX-03

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] `tools/gemini_edit.py` no longer exists on disk.
- [ ] Gate check passes: `ls tools/gemini_edit.py` reports "No such file or directory".

**Tests**: none
**Gate**: build

**Commit**: `chore(tools): remove gemini_edit.py (paid api required)`

---

### T4: Remove `tools/gemini-edit.ps1` ✅ Complete

**What**: Delete the file — it requires a paid nanobanana API key and is already broken (Google discontinued the free `gemini` CLI login used as its foundation).
**Where**: `tools/gemini-edit.ps1`
**Depends on**: None
**Reuses**: N/A (deletion)
**Requirement**: CTX-03

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] `tools/gemini-edit.ps1` no longer exists on disk.
- [ ] Gate check passes: `ls tools/gemini-edit.ps1` reports "No such file or directory".

**Tests**: none
**Gate**: build

**Commit**: `chore(tools): remove gemini-edit.ps1 (broken, paid api)`

---

### T5: Update README.md — drop removed backends, fix width/height docs ✅ Complete

**What**: Update `README.md`'s "Estado atual" comparison table (mark the two removed rows as "removed from the repo", keep the rejection rationale), delete the `### tools/gemini_edit.py` and `### tools/gemini-edit.ps1` subsections, add an explicit removal note pointing existing users at `edit.mjs`, and correct the `{width}`/`{height}` placeholder-table row to describe the post-T1/T2 behavior.
**Where**: `README.md`
**Depends on**: T1, T2, T3, T4
**Reuses**: The existing "Estado atual" table structure and the existing placeholder table under "O CLI".
**Requirement**: CTX-05

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] The "Estado atual" table's `gemini_edit.py` and `gemini-edit.ps1` rows state the script was **removed from the repo** (not merely "não recomendado"), while keeping the original rationale text as historical context.
- [ ] The `### tools/gemini_edit.py` and `### tools/gemini-edit.ps1` subsections (setup/usage instructions) are deleted in full.
- [ ] A short note states both scripts were removed and that any "Comando externo" field referencing either must be replaced with the `edit.mjs` command.
- [ ] The `{width}` / `{height}` row in the placeholder table is updated to state these now carry the real dimensions into the canvas-size instruction sent to Gemini (via T1/T2).
- [ ] Gate check passes: `grep -n "gemini_edit.py\|gemini-edit.ps1" README.md` returns only lines inside the historical-rationale table row and the removal note - no install/usage instruction remains.

**Tests**: none
**Gate**: build

**Commit**: `docs(readme): drop removed backends, fix width/height docs`

---

### T6: Update CLAUDE.md's Architecture section ✅ Complete

**What**: Remove `tools/gemini_edit.py` and `tools/gemini-edit.ps1` from the Architecture description, state `tools/gemini-web-edit/edit.mjs` as the sole shipped backend, and mention its new `--width`/`--height` support.
**Where**: `CLAUDE.md`
**Depends on**: T3, T4
**Reuses**: The existing "tools/ (external CLI backends...)" subsection structure in `CLAUDE.md`.
**Requirement**: CTX-04

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] `CLAUDE.md`'s tools/ subsection no longer lists `gemini_edit.py` or `gemini-edit.ps1` as backends.
- [ ] It states `edit.mjs` is the sole shipped backend and documents the new `--width`/`--height` flags.
- [ ] Cross-checked against `tools/`'s actual on-disk contents (post T3/T4) for accuracy.
- [ ] Gate check passes: `grep -n "gemini_edit.py\|gemini-edit.ps1" CLAUDE.md` returns only a line documenting they were removed (consistent with README.md's treatment in T5) - no line describing either as an active/usable backend. (Corrected from an overly strict "no matches at all" gate written into this task, which contradicted CTX-04's actual AC - "no longer describes them as active backends" - and the T5 precedent of keeping historical rationale rather than deleting it outright.)

**Tests**: none
**Gate**: build

**Commit**: `docs(claude): reflect edit.mjs as the sole backend`

---

### T7: Create README.en-US.md ✅ Complete

**What**: Full English translation of the post-T5 `README.md`, with a language-switcher line at the top linking back to `README.md`.
**Where**: `README.en-US.md`
**Depends on**: T5
**Reuses**: `README.md`'s finalized (post-cleanup) structure and section order.
**Requirement**: DOC-01

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] `README.en-US.md` exists with an English translation of every section remaining in the post-T5 `README.md` (Current status, Installation, Building a new release, The CLI + the single `gemini-web-edit` subsection, Proximity factor, Usage tips, Progress & execution, Debug, Known limitations).
- [ ] A one-line language-switcher is present at the very top, linking to `README.md`.
- [ ] Section-header count and order match `README.md` 1:1 (manual diff).
- [ ] Does not describe `gemini_edit.py` or `gemini-edit.ps1` as available options - only the same removed/historical note as `README.md`, translated.

**Tests**: none
**Gate**: build

**Commit**: `docs(readme): add readme.en-us.md translation`

---

### T8: Add language-switcher link to README.md ✅ Complete

**What**: Add a one-line language-switcher at the very top of `README.md` pointing to `README.en-US.md`.
**Where**: `README.md`
**Depends on**: T7
**Reuses**: The switcher line format introduced in T7.
**Requirement**: DOC-02

**Tools**:

- MCP: NONE
- Skill: NONE

**Done when**:

- [ ] `README.md` has a one-line language-switcher at the very top linking to `README.en-US.md`.
- [ ] Round-trip verified: the link in `README.md` reaches `README.en-US.md` and vice versa.

**Tests**: none
**Gate**: build

**Commit**: `docs(readme): link to the english readme`

---

## Phase Execution Map

Phase groupings (for reading order):

```
Phase 1 → Phase 2 → Phase 3 → Phase 4

Phase 1:  T1, T2
Phase 2:  T3, T4
Phase 3:  T5, T6
Phase 4:  T7, T8
```

Full dependency graph (every `Depends on` edge drawn explicitly, including cross-phase ones, so it matches the Task Breakdown exactly):

```
T1 -> T2
T1 -> T5
T2 -> T5
T3 -> T5
T4 -> T5
T3 -> T6
T4 -> T6
T5 -> T7
T7 -> T8
```

Execution is strictly sequential - there is no intra-phase parallelism. All 8 tasks fit a single batch (≤ ~8), so this executes inline with no sub-agent dispatch.

---

## Task Granularity Check

| Task | Scope | Status |
| ---- | ----- | ------ |
| T1: Add width/height to edit.mjs | 1 file (+ its co-located test file) | ✅ Granular |
| T2: Forward width/height in DEFAULTS.command | 1 file, 1 string literal | ✅ Granular |
| T3: Remove gemini_edit.py | 1 file (deletion) | ✅ Granular |
| T4: Remove gemini-edit.ps1 | 1 file (deletion) | ✅ Granular |
| T5: Update README.md | 1 file | ✅ Granular |
| T6: Update CLAUDE.md | 1 file | ✅ Granular |
| T7: Create README.en-US.md | 1 file | ✅ Granular |
| T8: Add switcher to README.md | 1 file | ✅ Granular |

---

## Diagram-Definition Cross-Check

| Task | Depends On (task body) | Diagram Shows | Status |
| ---- | ----------------------- | -------------- | ------ |
| T1 | None | (no incoming edge) | ✅ Match |
| T2 | T1 | T1 -> T2 | ✅ Match |
| T3 | None | (no incoming edge) | ✅ Match |
| T4 | None | (no incoming edge) | ✅ Match |
| T5 | T1, T2, T3, T4 | T1 -> T5, T2 -> T5, T3 -> T5, T4 -> T5 | ✅ Match |
| T6 | T3, T4 | T3 -> T6, T4 -> T6 | ✅ Match |
| T7 | T5 | T5 -> T7 | ✅ Match |
| T8 | T7 | T7 -> T8 | ✅ Match |

Every `Depends on` edge in the Task Breakdown has a matching arrow in the full dependency graph above, and every arrow in that graph has a matching `Depends on` entry - the two sides are drawn to be identical, so the cross-check holds regardless of how phase boundaries are inferred. All dependencies point strictly backward by phase order (Phase 1 → 2 → 3 → 4) - no forward-phase dependency exists.

---

## Test Co-location Validation

| Task | Code Layer Created/Modified | Matrix Requires | Task Says | Status |
| ---- | ---------------------------- | ---------------- | ---------- | ------ |
| T1: Add width/height to edit.mjs | `edit.mjs` prompt-building function | unit | unit | ✅ OK |
| T2: Forward width/height in DEFAULTS.command | `gemini-edit.lua` (config template) | none | none | ✅ OK |
| T3: Remove gemini_edit.py | File removal | none | none | ✅ OK |
| T4: Remove gemini-edit.ps1 | File removal | none | none | ✅ OK |
| T5: Update README.md | Documentation | none | none | ✅ OK |
| T6: Update CLAUDE.md | Documentation | none | none | ✅ OK |
| T7: Create README.en-US.md | Documentation | none | none | ✅ OK |
| T8: Add switcher to README.md | Documentation | none | none | ✅ OK |

No violations - the only code layer with a non-"none" matrix requirement (`edit.mjs`'s prompt-building function) is covered by T1's own co-located `node --test` suite, not deferred to a later task.
