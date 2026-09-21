# 4x4 Grid + Animation Mode Specification

## Problem Statement

The "Frame in a quadrant" trick (2x2 grid, content in the top-left cell) reliably stops Nano
Banana from resizing/repainting the whole canvas, validated in production (0.3.0/0.3.1). The
user wants two things built on top of that proven trick: (1) widen the grid from 2x2 (4 cells)
to 4x4 (16 cells), and (2) reuse those 16 cells to generate a full animation — 16 sequential
frames of the same asset (idle, walk, run, jump, ...) in one Gemini request, sliced back into
real Aseprite timeline frames.

## Goals

- [ ] Single-edit mode keeps today's quality/behavior, just framed in a 4x4 grid instead of 2x2
- [ ] A new "Animation mode" generates 16 usable, sequentially-ordered animation frames from one
      Gemini request and drops them straight into the sprite's timeline
- [ ] Backends declare animation support the same explicit way they declare `--width`/`--height`
      support today (documented contract, not a silent convention)

## Out of Scope

| Feature | Reason |
| --- | --- |
| Configurable grid size (2x2/3x3/4x4/...) | User explicitly asked to replace 2x2 with 4x4, not to make it configurable |
| Auto-adjusting the upscale factor based on grid size | Existing "Upscale before sending" slider already gives the user that control; adding auto-logic is unrequested complexity (see design.md Tech Decisions) |
| Onion skinning / interpolation / frame count other than 16 | 16 is fixed by the 4x4 grid; anything else is a different feature |
| Setting custom per-frame durations or `aniDir` on the created Tag | Aseprite's default new-frame duration is used as-is; no fps/timing UI was requested |
| Retrofitting the removed `gemini_edit.py` / `gemini-edit.ps1` backends with animation support | Out of scope per CLAUDE.md — those backends are gone, don't resurrect |

---

## User Stories

### P1: 4x4 grid replaces the 2x2 quadrant frame ⭐ MVP

**User Story**: As a pixel artist using the existing "Frame in a quadrant" option, I want it
widened to a 4x4 (16-cell) grid instead of 2x2, with no other behavior change, so single-edit
requests keep working exactly as validated before, just on a bigger grid.

**Why P1**: Everything else (animation) is built on this same grid primitive — it must exist
and work correctly first.

**Acceptance Criteria**:

1. WHEN "Frame in a grid before sending" is checked and Animation mode is OFF THEN the system
   SHALL place the sent image in the top-left of a 4x4 grid (16 cells) with the other 15 cells
   left blank, exactly mirroring today's 2x2 top-left placement.
2. WHEN the response comes back THEN the system SHALL crop the top-left cell back out using the
   same *relative-fraction-of-returned-size* technique already used for the 2x2 grid (not an
   absolute pixel size), so a model-side resolution change on a 4x4 grid doesn't misalign the
   crop.
3. WHEN the backend's prompt text describes the grid THEN it SHALL describe 16 cells / 4x4,
   with no other added instruction or constraint beyond what already existed for the 2x2 case
   (same sentence, updated numbers only).
4. WHEN Animation mode is OFF THEN the UI checkbox text and README/CHANGELOG SHALL reflect "4x4
   grid" instead of "quadrant"/"2x2" wherever the old count was mentioned.

**Independent Test**: Toggle Animation mode off, run a normal single edit, confirm the sent PNG
has a 4x4 grid with content only in the top-left cell, and the result pastes back in place same
as before 0.3.1.

---

### P1: Animation mode generates 16 sprite frames ⭐ MVP

**User Story**: As a pixel artist, I want to check "Animation mode", optionally type what the
animation is ("walk", "idle", "jump run cycle"), and get 16 real frames on my sprite's timeline
from a single Generate click, instead of manually asking for one frame at a time.

**Why P1**: This is the actual feature being requested — the 4x4 grid exists to serve this.

**Acceptance Criteria**:

1. WHEN Animation mode is checked THEN the dialog SHALL show an additional "Animation
   description" text field (optional) and SHALL force grid framing on (the "Frame in a grid"
   checkbox becomes irrelevant/locked while Animation mode is on, since animation cannot work
   without the grid).
2. WHEN Generate is clicked with Animation mode on THEN the backend SHALL be instructed to draw
   a sequential animation frame in EACH of the 16 cells (row-major order: left-to-right, then
   top-to-bottom), consistent character scale/position/design across frames, instead of leaving
   15 cells blank.
3. WHEN the response image comes back THEN the system SHALL slice all 16 cells (same
   relative-fraction technique as AC2 of the grid story above), and, inside one
   `app.transaction`, write cell 1..16 as 16 consecutive sprite frames starting at the frame
   that was active when Generate was clicked (not when the job finishes — mirrors the existing
   frame/layer capture-at-click-time behavior).
4. WHEN the sprite doesn't already have enough frames to hold all 16 THEN the system SHALL
   append new empty frames at the end of the timeline as needed (never insert/shift existing
   frames).
5. WHEN "Apply to" is "New layer" THEN a new layer SHALL be created once and receive all 16
   cels; WHEN it's "Replace current cel" THEN the current layer's cels for those 16 frames SHALL
   be replaced (created if missing on that layer/frame), mirroring today's single-edit
   new_layer/replace semantics.
6. WHEN Animation mode is on and the prompt/description is empty THEN the system SHALL still
   send a valid request (generic "sequential animation frames" instruction, no named action).

**Independent Test**: Check Animation mode, type "walk", click Generate on a sprite with 1
frame; after it finishes, the sprite SHALL have at least 16 frames with 16 different cels on
the target layer, playable frame-by-frame.

---

### P2: Auto-created Aseprite Tag for the animation

**User Story**: As a pixel artist, I want the 16 new frames already grouped into a named,
playable Aseprite Tag right after generation, so I don't have to do it by hand.

**Why P2**: Valuable polish, but the feature is usable (frames exist, scrubbable) without it.

**Acceptance Criteria**:

1. WHEN animation generation finishes successfully THEN the system SHALL create one Tag
   spanning exactly the 16 new frames.
2. WHEN an animation description was provided THEN the Tag's name SHALL be derived from it
   (truncated to a safe length, mirroring the existing `data.prompt:sub(1, 24)` layer-naming
   pattern); WHEN it was left blank THEN the Tag SHALL get a generic fallback name.

**Independent Test**: After a successful animation generation, open the Timeline's tag list and
confirm a new tag exists covering exactly those 16 frames with the expected name.

---

### P2: Explicit `--animation` backend contract

**User Story**: As the maintainer of `kobixel-gemini-web` (and any future backend), I want a
documented, explicit way to know a request is for animation and what the animation is, so I
don't have to sniff it out of the free-text prompt.

**Why P2**: Needed for `edit.mjs` to actually implement the animation-mode prompt (P1 story
above depends on the backend understanding the request), but it's a contract/plumbing detail,
not directly user-visible beyond "animation works".

**Acceptance Criteria**:

1. WHEN `kobixel.lua` builds the external command THEN it SHALL always substitute a new
   `{animation}` placeholder (empty string when Animation mode is off), the same way `{width}`/
   `{height}` are always substituted today.
2. WHEN `edit.mjs` receives a non-empty `--animation` value THEN it SHALL build a distinct
   16-cell-fill instruction (per the Animation story's AC2) instead of the single-cell-edit
   instruction.
3. WHEN `edit.mjs` receives an empty/absent `--animation` value THEN its behavior SHALL be
   unchanged from today (single top-left-cell instruction, just worded for 16 cells per the grid
   story).
4. WHEN `edit.test.mjs` runs THEN it SHALL cover both branches of `buildPixelArtInstructions`
   (with and without an animation description) with exact-equality assertions, following the
   existing test file's style.
5. WHEN CLAUDE.md's "Any new backend must implement..." contract paragraph is read THEN it
   SHALL also mention the optional `--animation` flag as part of the contract for new backends.

**Independent Test**: `node --test tools/kobixel-gemini-web/edit.test.mjs` passes with new cases
for the animation branch.

---

## Edge Cases

- WHEN the sprite has fewer remaining frames than needed for the 16-frame block THEN the system
  SHALL append empty frames at the end of the timeline (never shift/insert existing frames).
- WHEN there's an active selection THEN each of the 16 extracted cells SHALL be resampled to the
  selection's size, same as today's single-result path uses the selection rect.
- WHEN the model doesn't return the exact canvas size sent (resolution normalization) THEN each
  of the 16 cells SHALL still be extracted correctly via relative-fraction cropping, not an
  absolute pixel offset.
- WHEN Animation mode is on and the user also has "Frame in a grid" unchecked THEN the system
  SHALL still use the grid (Animation mode implies grid framing; the checkbox is locked/ignored
  while Animation mode is on — see P1 Animation story AC1).
- WHEN the animation description is left blank THEN the request SHALL still be sent (generic
  animation instruction) and the auto-created Tag SHALL fall back to a generic name.
- WHEN a very high "Upscale before sending" value is combined with Animation mode's 4x4 grid
  (16x the pixel area of a single cell vs. today's 4x for 2x2) THEN the system SHALL NOT
  auto-adjust anything — this is a documented limitation, not a bug (see design.md Tech
  Decisions and Out of Scope above).

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| --- | --- | --- | --- |
| GRID-01 | P1: 4x4 grid replaces 2x2 | Implementing (T1) | Implementing — awaiting T7 manual UAT |
| GRID-02 | P1: 4x4 grid replaces 2x2 (crop-back) | Implementing (T2) | Implementing — awaiting T7 manual UAT |
| GRID-03 | P1: 4x4 grid replaces 2x2 (prompt wording) | Implementing (T6) | Implementing — awaiting T7 manual UAT |
| ANIM-01 | P1: Animation mode UI | Implementing (T3) | Implementing — awaiting T7 manual UAT |
| ANIM-02 | P1: Animation mode prompt (fill all 16 cells) | Implementing (T6) | Verified — `edit.test.mjs` passing (8/8) |
| ANIM-03 | P1: Animation mode frame slicing + timeline write | Implementing (T2, T5) | Implementing — awaiting T7 manual UAT |
| ANIM-04 | P1: Animation mode frame auto-extend | Implementing (T5) | Implementing — awaiting T7 manual UAT |
| ANIM-05 | P1: Animation mode new_layer/replace semantics | Implementing (T5) | Implementing — awaiting T7 manual UAT |
| TAG-01 | P2: Auto-created Tag | Implementing (T5) | Implementing — awaiting T7 manual UAT |
| BACK-01 | P2: `{animation}` placeholder always substituted | Implementing (T4) | Implementing — awaiting T7 manual UAT |
| BACK-02 | P2: `edit.mjs` animation branch | Implementing (T6) | Verified — `edit.test.mjs` passing (8/8) |
| BACK-03 | P2: `edit.test.mjs` coverage | Implementing (T6) | Verified — 4 new tests added, 8/8 passing |
| BACK-04 | P2: CLAUDE.md contract doc update | Implementing (T8) | Done — CLAUDE.md updated |

**Coverage:** 13 total, 13 mapped to tasks, 0 unmapped. 4 Verified/Done, 9 Implementing (awaiting
manual UAT in T7 — the extension package is built as `kobixel-0.4.0.aseprite-extension`, ready
to install).

---

## Success Criteria

- [ ] A single-edit request (Animation off) looks and behaves identically to today's validated
      2x2 behavior, just on a 4x4 grid
- [ ] One Generate click with Animation mode on produces 16 distinct, correctly-ordered frames
      on the sprite's timeline, wrapped in one undoable transaction
- [ ] `node --test tools/kobixel-gemini-web/edit.test.mjs` passes, including new animation-branch
      cases
- [ ] CHANGELOG.md has an `[Unreleased]` entry describing both changes; version bumped via
      `release.ps1` before shipping
