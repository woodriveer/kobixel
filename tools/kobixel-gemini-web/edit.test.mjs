import { test } from "node:test";
import assert from "node:assert/strict";
import {
  buildPixelArtInstructions,
  BASE_PIXEL_ART_INSTRUCTIONS,
  BASE_ANIMATION_INSTRUCTIONS,
} from "./edit.mjs";

// Spec: prompt-context-audit-i18n, CTX-02 AC2/AC3.
//
// Exact-equality (not regex) assertions on the "no dimensions" branches:
// a regex like /\d+x\d+/ would miss a boundary bug where only one of
// width/height is set (e.g. "512xundefined" doesn't match \d+x\d+ either,
// so a looser assertion would silently let that bug through).

test("includes the real WxH when both width and height are given", () => {
  const result = buildPixelArtInstructions({ width: "512", height: "512" });
  assert.equal(
    result,
    `${BASE_PIXEL_ART_INSTRUCTIONS} Use canvas size as 512x512 pixels.`,
  );
});

test("returns exactly the base instructions when dimensions are missing", () => {
  const result = buildPixelArtInstructions({});
  assert.equal(result, BASE_PIXEL_ART_INSTRUCTIONS);
});

test("returns exactly the base instructions when only width is given", () => {
  const result = buildPixelArtInstructions({ width: "512" });
  assert.equal(result, BASE_PIXEL_ART_INSTRUCTIONS);
});

test("returns exactly the base instructions when only height is given", () => {
  const result = buildPixelArtInstructions({ height: "512" });
  assert.equal(result, BASE_PIXEL_ART_INSTRUCTIONS);
});

// Spec: grid-4x4-animation, BACK-02/BACK-03.

test("switches to the animation instructions and names the animation when given", () => {
  const result = buildPixelArtInstructions({ animation: "walk" });
  assert.equal(
    result,
    `${BASE_ANIMATION_INSTRUCTIONS} The animation is: walk.`,
  );
});

test("combines animation and canvas-size instructions when both are given", () => {
  const result = buildPixelArtInstructions({
    animation: "walk",
    width: "512",
    height: "512",
  });
  assert.equal(
    result,
    `${BASE_ANIMATION_INSTRUCTIONS} The animation is: walk. Use canvas size as 512x512 pixels.`,
  );
});

test("returns exactly the base (non-animation) instructions when animation is an empty string", () => {
  const result = buildPixelArtInstructions({ animation: "" });
  assert.equal(result, BASE_PIXEL_ART_INSTRUCTIONS);
});

test("returns exactly the base (non-animation) instructions when animation is omitted", () => {
  const result = buildPixelArtInstructions({});
  assert.equal(result, BASE_PIXEL_ART_INSTRUCTIONS);
});
