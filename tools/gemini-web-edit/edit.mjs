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
//     --user-data-dir="%USERPROFILE%\.repixel-ai\chrome-profile" ^
//     --remote-debugging-port=9222 https://gemini.google.com/app
// Log into your Google account in that window, confirm the Gemini prompt
// box works, and leave the window open (don't close it — this script needs
// the running process, not just the saved profile).
//
// Usage (matches the Aseprite extension's {input}/{output}/{prompt}):
//   node edit.mjs --in "{input}" --out "{output}" --prompt "{prompt}"

import { chromium } from "playwright";
import { mkdirSync } from "node:fs";
import { writeFile } from "node:fs/promises";
import path from "node:path";

function arg(name) {
  const i = process.argv.indexOf(`--${name}`);
  if (i === -1 || !process.argv[i + 1]) {
    console.error(`Missing required --${name}`);
    process.exit(1);
  }
  return process.argv[i + 1];
}

const inPath = path.resolve(arg("in"));
const outPath = path.resolve(arg("out"));
const prompt = arg("prompt");

const PIXEL_ART_INSTRUCTIONS =
  "This is pixel art. Preserve the exact pixel grid: no anti-aliasing, " +
  "no smoothing, no gradients, no blur. " +
  "Use canvas size as 256x256 pixels";

const DEBUG_URL = "http://localhost:9222";
const TOTAL_STEPS = 7;

// Printed to stderr (captured in gemini.log by the Aseprite extension) so
// the Lua side has something meaningful to tail into its progress dialog.
function step(n, text) {
  console.error(`[${n}/${TOTAL_STEPS}] ${text}`);
}

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
