#!/usr/bin/env node
// Edits a pixel-art PNG using Google Gemini's Nano Banana, driven through
// YOUR OWN already-open, already-logged-in Chrome window (Gemini Pro/Ultra
// subscription quota) — no API key, no Claude agent loop.
//
// Google blocks Google-account sign-in attempted from a browser Playwright
// launched itself ("This browser or app may not be secure"), even with a
// real Chrome binary. The fix is to never let Playwright launch or log in
// the browser at all: you start Chrome yourself, normally, with a debug
// port open, sign in by hand once, and this script only ATTACHES to that
// already-authenticated instance via chrome-remote-debugging.
//
// One-time setup, run yourself (not via this script):
//   "C:\Program Files\Google\Chrome\Application\chrome.exe" ^
//     --user-data-dir="%USERPROFILE%\.kobixel\chrome-profile" ^
//     --remote-debugging-port=9222 https://gemini.google.com/app
// Log into your Google account in that window, confirm the Gemini prompt
// box works, and leave the window open (don't close it — this script needs
// the running process, not just the saved profile).
//
// Usage (matches the Aseprite extension's {input}/{output}/{prompt}):
//   node edit.mjs --in "{input}" --out "{output}" --prompt "{prompt}" --width "{width}" --height "{height}" --animation "{animation}"

import { chromium } from "playwright";
import { mkdirSync, realpathSync } from "node:fs";
import { writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";

function arg(name) {
  const i = process.argv.indexOf(`--${name}`);
  if (i === -1 || !process.argv[i + 1]) {
    console.error(`Missing required --${name}`);
    process.exit(1);
  }
  return process.argv[i + 1];
}

// Like arg(), but returns undefined instead of exiting when the flag is
// absent — {width}/{height} are optional so a hand-edited "External
// command" field without them keeps working.
function optionalArg(name) {
  const i = process.argv.indexOf(`--${name}`);
  if (i === -1 || !process.argv[i + 1]) return undefined;
  return process.argv[i + 1];
}

// The second sentence is a no-op when kobixel.lua's "Frame in a 4x4 grid"
// option is off (there's no grid in the image, so the "if" doesn't apply)
// and load-bearing when it's on: it's the piece of prompt text that tells
// Nano Banana to treat the marked cell as a hard boundary. Kept as one
// unconditional instruction (rather than a flag threaded through the CLI
// args) so this file doesn't need to know whether the image it received
// was actually framed - it just describes what to do in either case.
export const BASE_PIXEL_ART_INSTRUCTIONS =
  "This is pixel art. Preserve the exact pixel grid: no anti-aliasing, " +
  "no smoothing, no gradients, no blur. If this image has a black grid " +
  "dividing it into 16 cells (4x4) with content only in the top-left " +
  "cell, edit ONLY inside that top-left cell, keep the grid lines " +
  "exactly where they are, and leave the other 15 cells pure white - do " +
  "not draw anything there, and do not resize, move, or redraw the grid " +
  "boundaries.";

// Animation mode's counterpart of BASE_PIXEL_ART_INSTRUCTIONS: instead of
// leaving 15 of the 16 grid cells blank, this tells the model to fill
// EVERY cell with a different frame of the same animated asset.
// kobixel.lua's sliceGrid then extracts all 16 in the exact row-major
// order this text describes (cell 1 = top-left, cell 16 = bottom-right).
export const BASE_ANIMATION_INSTRUCTIONS =
  "This is pixel art. Preserve the exact pixel grid: no anti-aliasing, " +
  "no smoothing, no gradients, no blur. This image has a black grid " +
  "dividing it into 16 cells (4x4). Draw a sequential animation frame of " +
  "the same character/asset in EVERY one of the 16 cells, in reading " +
  "order (left to right, then top to bottom - cell 1 is top-left, cell " +
  "16 is bottom-right). Do not leave any cell blank. Keep the " +
  "character's design, proportions, and scale consistent across all 16 " +
  "frames, changing only the pose/motion between them. Keep the grid " +
  "lines exactly where they are, and do not resize, move, or redraw the " +
  "grid boundaries.";

// Builds the full instruction text. `animation` (when non-empty) switches
// from the single-cell-edit instructions to the fill-all-cells animation
// instructions and names the requested animation; the canvas-size sentence
// is built from the REAL dimensions of the image actually sent
// (data.upscale in kobixel.lua changes this per-sprite), instead of a
// fixed claim that used to say "256x256" regardless of what was really
// uploaded.
export function buildPixelArtInstructions({ width, height, animation } = {}) {
  let text = animation ? BASE_ANIMATION_INSTRUCTIONS : BASE_PIXEL_ART_INSTRUCTIONS;
  if (animation) {
    text = `${text} The animation is: ${animation}.`;
  }
  if (width && height) {
    text = `${text} Use canvas size as ${width}x${height} pixels.`;
  }
  return text;
}

const DEBUG_URL = "http://localhost:9222";
const TOTAL_STEPS = 7;

// Printed to stderr (captured in gemini.log by the Aseprite extension) so
// the Lua side has something meaningful to tail into its progress dialog.
function step(n, text) {
  console.error(`[${n}/${TOTAL_STEPS}] ${text}`);
}

async function main() {
  const inPath = path.resolve(arg("in"));
  const outPath = path.resolve(arg("out"));
  const prompt = arg("prompt");
  const width = optionalArg("width");
  const height = optionalArg("height");
  const animation = optionalArg("animation");
  const PIXEL_ART_INSTRUCTIONS = buildPixelArtInstructions({ width, height, animation });

  let browser;
  try {
    step(1, "Connecting to your Chrome window...");
    browser = await chromium.connectOverCDP(DEBUG_URL);
  } catch {
    console.error(
      `Could not connect to Chrome's debug port at ${DEBUG_URL}.\n` +
        "Start Chrome yourself first (see the comment at the top of this " +
        "script for the exact command) and make sure you're signed in and " +
        "the window is still open, then try again.",
    );
    process.exit(1);
  }

  try {
    step(2, "Opening Gemini...");
    const context = browser.contexts()[0];
    const page =
      context.pages().find((p) => p.url().includes("gemini.google.com")) ??
      (await context.newPage());
    if (!page.url().includes("gemini.google.com")) {
      await page.goto("https://gemini.google.com/app", {
        waitUntil: "domcontentloaded",
      });
    }

    let composeBox = page.locator('div[contenteditable="true"]').first();
    const isReady = await composeBox
      .isVisible({ timeout: 10_000 })
      .catch(() => false);
    if (!isReady) {
      throw new Error(
        "Gemini's prompt box isn't visible — make sure you're signed in " +
          "in the Chrome window this script connected to.",
      );
    }

    step(3, "Starting a new chat...");
    // Reusing an existing conversation is why the "wait for the generated
    // image" step below used to return instantly: a chat with prior turns
    // already has a large <img> on the page, so "some image is big enough"
    // was already true before Nano Banana ever ran on THIS request. Starting
    // fresh each time also keeps the conversation (and its token cost) from
    // growing forever across many edits.
    // "Nova conversa" is a sidebar <a> list item, not a <button role="button">
    // — matching by role silently never found it, so the click was skipped
    // every time and the conversation kept growing across runs.
    const newChatButton = page.getByText(/^(Nova conversa|New chat)$/).first();
    if (await newChatButton.isVisible({ timeout: 3000 }).catch(() => false)) {
      await newChatButton.click();
      composeBox = page.locator('div[contenteditable="true"]').first();
      await composeBox.waitFor({ state: "visible", timeout: 10_000 });
    }

    step(4, "Uploading input image...");
    // Attach the input image, intercepting the native file chooser instead of
    // trying to click through it (there is no visible dialog to drive).
    await page
      .getByRole("button", { name: /Envio e ferramentas|Upload files/i })
      .click();
    const [chooser] = await Promise.all([
      page.waitForEvent("filechooser"),
      page.getByText(/Enviar arquivos|Upload files/i).click(),
    ]);
    await chooser.setFiles(inPath);

    // Give the thumbnail preview a moment to attach before typing, so the
    // image is actually part of the turn we submit.
    await page.waitForTimeout(1500);

    // Baseline BEFORE submitting: even on a fresh chat this stays a valid
    // belt-and-suspenders check (e.g. if "New chat" wasn't found above), and
    // it's what actually confirms the wait below is for a NEW image rather
    // than one already sitting on the page from a previous turn.
    const bigImageCountBefore = await page.evaluate(
      () =>
        Array.from(document.querySelectorAll("img")).filter(
          (i) => i.naturalWidth >= 512,
        ).length,
    );

    step(5, "Sending prompt...");
    await composeBox.click();
    await composeBox.type(`${prompt} ${PIXEL_ART_INSTRUCTIONS}`);
    await page.keyboard.press("Enter");

    step(6, "Waiting for Nano Banana to generate the image...");
    // Poll (not just a one-shot check) for the count of large, fully-loaded
    // images to exceed what it was before we submitted — avatars/icons are
    // much smaller than a generated image (1024px+), and requiring a net
    // INCREASE (not just "one exists") is what actually proves THIS request
    // produced a new image, rather than the check trivially passing because
    // of a leftover image already on the page.
    await page.waitForFunction(
      (before) =>
        Array.from(document.querySelectorAll("img")).filter(
          (i) => i.naturalWidth >= 512 && i.complete,
        ).length > before,
      bigImageCountBefore,
      { timeout: 60_000, polling: 500 },
    );

    step(7, "Extracting and saving result...");
    // Extract the actual pixel data losslessly via canvas, rather than using
    // the UI's own download button (which re-encodes as JPEG) or the OS
    // clipboard (which flattens to opaque RGB) — both lose the alpha channel
    // if the source image has one.
    const dataUrl = await page.evaluate(() => {
      const img = Array.from(document.querySelectorAll("img"))
        .filter((i) => i.naturalWidth >= 512)
        .pop();
      const canvas = document.createElement("canvas");
      canvas.width = img.naturalWidth;
      canvas.height = img.naturalHeight;
      canvas.getContext("2d").drawImage(img, 0, 0);
      return canvas.toDataURL("image/png");
    });

    const base64 = dataUrl.split(",")[1];
    mkdirSync(path.dirname(outPath), { recursive: true });
    await writeFile(outPath, Buffer.from(base64, "base64"));

    console.log(`Wrote ${outPath}`);
  } finally {
    // Deliberately not closing anything here: this browser is the user's own,
    // already-open window that we only attached to — closing it would kill
    // their session. Just let the process exit; that drops our CDP
    // connection without touching the browser itself.
  }
}

// Only run the CLI when this file is executed directly (`node edit.mjs ...`),
// not when it's imported (e.g. by edit.test.mjs) — otherwise importing it to
// reach buildPixelArtInstructions would try to connect to Chrome.
//
// realpathSync matters here: `npm install -g .` on a local path symlinks the
// package instead of copying it, so the generated bin shim invokes this file
// through a symlinked path. Node's ESM loader resolves import.meta.url past
// that symlink, but process.argv[1] keeps the literal (unresolved) path —
// without realpathSync the two never match and main() silently never runs.
if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
  main();
}
