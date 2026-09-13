# Prompt Context Fix, Backend Cleanup & English README Validation

**Date**: 2026-09-13
**Spec**: `.specs/features/prompt-context-audit-i18n/spec.md`
**Diff range**: `ce9c518..HEAD` (8 commits: 0ad71bc, 5247eeb, 6f4102e, 43e2d80, 40c02b5, cb82247, b0a1d10, 7bb5273)
**Verifier**: independent sub-agent (author ≠ verifier)

---

## Task Completion

| Task | Status  | Notes |
| ---- | ------- | ----- |
| T1   | ✅ Done | `buildPixelArtInstructions` extracted and tested, but the discrimination sensor found the `width && height` boundary condition (only one of the two flags present) is never exercised by a test — see Discrimination Sensor below. |
| T2   | ✅ Done | `gemini-edit.lua:13` appends `--width "{width}" --height "{height}"`; `run()` already populates both keys. |
| T3   | ✅ Done | `tools/gemini_edit.py` confirmed absent on disk. |
| T4   | ✅ Done | `tools/gemini-edit.ps1` confirmed absent on disk. |
| T5   | ✅ Done | README.md table/notes/CLI section all updated per AC. |
| T6   | ✅ Done | `CLAUDE.md` did not exist before this feature (see Code Quality) — it was created fresh rather than "updated" as the task text assumed, but its content satisfies CTX-04's outcome. |
| T7   | ✅ Done | `README.en-US.md` created, 1:1 section-header parity confirmed. |
| T8   | ✅ Done | Reciprocal switcher link added to `README.md`. |

---

## Spec-Anchored Acceptance Criteria

### P1: `edit.mjs` prompt reflects actual image dimensions

| Criterion (WHEN X THEN Y) | Spec-defined outcome | `file:line` + assertion | Result |
| --- | --- | --- | --- |
| AC1 (CTX-01): `gemini-edit.lua` builds command from `DEFAULTS.command` including `{width}`/`{height}` filled with `sent.width`/`sent.height` | Template contains both placeholders; `fillTemplate` map supplies real values | `gemini-edit.lua:13` — `command = '... --width "{width}" --height "{height}"'`; `gemini-edit.lua:477-478` — `width = tostring(sent.width), height = tostring(sent.height)` | ✅ PASS (read/trace, no Lua runtime — matches Test Coverage Matrix "none") |
| AC2 (CTX-02): `edit.mjs` with `--width`/`--height` includes exact values in Gemini prompt text, replacing hardcoded 256x256 | Result contains literal `${width}x${height}` | `tools/gemini-web-edit/edit.test.mjs:7-11` — `assert.match(result, /512x512/); assert.doesNotMatch(result, /256x256/)` against `tools/gemini-web-edit/edit.mjs:56-58` | ✅ PASS (`node --test` run: 2/2 pass, see Gate Check) |
| AC3 (CTX-02): IF invoked without `--width` OR without `--height` THEN omit canvas-size sentence entirely, no crash | No digit-based size clause when either is missing | `tools/gemini-web-edit/edit.test.mjs:13-16` — `buildPixelArtInstructions({})` (**both** missing) → `assert.doesNotMatch(result, /\d+x\d+/)` | ⚠️ **Spec-precision gap / partial coverage** — the test only covers "both missing." The literal AC3 wording ("without `--width` OR without `--height`") also covers the mixed case (one present, one missing). The implementation (`edit.mjs:57`, `if (width && height)`) is correct for that case too, but no test asserts it — confirmed by the discrimination sensor (Mutation 1 survived). |

### P1: Remove paid/broken alternative backends and correct docs

| Criterion | Spec-defined outcome | `file:line` + assertion | Result |
| --- | --- | --- | --- |
| AC1 (CTX-03): delete both files | Neither exists on disk | `ls tools/gemini_edit.py tools/gemini-edit.ps1` → both "No such file or directory" (verified) | ✅ PASS |
| AC2 (CTX-05): "Estado atual" table rows marked **removed from the repo**, rationale kept | Rows say "removido do repositório", not "não recomendado" | `README.md:25-26` | ✅ PASS |
| AC3 (CTX-05): `### tools/gemini_edit.py` / `### tools/gemini-edit.ps1` subsections deleted | No install/usage subsections remain | `grep -n "### tools/gemini"` README.md → no matches (confirmed by full-file read) | ✅ PASS |
| AC4 (CTX-04): `CLAUDE.md` Architecture section no longer describes either as active backends, names `edit.mjs` as sole backend | Text states `edit.mjs` is the sole shipped backend | `CLAUDE.md:55` "the sole shipped backend"; `CLAUDE.md:57` historical-only removal note | ✅ PASS |
| AC5 (CTX-05): explicit removal note pointing users at `edit.mjs` | Note present in README.md | `README.md:30` — "**Nota**: ... foram removidos ... troque pelo comando do `edit.mjs`" | ✅ PASS |

### P2: English README parity

| Criterion | Spec-defined outcome | `file:line` + assertion | Result |
| --- | --- | --- | --- |
| AC1 (DOC-01): `README.en-US.md` covers every post-cleanup section | 1:1 header parity | Headers compared: README.md has 11 (`##`/`###`) headers, `README.en-US.md` has 11, same order (`Estado atual`↔`Current status` ... `Limitações conhecidas`↔`Known limitations`) | ✅ PASS |
| AC2 (DOC-02): language-switcher at top of both, linking to the other | Round-trip link | `README.md:1` → `README.en-US.md`; `README.en-US.md:1` → `README.md` | ✅ PASS |
| AC3 (DOC-01): `{width}`/`{height}` row describes real-dimension behavior; removed scripts not documented as available | Table + prose reflect post-fix behavior, no install instructions for removed scripts | `README.en-US.md:96` placeholder row; `README.en-US.md:104-106` `--width`/`--height` prose; `README.en-US.md:26-27,31-34` mark both scripts removed, historical only | ✅ PASS |

**Status**: ⚠️ Spec-precision gap flagged (AC3 of Story 1) — everything else PASS with direct evidence.

---

## Discrimination Sensor

Isolated in a temporary git worktree (`git worktree add`), never touching the real tree. `node_modules` was symlinked into the worktree (untracked, needed only to resolve the `playwright` import) and removed before `git worktree remove --force`. Baseline `git status --porcelain` before and after the sensor run matched exactly (only pre-existing untracked `.agents/`, `.claude/`, `.cursor/`, `.windsurf/`, unrelated to this feature).

| # | File:line | Description | Killed? |
| - | --------- | ------------ | ------- |
| 1 | `tools/gemini-web-edit/edit.mjs:57` | Boundary flip: `if (width && height)` → `if (width \|\| height)` | ❌ **Survived** — both existing tests still pass (one only supplies both dims, the other supplies neither; neither exercises "only one present"). Fix task created below. |
| 2 | `tools/gemini-web-edit/edit.mjs:58` | Return-value mutation: `${width}x${height}` → `${width}${height}` (dropped separator) | ✅ Killed — `edit.test.mjs:9` (`/512x512/`) failed as expected |
| 3 | `tools/gemini-web-edit/edit.mjs:56-61` | Removed side effect: function unconditionally returns `BASE_PIXEL_ART_INSTRUCTIONS`, dropping the dimension branch entirely | ✅ Killed — `edit.test.mjs:9` failed as expected |

**Sensor depth**: lightweight (3 targeted mutations on the highest-risk new code, `buildPixelArtInstructions`)
**Result**: 2/3 killed, 1 survived — ❌ **FAIL** (per validate.md: a surviving mutant means the tests are not discriminating for that behavior; do not mark the feature fully done without a fix task)

---

## Code Quality

| Principle | Status | Notes |
| --- | --- | --- |
| Minimum code | ✅ | `edit.mjs`'s `main()`/`import.meta.url` wrapper is a necessary refactor (the file previously ran top-level `await` code on load — extracting a pure, importable function was impossible without it), not gratuitous restructuring. |
| Surgical changes | ⚠️ | `CLAUDE.md` was created **from scratch** (66 new lines) in T6, even though the task text says "Update CLAUDE.md's Architecture section" and "Reuses: the existing ... subsection structure in CLAUDE.md" — no such file existed anywhere in git history before commit `cb82247`. The content itself is in-scope and accurate, but the task's premise (an existing file to edit) didn't match reality, and the result is a full architecture doc, not a narrow removed-backend fix. Flagged for awareness, not a functional defect. |
| No scope creep | ⚠️ | Same CLAUDE.md observation — it documents the whole Lua pipeline (color conversion, resampling, dialog/config, PATH constraints), well beyond "no longer describe removed backends." Content quality is good; scope is broader than CTX-04 strictly requires. |
| Matches patterns | ✅ | `edit.mjs` refactor preserves original step-by-step automation logic verbatim (diff shows only re-indentation, no logic changes to steps 1-7). |
| Spec-anchored outcome check (asserted values match spec) | ⚠️ | See AC3 gap above — the assertion that exists matches spec-defined output for the "both missing" case, but doesn't cover the "one missing" case implied by CTX-02 bullet 3's wording. |
| Per-layer Coverage Expectation met (domain 1:1 ACs; routes happy+edge+error) | ⚠️ | `buildPixelArtInstructions` has 1:1 nominal coverage (2 tests for 2 stated branches) but the boundary/edge branch (partial args) is untested per the sensor. No routes/e2e in scope (Lua has no runtime harness, matches Test Coverage Matrix). |
| Every test maps to a spec requirement — no unclaimed tests | ✅ | Both tests in `edit.test.mjs` carry an explicit `// Spec: prompt-context-audit-i18n, CTX-02 AC2/AC3.` comment. |
| Documented guidelines followed: [file(s) or "none — strong defaults applied"] | ✅ | None exist (`AGENTS.md`/`CONTRIBUTING.md`/CI/linter config all absent, confirmed by Test Coverage Matrix note) — strong defaults applied (`node:test`, no new dependency). |

---

## Edge Cases

- [x] Hand-edited command already referencing `{width}`/`{height}` keeps working unchanged — `optionalArg` (`edit.mjs:42-46`) never exits/throws when a flag is absent; additive-only change confirmed by reading.
- [x] Custom command targeting a deleted script fails at execution (file not found) — trivially true, files confirmed deleted.
- [x] Width/height treated as plain integers, no parsing/rounding — confirmed no `parseInt`/`Number`/`parseFloat` anywhere in `edit.mjs` (grep returned zero matches); values only ever interpolated into template strings.
- [x] Non-numeric `--width`/`--height` (typo) does not crash — same reasoning: values are never parsed as numbers, only string-interpolated (`edit.mjs:58`).

---

## Gate Check

- **Gate command (as documented in tasks.md)**: `node --test tools/gemini-web-edit`
- **Result of the literal documented command**: **FAILS** on this machine — `MODULE_NOT_FOUND` — reproduced identically in Git Bash and native PowerShell, with relative, absolute, forward-slash, back-slash, and trailing-slash path variants, and reproduced even against a **trivial, unrelated scratch directory** with a single `*.test.mjs` file (Node v22.19.0, win32). This is a pre-existing Node/Windows test-runner directory-argument quirk in this environment, **not a defect introduced by this feature's code**.
- **Working equivalent invocation**: `node --test tools/gemini-web-edit/edit.test.mjs` (or `node --test "tools/gemini-web-edit/*.test.mjs"`) — **2 passed, 0 failed**.
- **Test count before feature**: 0 (no test files existed anywhere in the repo)
- **Test count after feature**: 2
- **Delta**: +2 new tests
- **Skipped tests**: none
- **Failures**: none in the actual test suite; only the literal gate-command string as written in `tasks.md`/`CLAUDE.md:25,55` fails on Windows Node 22 for directory-style arguments — flagged as a fix task (documentation/tooling), not a code gap.

---

## Fix Plans

### Fix 1: Untested boundary condition in `buildPixelArtInstructions`

- **Root cause**: `edit.test.mjs` only covers "both dims present" and "both dims absent." The `width && height` condition (`edit.mjs:57`) has an untested third state (exactly one of the two present), which the spec's AC3 wording ("without `--width` OR without `--height`") also covers. Confirmed via discrimination sensor: flipping `&&`→`||` left both existing tests green.
- **Fix task**: Add a third `node:test` case to `tools/gemini-web-edit/edit.test.mjs`: call `buildPixelArtInstructions({ width: "512" })` (height omitted) and assert `assert.doesNotMatch(result, /\d+x\d+/)`; optionally a fourth case with only `height` set.
- **Priority**: Major (blocks marking CTX-02/T1 fully verified per the discrimination sensor's mandatory rule, though the underlying implementation is already correct).

### Fix 2: Gate command in `tasks.md`/`CLAUDE.md` not portable on Windows Node 22

- **Root cause**: `node --test <directory>` fails with `MODULE_NOT_FOUND` on this Node/Windows combination for any directory argument (verified with an unrelated scratch directory), so the documented `node --test tools/gemini-web-edit` command cannot be copy-pasted and run as-is here.
- **Fix task**: Update the Gate Check Commands table in `tasks.md` and `CLAUDE.md:25,55` to use `node --test tools/gemini-web-edit/edit.test.mjs` (or a glob), or note the Windows caveat.
- **Priority**: Minor (documentation/tooling, does not affect actual code correctness — the test file itself passes).

---

## Requirement Traceability Update

| Requirement | Previous Status | New Status |
| ----------- | ---------------- | ---------- |
| CTX-01 | Implementing | ✅ Verified |
| CTX-02 | Implementing | ⚠️ Needs Fix (surviving mutant on the partial-args branch — see Fix 1) |
| CTX-03 | Implementing | ✅ Verified |
| CTX-04 | Implementing | ✅ Verified (see Code Quality note on CLAUDE.md scope) |
| CTX-05 | Implementing | ✅ Verified |
| DOC-01 | Implementing | ✅ Verified |
| DOC-02 | Implementing | ✅ Verified |

---

## Summary

**Overall**: ⚠️ Issues (not a clean PASS)

**Spec-anchored check**: 8/9 ACs matched spec outcome directly; 1 spec-precision/coverage gap flagged (Story 1, AC3)
**Sensor**: 2/3 mutations killed, 1 survived
**Gate**: 2 passed, 0 failed (via working invocation); the literal documented gate command string fails on this Windows/Node 22 environment for unrelated, pre-existing reasons

**What works**: `edit.mjs` now accepts optional `--width`/`--height` and uses them in the Gemini prompt text via a pure, tested `buildPixelArtInstructions` function; the hardcoded "256x256" claim is gone; `gemini-edit.lua`'s default command forwards the already-computed dimensions; both paid/broken backends are deleted with no lingering install/usage instructions anywhere in the docs; `README.en-US.md` has full 1:1 section parity with a working bidirectional language switcher.

**Issues found**:
1. The `width && height` boundary case in `buildPixelArtInstructions` has no direct test — add the case described in Fix 1.
2. `tasks.md`'s and `CLAUDE.md`'s documented gate command (`node --test tools/gemini-web-edit`) does not run as written on Windows Node 22 — update to `node --test tools/gemini-web-edit/edit.test.mjs` per Fix 2.
3. (Quality note, non-blocking) `CLAUDE.md` was authored as a brand-new 66-line file in T6 rather than an edit to an existing one, going beyond CTX-04's narrow ask — content is accurate and in-scope subject-wise, so no fix task, just flagged for awareness.

**Next steps**: Route Fix 1 and Fix 2 as fix tasks to an implementer; re-verify (test count should go to 3-4, sensor re-run on the strengthened test, and confirm the corrected gate command in tasks.md/CLAUDE.md). This is fix→re-verify iteration 1 of the allowed 3.
