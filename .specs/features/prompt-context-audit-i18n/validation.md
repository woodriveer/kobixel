# Prompt Context Fix, Backend Cleanup & English README Validation

**Date**: 2026-09-13
**Spec**: `.specs/features/prompt-context-audit-i18n/spec.md`
**Diff range**: `ce9c518..HEAD` (11 commits: 0ad71bc, 5247eeb, 6f4102e, 43e2d80, 40c02b5, cb82247, b0a1d10, 7bb5273, 5b7ccfc, 5e45974, a98d6fa)
**Verifier**: independent sub-agent (author ≠ verifier) — this is fix→re-verify iteration 1 of the allowed 3, re-run from scratch against the full diff surface, not a diff against the round-1 report.

---

## Task Completion

| Task | Status | Notes |
| ---- | ------- | ----- |
| T1 | ✅ Done | `buildPixelArtInstructions` extracted, exported, and now covered by 4 tests including the previously-untested partial-args boundary. |
| T2 | ✅ Done | `gemini-edit.lua:13` appends `--width "{width}" --height "{height}"`; `run()` (`gemini-edit.lua:477-478`) populates both keys with `tostring(sent.width/height)`. |
| T3 | ✅ Done | `tools/gemini_edit.py` confirmed absent on disk (re-verified). |
| T4 | ✅ Done | `tools/gemini-edit.ps1` confirmed absent on disk (re-verified). |
| T5 | ✅ Done | README.md table/notes/CLI section confirmed updated per AC (re-read in full). |
| T6 | ✅ Done | `CLAUDE.md` content satisfies CTX-04's outcome; scope-breadth note carried forward (see Code Quality). |
| T7 | ✅ Done | `README.en-US.md` 1:1 section-header parity re-confirmed (11 headers, same order, both files). |
| T8 | ✅ Done | Reciprocal switcher link (`README.md:1` ↔ `README.en-US.md:1`) re-confirmed working round-trip. |
| FIX-1 | ✅ Done | `BASE_PIXEL_ART_INSTRUCTIONS` exported (`edit.mjs:48`); `edit.test.mjs` now has 4 exact-equality tests covering both-present, both-absent, width-only, height-only. Independently re-mutated and confirmed killed (see Discrimination Sensor). |
| FIX-2 | ✅ Done | `tasks.md` Gate Check Commands, Test Coverage Matrix, T1/FIX-1/FIX-2 Done-when, and `CLAUDE.md:25,55` all cite `node --test tools/gemini-web-edit/edit.test.mjs`. Independently re-ran both the corrected and the old broken form (see Gate Check). |

---

## Spec-Anchored Acceptance Criteria

### P1: `edit.mjs` prompt reflects actual image dimensions

| Criterion (WHEN X THEN Y) | Spec-defined outcome | `file:line` + assertion | Result |
| --- | --- | --- | --- |
| AC1 (CTX-01): `gemini-edit.lua` builds command from `DEFAULTS.command` including `{width}`/`{height}` filled with `sent.width`/`sent.height` | Template contains both placeholders; `fillTemplate` map supplies real values | `gemini-edit.lua:13` — `command = '... --width "{width}" --height "{height}"'`; `gemini-edit.lua:477-478` — `width = tostring(sent.width), height = tostring(sent.height)` | ✅ PASS (re-traced independently) |
| AC2 (CTX-02): `edit.mjs` with `--width`/`--height` includes exact values in Gemini prompt text, replacing hardcoded 256x256 | Result contains literal `${width}x${height}` | `tools/gemini-web-edit/edit.test.mjs:15-21` — `assert.equal(result, \`${BASE_PIXEL_ART_INSTRUCTIONS} Use canvas size as 512x512 pixels.\`)` against `edit.mjs:56-58` | ✅ PASS (`node --test tools/gemini-web-edit/edit.test.mjs`: 4/4 pass, independently re-run) |
| AC3 (CTX-02): IF invoked without `--width` OR without `--height` THEN omit canvas-size sentence entirely, no crash | No digit-based size clause when either is missing (all three sub-states: neither, width-only, height-only) | `edit.test.mjs:23-26` (neither), `:28-31` (width-only), `:33-36` (height-only) — each asserts exact equality to `BASE_PIXEL_ART_INSTRUCTIONS` against `edit.mjs:56-60` | ✅ PASS — round-1's gap (mixed-state untested) is closed; all three sub-states now have dedicated exact-equality assertions, not a permissive regex. |

**Round-1 gap closed**: the discrimination sensor's exact mutation (`width && height` → `width || height`) was independently re-applied in a fresh isolated worktree and is now killed (2/4 tests fail with the malformed `undefinedx512` value surfaced) — see Discrimination Sensor below.

### P1: Remove paid/broken alternative backends and correct docs

| Criterion | Spec-defined outcome | `file:line` + assertion | Result |
| --- | --- | --- | --- |
| AC1 (CTX-03): delete both files | Neither exists on disk | `ls tools/gemini_edit.py tools/gemini-edit.ps1` → both "No such file or directory" (re-verified) | ✅ PASS |
| AC2 (CTX-05): "Estado atual" table rows marked **removed from the repo**, rationale kept | Rows say "removido do repositório", not "não recomendado" | `README.md:25-26` (re-read in full) | ✅ PASS |
| AC3 (CTX-05): `### tools/gemini_edit.py` / `### tools/gemini-edit.ps1` subsections deleted | No install/usage subsections remain | `grep -n "### tools/gemini" README.md README.en-US.md` → zero matches (re-run) | ✅ PASS |
| AC4 (CTX-04): `CLAUDE.md` Architecture section no longer describes either as active backends, names `edit.mjs` as sole backend | Text states `edit.mjs` is the sole shipped backend | `CLAUDE.md:55` "the sole shipped backend"; `CLAUDE.md:57` historical-only removal note | ✅ PASS |
| AC5 (CTX-05): explicit removal note pointing users at `edit.mjs` | Note present in README.md | `README.md:30` — "**Nota**: ... foram removidos ... troque pelo comando do `edit.mjs`" | ✅ PASS |

Full-repo grep for `gemini_edit\.py\|gemini-edit\.ps1` (excluding `.git`) re-run: every hit outside `.specs/` (the spec/tasks/validation artifacts themselves, which are expected to name the removed files) falls inside `CLAUDE.md:57`'s historical note or the two READMEs' historical-rationale table rows/removal notes — no install/usage instruction remains anywhere.

### P2: English README parity

| Criterion | Spec-defined outcome | `file:line` + assertion | Result |
| --- | --- | --- | --- |
| AC1 (DOC-01): `README.en-US.md` covers every post-cleanup section | 1:1 header parity | Re-diffed: README.md has 11 `##`/`###` headers, `README.en-US.md` has 11, same order (`Estado atual`↔`Current status` ... `Limitações conhecidas`↔`Known limitations`) | ✅ PASS |
| AC2 (DOC-02): language-switcher at top of both, linking to the other | Round-trip link | `README.md:1` → `README.en-US.md`; `README.en-US.md:1` → `README.md` (re-read) | ✅ PASS |
| AC3 (DOC-01): `{width}`/`{height}` row describes real-dimension behavior; removed scripts not documented as available | Table + prose reflect post-fix behavior, no install instructions for removed scripts | `README.en-US.md:96` placeholder row ("dimensions of the sent PNG"); `README.en-US.md:26-27,31-34` mark both scripts removed, historical only | ✅ PASS |

**Status**: ✅ All ACs covered — no spec-precision gaps remain. 9/9 ACs matched the spec-defined outcome directly.

---

## Discrimination Sensor

Isolated in a fresh temporary git worktree (`git worktree add /d/Developer/repixel-ai-verify-scratch HEAD`), never touching the real tree. `node_modules` (for the `playwright` import chain) was symlinked into the worktree from the real tree's `tools/gemini-web-edit/node_modules` and the symlink removed before `git worktree remove --force`. Baseline `git status --porcelain` before and after the sensor run matched exactly (only the pre-existing untracked `.agents/`, `.claude/`, `.cursor/`, `.windsurf/`, unrelated to this feature — confirmed via `git worktree list` showing no leftover worktree afterward).

| # | File:line | Description | Killed? |
| - | --------- | ------------ | ------- |
| 1 | `tools/gemini-web-edit/edit.mjs:57` | **Exact re-attempt of the round-1 survivor**: boundary flip `if (width && height)` → `if (width \|\| height)` | ✅ **Killed** — 2/4 tests now fail. `assert.equal` on the width-only case expected `BASE_PIXEL_ART_INSTRUCTIONS` but got `"...blur. Use canvas size as undefinedx512 pixels."` — the malformed value is now caught because the assertion is exact-equality, not the old permissive `doesNotMatch(/\d+x\d+/)` regex. |
| 2 | `tools/gemini-web-edit/edit.mjs:58` | Return-value mutation: dropped separator, `${width}x${height}` → `${width}${height}` | ✅ Killed — 1/4 tests failed (the both-present case, exact-equality mismatch). |
| 3 | `tools/gemini-web-edit/edit.mjs:56-60` | Removed side effect: function unconditionally returns `BASE_PIXEL_ART_INSTRUCTIONS`, dropping the dimension branch entirely | ✅ Killed — 1/4 tests failed (the both-present case). |

**Sensor depth**: lightweight (3 targeted mutations on the highest-risk new code, `buildPixelArtInstructions`), including a mandatory exact re-attempt of the round-1 surviving mutation.
**Result**: 3/3 killed — ✅ **PASS**

---

## Interactive UAT Results

Not performed — backend/CLI + documentation feature with no interactive UI surface in scope (matches spec's own "Out of Scope: Localizing dialog UI strings" and the project's manual-Lua-testing convention). Consistent with round 1.

---

## Code Quality

| Principle | Status | Notes |
| --- | --- | --- |
| Minimum code | ✅ | FIX-1's change is a 1-line export plus new test cases; FIX-2 is documentation-only. Neither adds unrequested functionality. |
| Surgical changes | ⚠️ | Carried forward from round 1, unchanged by the fix commits: `CLAUDE.md` was authored as a brand-new 66-line file in T6 rather than an edit to an existing one (none existed in git history before `cb82247`), going beyond CTX-04's narrow "update the Architecture section" ask. Content is accurate and in-scope subject-wise. Not touched or worsened by this round's fix commits (`git show 5e45974` only edits 2 existing lines in `CLAUDE.md`). Flagged for awareness, not a functional defect. |
| No scope creep | ✅ | FIX-1/FIX-2 diffs (`git show 5b7ccfc`, `git show 5e45974`) touch only `edit.mjs` (1 line), `edit.test.mjs`, `tasks.md`, `CLAUDE.md` (the 2 command-string lines), and `spec.md` (traceability) — exactly the files named in the fix tasks, nothing else. |
| Matches patterns | ✅ | New tests follow the existing `node:test`/`node:assert/strict` pattern already established in T1; no new dependency added. |
| Spec-anchored outcome check (asserted values match spec) | ✅ | All 4 tests assert exact string equality against spec-defined outcomes (real `WxH` string, or the literal base-instructions constant) — no vague/regex assertions remain. |
| Per-layer Coverage Expectation met (domain 1:1 ACs; routes happy+edge+error) | ✅ | `buildPixelArtInstructions` now has 4 tests covering all 3 branches implied by AC3's "without X or without Y" wording (both-absent, width-only, height-only) plus the both-present branch. No routes/e2e in scope (Lua has no runtime harness, matches Test Coverage Matrix). |
| Every test maps to a spec requirement — no unclaimed tests | ✅ | `edit.test.mjs` carries a file-level comment block citing "Spec: prompt-context-audit-i18n, CTX-02 AC2/AC3" covering all 4 tests. |
| Documented guidelines followed: [file(s) or "none — strong defaults applied"] | ✅ | None exist (`AGENTS.md`/`CONTRIBUTING.md`/CI/linter config all absent, re-confirmed) — strong defaults applied (`node:test`, no new dependency). |

---

## Edge Cases

- [x] Hand-edited command already referencing `{width}`/`{height}` keeps working unchanged — `optionalArg` (`edit.mjs:42-46`) never exits/throws when a flag is absent; re-confirmed by reading.
- [x] Custom command targeting a deleted script fails at execution (file not found) — trivially true, files re-confirmed deleted.
- [x] Width/height treated as plain integers, no parsing/rounding — re-confirmed via independent grep: zero matches for `parseInt|parseFloat|Number(` anywhere in `edit.mjs`.
- [x] Non-numeric `--width`/`--height` (typo) does not crash — same reasoning: values are never parsed as numbers, only string-interpolated (`edit.mjs:58`).

---

## Gate Check

- **Gate command (corrected, per FIX-2)**: `node --test tools/gemini-web-edit/edit.test.mjs`
- **Result**: **4 passed, 0 failed** (independently re-run against the real working tree)
- **Old documented command re-check**: `node --test tools/gemini-web-edit` (directory form) — independently re-run and **confirmed still fails** with `MODULE_NOT_FOUND` on this machine (Node v22.19.0, win32), consistent with round 1's finding. This confirms the round-1 defect was real and that FIX-2 correctly changed the *documented* command rather than claiming to fix an unfixable Node/Windows quirk.
- **Test count before this feature**: 0
- **Test count after FIX-1**: 4 (was 2 after round-1's T1; FIX-1 added 2 more to cover the previously-untested boundary sub-states)
- **Delta**: +4 new tests total (+2 since round 1)
- **Skipped tests**: none
- **Failures**: none

**Test Integrity Check**: test count increased (2 → 4), no test was deleted or weakened; the two new tests use the same exact-equality style as the two strengthened originals — no regression.

---

## Fix Plans

None. Both round-1 fix tasks (FIX-1, FIX-2) are independently confirmed resolved with fresh evidence, not just re-read from the prior report.

---

## Requirement Traceability Update

| Requirement | Previous Status | New Status |
| ----------- | ---------------- | ---------- |
| CTX-01 | ✅ Verified | ✅ Verified |
| CTX-02 | ⚠️ Needs Fix | ✅ Verified |
| CTX-03 | ✅ Verified | ✅ Verified |
| CTX-04 | ✅ Verified | ✅ Verified |
| CTX-05 | ✅ Verified | ✅ Verified |
| DOC-01 | ✅ Verified | ✅ Verified |
| DOC-02 | ✅ Verified | ✅ Verified |

---

## Summary

**Overall**: ✅ Ready

**Spec-anchored check**: 9/9 ACs matched spec outcome directly; 0 spec-precision gaps
**Sensor**: 3/3 mutations killed, including an independent re-attempt of the exact mutation that survived round 1
**Gate**: 4 passed, 0 failed (corrected command); old documented directory-form command re-confirmed broken on this Windows/Node 22 environment for pre-existing, unrelated reasons — docs now correctly point at the working form

**What works**: `edit.mjs` accepts optional `--width`/`--height` and uses them in the Gemini prompt text via a pure, now-fully-tested `buildPixelArtInstructions` function covering all 4 argument-presence combinations with exact-equality assertions; `gemini-edit.lua`'s default command forwards the already-computed dimensions; both paid/broken backends are deleted with no lingering install/usage instructions anywhere in the docs; `README.en-US.md` has full 1:1 section parity with a working bidirectional language switcher; the documented gate command now runs as written on this machine.

**Issues found**: None blocking. One non-blocking quality note carried forward unchanged from round 1: `CLAUDE.md` was authored as a new file in T6 rather than edited from an existing one, going slightly beyond CTX-04's narrow scope — content is accurate, not touched by this round's fixes, not a functional defect.

**Next steps**: None required. Feature is done; no further fix→re-verify iteration needed.
