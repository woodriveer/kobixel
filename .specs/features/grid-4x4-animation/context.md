# 4x4 Grid + Animation Mode Context

**Gathered:** 2026-09-21
**Spec:** `.specs/features/grid-4x4-animation/spec.md`
**Status:** Ready for design

---

## Feature Boundary

Replace the existing 2x2 "frame in a quadrant" grid with a 4x4 (16-cell) grid, and add an
Animation mode that fills all 16 cells with sequential animation frames instead of leaving 15
blank, sliced back into real Aseprite timeline frames.

---

## Implementation Decisions

### Grid scope (2x2 vs 4x4)

- The 4x4 grid **replaces** the 2x2 grid outright — one grid mechanism, not two, and not a
  user-configurable grid size.
- For single-edit mode (Animation off), the prompt instruction changes **only the numbers**
  (4 quadrants → 16 cells, "four"/"three" → "sixteen"/"fifteen") — no new constraint or added
  instruction beyond what already existed for the 2x2 case.
- For Animation mode, the prompt instruction explicitly tells the model to draw in **all**
  cells (not leave any blank) — this is the one place new instruction text is added.

### Starting frame for the 16 generated frames

- The animation's 16 frames start at the frame that was **active when Generate was clicked**
  (`app.frame` captured at click time), not always frame 1. This mirrors the existing
  `frameNumber`/`targetLayer` capture-at-click-time behavior already documented in
  `kobixel.lua`'s `finalizeResult` comment (protects against the user switching frames during
  the 30-90s+ background wait).

### Aseprite Tag auto-creation

- Yes — after a successful animation generation, auto-create a Tag spanning exactly the 16 new
  frames, named from the animation description (truncated), so the result is immediately
  playable/organized without a manual step.

### Backend contract for animation

- New optional CLI flag `--animation "<description>"`, following the exact precedent set by
  `--width`/`--height` in `edit.mjs`: always substituted by `kobixel.lua` (empty string when
  Animation mode is off), parsed with the existing `optionalArg` helper, and used by the backend
  to choose which instruction branch to build. The user's free-text `{prompt}` stays untouched
  by animation-specific wording — same separation of concerns as the existing fidelity
  instruction being appended in `kobixel.lua` rather than baked into the prompt field.

### Agent's Discretion

- Exact grid-line thickness/gutter math generalization from 2x2 to 4x4 (interior dividers vs.
  the old single-divider design) — implementation detail, no user-facing behavior choice.
- Tag fallback name text when the animation description is left blank.
- Exact wording of the new dialog label/help text for Animation mode and the grid checkbox.
- How the "Frame in a grid" checkbox visually reflects being locked/forced-on while Animation
  mode is active (disabled + checked vs. just ignored) — pick whatever Aseprite's Dialog API
  supports cleanly (see design.md).

---

## Specific References

- The existing `frameInQuadrant`/`cropTopLeft`/`BASE_PIXEL_ART_INSTRUCTIONS` mechanism
  (`kobixel.lua:327-361`, `tools/kobixel-gemini-web/edit.mjs:55-73`) is the validated pattern to
  generalize — same relative-fraction crop-back technique, same "black gutter dividing the
  canvas" visual trick, same style of prompt sentence.
- User's own framing: "não deve indicar nenhuma outra instrução" (single-edit mode prompt text
  should change ONLY the cell-count numbers) and "quando ligar o modo animação deve instruir o
  agente a desenhar em todos quadrantes" (Animation mode's prompt text should tell the model to
  draw in every cell) — both taken as literal constraints on the prompt-text design, not just
  paraphrase.

---

## Deferred Ideas

- Configurable grid size (e.g. a dropdown for 2x2/3x3/4x4) — explicitly out of scope per the
  user's "instead of 4 quadrants" framing (replacement, not a new option).
- Auto-adjusting the "Upscale before sending" slider based on grid size to cap total sent-image
  resolution — not requested; documented as a known limitation instead (see spec.md Edge Cases
  and design.md Tech Decisions).
- Custom per-frame timing/`aniDir` on the auto-created Tag — not requested; Aseprite's default
  new-frame duration and Tag defaults are used as-is.
