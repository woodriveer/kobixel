import { test } from "node:test";
import assert from "node:assert/strict";
import { buildPixelArtInstructions } from "./edit.mjs";

// Spec: prompt-context-audit-i18n, CTX-02 AC2/AC3.

test("includes the real WxH when both width and height are given", () => {
  const result = buildPixelArtInstructions({ width: "512", height: "512" });
  assert.match(result, /512x512/);
  assert.doesNotMatch(result, /256x256/);
});

test("omits any digit-based canvas-size clause when dimensions are missing", () => {
  const result = buildPixelArtInstructions({});
  assert.doesNotMatch(result, /\d+x\d+/);
});
