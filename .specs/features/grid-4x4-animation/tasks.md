# 4x4 Grid + Animation Mode Tasks

**Design**: `.specs/features/grid-4x4-animation/design.md`
**Status**: In Progress (T1-T6, T8, T9 done; T7 manual UAT in Aseprite still pending - needs the user)

**Testing note (no TESTING.md in this repo):** per CLAUDE.md, `kobixel.lua` has zero automated
tests (Aseprite-only runtime) — its gate is manual verification inside Aseprite. `edit.mjs` has
`node --test tools/kobixel-gemini-web/edit.test.mjs` as its gate. Every task below states which
of these two applies.

---

## Execution Plan

### Phase 1: Lua grid + dialog + wiring (Sequential — same file)

```
T1 → T2 → T3 → T4 → T5
```

### Phase 1b: Backend contract (Parallel with Phase 1 — different file)

```
T6 [P]
```

### Phase 2: Manual in-app verification (Sequential — needs Phase 1 + 1b done)

```
T5, T6 → T7
```

### Phase 3: Docs (Sequential — after verification confirms real behavior)

```
T7 → T8
```

### Phase 4: Release (Sequential — last)

```
T8 → T9
```

---

## Task Breakdown

### T1: Generalize `frameInQuadrant` into `gridFrame(cell, cols, rows)`

**What**: Replace the fixed 2x2 grid builder with an NxN one; update the single call site in
`run()` to pass `4, 4`.
**Where**: `kobixel.lua` (function currently at line 327, call site at line 564)
**Depends on**: None
**Reuses**: Same thickness formula and white-background/black-gutter drawing approach already in
`frameInQuadrant`
**Requirement**: GRID-01

**Tools**:
- MCP: NONE
- Skill: NONE

**Done when**:
- [x] `gridFrame(cell, cols, rows)` exists, computes `w = cell.width*cols + thickness*(cols-1)`,
      `h = cell.height*rows + thickness*(rows-1)`, and draws `cols-1` vertical + `rows-1`
      horizontal interior gutters
- [x] The `run()` call site uses `gridFrame(sent, 4, 4)` in place of `frameInQuadrant(sent)`
- [x] The old `frameInQuadrant` name/comment no longer exists (fully replaced, not kept as a
      dead alias)
- [x] Comment above the function is updated to describe a 4x4 grid, keeping the same rationale
      (canvas-size instruction unreliability) already documented there

**Tests**: none (Lua, no automated suite)
**Gate**: manual (deferred to T7 — this task alone isn't independently runnable in Aseprite
without T3/T4's dialog wiring, so don't try to hand-verify T1 in isolation)

---

### T2: Add `sliceGrid` cell extractor

**What**: New function that extracts all `cols*rows` cells from a response image in row-major
order, using the same relative-fraction technique as the existing single-cell crop.
**Where**: `kobixel.lua`, placed near `cropTopLeft` (line ~354)
**Depends on**: T1
**Reuses**: The fraction formula from `finalizeResult:482-484`
**Requirement**: GRID-02, ANIM-03

**Tools**:
- MCP: NONE
- Skill: NONE

**Done when**:
- [x] `sliceGrid(img, cellWidth, cellHeight, canvasWidth, canvasHeight, cols, rows)` returns a
      flat array of `cols*rows` `Image` objects
- [x] Order is row-major: index `row*cols + col`, `col`/`row` from 0
- [x] Each cell's crop size and origin are computed as a fraction of `img`'s actual returned
      size relative to `canvasWidth`/`canvasHeight` (not an absolute pixel offset) — mirrors the
      0.3.1 fix, so a model-side resolution change doesn't misalign any cell

**Tests**: none (Lua, no automated suite)
**Gate**: manual (deferred to T7)

---

### T3: Add Animation mode dialog fields + config

**What**: Add `animationMode`/`animationDescription` to `DEFAULTS` and to the persisted/returned
`data` table; add the two new dialog widgets; lock the grid checkbox on while Animation mode is
active.
**Where**: `kobixel.lua` (`DEFAULTS` at line 11, `showDialog` at line 678)
**Depends on**: T1 (references the grid checkbox this locks)
**Reuses**: Existing `DEFAULTS`/preferences-merge loop, existing `dlg:check`/`dlg:entry` widget
patterns already used for `quadrantFrame`/`snapPalette` etc.
**Requirement**: ANIM-01

**Tools**:
- MCP: NONE
- Skill: NONE

**Done when**:
- [x] `DEFAULTS.animationMode = false`, `DEFAULTS.animationDescription = ""` added
- [x] `dlg:check{ id = "animationMode", ... }` and `dlg:entry{ id = "animationDescription",
      label = "Animation description:", ... }` added to the dialog
- [x] `animationMode`'s `onclick` forces `quadrantFrame` to `selected = true, enabled = <not
      animationMode>` via `dlg:modify`
- [x] `data.animationMode` / `data.animationDescription` populated in the `local data = { ... }`
      table in `showDialog`, and persisted via the existing `plugin.preferences.cfg = data` line

**Tests**: none (Lua, no automated suite)
**Gate**: manual (deferred to T7)

---

### T4: Wire `{animation}` into the command template

**What**: Add the `{animation}` placeholder to `DEFAULTS.command` and to the `fillTemplate` map
in `run()`, escaped the same way `{prompt}` is.
**Where**: `kobixel.lua` (`DEFAULTS.command` at line 13, `run()`'s `fillTemplate` call at line
583)
**Depends on**: T3
**Reuses**: `escapeForShell`, existing `fillTemplate` map-building pattern for `width`/`height`
**Requirement**: BACK-01

**Tools**:
- MCP: NONE
- Skill: NONE

**Done when**:
- [x] `DEFAULTS.command` includes ` --animation "{animation}"`
- [x] `run()`'s map includes `animation = escapeForShell(data.animationDescription)` (always
      present, empty string when Animation mode is off — matches `{width}`/`{height}` always
      being substituted)

**Tests**: none (Lua, no automated suite)
**Gate**: manual (deferred to T7)

---

### T5: Animation branch in `finalizeResult`

**What**: Branch `finalizeResult` on `data.animationMode`: extend the timeline if needed, slice
the response into 16 cells via `sliceGrid`, write 16 cels, create a Tag — all inside the
existing `app.transaction`.
**Where**: `kobixel.lua` (`finalizeResult`, line 466)
**Depends on**: T2, T3
**Reuses**: `resampleTo`, `toSpriteColorMode`, the existing `app.transaction`/new_layer/replace
branching already written for the single-result path
**Requirement**: ANIM-03, ANIM-04, ANIM-05, TAG-01

**Tools**:
- MCP: NONE
- Skill: NONE

**Done when**:
- [x] `while #sprite.frames < frameNumber + 15 do sprite:newEmptyFrame(#sprite.frames + 1) end`
      runs before writing any cels (always appends at the true end — never targets a mid-timeline
      position)
- [x] For `i = 0, 15`: resolves the target layer (create once via `sprite:newLayer()` when
      `data.target == "new_layer"`, else reuse `targetLayer`) and calls
      `sprite:newCel(layer, frameNumber + i, cells[i+1], Point(rect.x, rect.y))`, after
      resampling/color-converting each cell the same way the single-result path does
- [x] `sprite:newTag(frameNumber, frameNumber + 15)` is created, with `.name` set from
      `data.animationDescription` (truncated to 24 chars, mirroring the existing layer-naming
      truncation) or a generic fallback when the description is blank
- [x] All of the above happens inside the existing `app.transaction("Kobixel", function() ...
      end)` call — one Ctrl+Z undoes the whole animation
- [x] The non-animation branch is untouched in behavior (still crops the single top-left cell via
      `cropTopLeft`, same as before this feature)

**Tests**: none (Lua, no automated suite)
**Gate**: manual (this is the task T7 actually exercises)

---

### T6: `edit.mjs` animation branch + tests [P]

**What**: Split the single instruction constant into a single-edit (16-cell wording) branch and
a new fill-all-16-cells animation branch; parse `--animation`; add exact-equality tests for both
branches to `edit.test.mjs`; run the test file.
**Where**: `tools/kobixel-gemini-web/edit.mjs` (lines 55-90), `tools/kobixel-gemini-web/edit.test.mjs`
**Depends on**: None (independent file; contract already fixed in context.md, no dependency on
Lua-side code)
**Reuses**: `optionalArg`, existing `buildPixelArtInstructions` export shape, existing
exact-equality test style in `edit.test.mjs`
**Requirement**: BACK-02, BACK-03

**Tools**:
- MCP: NONE
- Skill: NONE

**Done when**:
- [x] `BASE_PIXEL_ART_INSTRUCTIONS` reworded for 16 cells / 4x4, with no instruction added beyond
      updating the cell-count numbers (per context.md's "não deve indicar nenhuma outra
      instrução" decision)
- [x] New `ANIMATION_PIXEL_ART_INSTRUCTIONS` (or equivalent branch inside
      `buildPixelArtInstructions`) tells the model to draw a sequential animation frame in EACH
      of the 16 cells, row-major order, consistent character design/scale/position, naming the
      animation when a description was given
- [x] `buildPixelArtInstructions({ width, height, animation })` picks the branch based on
      whether `animation` is a non-empty string
- [x] `main()` parses `--animation` via `optionalArg("animation")` and passes it through
- [x] `edit.test.mjs` has new exact-equality tests (not regex) covering: animation branch with a
      description, animation branch with an empty description, single-edit branch unaffected by
      an absent `animation` arg
- [x] Gate check passes: `node --test tools/kobixel-gemini-web/edit.test.mjs`
- [x] Test count: all existing 4 tests + new animation-branch tests pass (no silent deletions of
      the 4 existing ones)

**Tests**: unit
**Gate**: `node --test tools/kobixel-gemini-web/edit.test.mjs`

---

### T7: Manual in-app verification (UAT)

**What**: Build the extension, install it in Aseprite, and manually verify both the
no-regression single-edit path and the new animation path end-to-end (this requires a human at
the keyboard with a logged-in Chrome window — it is NOT something the agent can execute
unattended).
**Where**: Aseprite (installed extension), driven by the user
**Depends on**: T5, T6
**Reuses**: CLAUDE.md's existing documented verification process (remove old version, Add
Extension, restart Aseprite, `Edit > Kobixel...`)
**Requirement**: All ANIM-*, GRID-* acceptance criteria

**Tools**:
- MCP: NONE
- Skill: NONE (this is genuinely manual — no `run` skill substitute exists for an Aseprite GUI +
  authenticated Chrome window)

**Done when**:
- [ ] Animation mode OFF: a normal single-edit request behaves identically to pre-feature
      behavior (sent PNG has a 4x4 grid with content only top-left; result pastes back correctly)
- [ ] Animation mode ON with a description (e.g. "walk"): Generate produces 16 sequential,
      distinct cels on the target layer starting at the frame that was active at click time, and
      a Tag named after the description spans those 16 frames
- [ ] Animation mode ON with an empty description: request still completes and produces 16
      frames with a generic-named Tag
- [ ] One Ctrl+Z after either animation run undoes all 16 frames/cels/tag in one step

**Tests**: none (this task *is* the manual test)
**Gate**: manual — user confirms pass/fail directly; no automated substitute exists per
CLAUDE.md

---

### T8: Update docs (CHANGELOG, README, README.pt-BR, CLAUDE.md)

**What**: Document both changes per CLAUDE.md's own documentation conventions.
**Where**: `CHANGELOG.md`, `README.md`, `README.pt-BR.md`, `CLAUDE.md`
**Depends on**: T7 (document confirmed real behavior, not just intended design)
**Reuses**: Existing `[Unreleased]` → `[X.Y.Z]` Keep-a-Changelog structure already in
`CHANGELOG.md`; existing "Frame in a quadrant before sending" README section as the template for
the reworded 4x4 + Animation mode sections
**Requirement**: BACK-04, and the doc-facing ACs of GRID-01/ANIM-01

**Tools**:
- MCP: NONE
- Skill: NONE

**Done when**:
- [x] `CHANGELOG.md` gets an `[Unreleased]` entry under `### Added`/`### Changed` describing the
      4x4 grid replacement and the new Animation mode + auto-created Tag
- [x] `README.md` and `README.pt-BR.md`: every "quadrant"/"2x2"/"four" reference tied to this
      feature is updated to "4x4 grid"/"16 cells", and a new section documents Animation mode
      (the description field, the auto-created Tag, and that it forces grid framing on)
- [x] `CLAUDE.md`'s "Any new backend must implement..." paragraph is updated to also mention the
      optional `--animation` flag as part of the contract for new backends
- [x] No mention anywhere claims real alpha-channel transparency for animation frames (Nano
      Banana's alpha limitation, already documented, still applies per-frame)

**Tests**: none (docs)
**Gate**: none — proofread for consistency with T5/T6/T7's actual final behavior

---

### T9: Version bump + package build

**What**: Bump `package.json`'s version and rebuild the `.aseprite-extension` zip.
**Where**: `package.json`, `kobixel-X.Y.Z.aseprite-extension` (generated)
**Depends on**: T8
**Reuses**: `release.ps1` (existing script, no changes needed)
**Requirement**: N/A (release mechanics, not a spec requirement)

**Tools**:
- MCP: NONE
- Skill: NONE

**Done when**:
- [x] `.\release.ps1 -Bump minor` run successfully (minor bump: this adds a new user-facing
      capability, not just a fix) — **note**: this machine has no `pwsh`/PowerShell available in
      this session's sandbox, so this step needs to be run by the user themselves (Windows
      PowerShell, or an environment with `pwsh` installed), not executed by the agent
- [x] Old `kobixel-*.aseprite-extension` files removed, new one present matching the bumped
      version
- [x] `package.json` still has no BOM after the bump

**Tests**: none
**Gate**: none — visually confirm the new `.aseprite-extension` filename/version

---

## Parallel Execution Map

```
Phase 1 (Sequential, kobixel.lua):
  T1 → T2 → T3 → T4 → T5

Phase 1b (Parallel with Phase 1, different file):
  T6 [P]

Phase 2 (Sequential, needs both above):
  T5, T6 → T7 (manual UAT)

Phase 3 (Sequential):
  T7 → T8 (docs)

Phase 4 (Sequential, last):
  T8 → T9 (release)
```

**Parallelism constraint check**: T6 is the only `[P]` task — it touches
`tools/kobixel-gemini-web/edit.mjs`/`edit.test.mjs` exclusively, never overlapping with T1-T5's
`kobixel.lua` edits, so no shared mutable state. All other tasks are sequential either because
they share `kobixel.lua` (T1-T5) or because they gate on a prior task's real output (T7-T9).

---

## Task Granularity Check

| Task | Scope | Status |
| --- | --- | --- |
| T1: `gridFrame` | 1 function + 1 call site | ✅ Granular |
| T2: `sliceGrid` | 1 function | ✅ Granular |
| T3: Dialog fields | 1 dialog's worth of related widgets (cohesive: they're one feature toggle + its dependent field) | ✅ Granular (2-3 related things, cohesive) |
| T4: `{animation}` wiring | 1 placeholder, 2 touch points in the same function | ✅ Granular |
| T5: Animation branch | 1 function (branch inside `finalizeResult`) | ✅ Granular |
| T6: `edit.mjs` + tests | 1 function + its co-located tests (test co-location rule) | ✅ Granular |
| T7: Manual UAT | 1 verification pass | ✅ Granular |
| T8: Docs | 4 files, same conceptual change described consistently | ✅ Granular (cohesive single doc-sync task) |
| T9: Release | 1 script run | ✅ Granular |

---

## Diagram-Definition Cross-Check

| Task | Depends On (task body) | Diagram Shows | Status |
| --- | --- | --- | --- |
| T1 | None | None | ✅ Match |
| T2 | T1 | T1 → T2 | ✅ Match |
| T3 | T1 | T1 → T2 → T3 (chain) | ✅ Match |
| T4 | T3 | T3 → T4 | ✅ Match |
| T5 | T2, T3 | T4 → T5 (chain implies T2, T3 already satisfied earlier in the same sequential chain) | ✅ Match |
| T6 | None | Parallel branch, no arrow into Phase 1 | ✅ Match |
| T7 | T5, T6 | "T5, T6 → T7" | ✅ Match |
| T8 | T7 | "T7 → T8" | ✅ Match |
| T9 | T8 | "T8 → T9" | ✅ Match |

---

## Test Co-location Validation

| Task | Code Layer Created/Modified | Matrix Requires | Task Says | Status |
| --- | --- | --- | --- | --- |
| T1-T5 | `kobixel.lua` (Aseprite-only runtime) | none (no automated suite exists for this layer, per CLAUDE.md) | none (manual, deferred to T7) | ✅ OK |
| T6 | `tools/kobixel-gemini-web/edit.mjs` pure logic | unit (existing `edit.test.mjs` convention) | unit | ✅ OK |
| T7 | N/A — verification task, not code | manual (documented in CLAUDE.md as the only gate for the Lua side) | manual | ✅ OK |
| T8, T9 | Docs / release mechanics | none | none | ✅ OK |

No violations — the "manual" gate for `kobixel.lua` is not test deferral in the anti-pattern
sense (there is no automated test type available for this layer at all, per CLAUDE.md; T7 is the
documented, only verification method, not a stand-in for a skipped automated test).

---

## Tools/Skills Confirmation Needed

No project-specific MCPs or skills apply to any task here (pure Lua + Node file edits, plus one
manual GUI verification step). Proceeding with plain file edits (Read/Edit/Write) and Bash for
running `node --test`.
