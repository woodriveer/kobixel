#!/usr/bin/env python3
"""CLI wrapper around the Gemini image API for the Aseprite "Gemini Edit" extension.

Talks directly to the Gemini API (google-genai), no extra CLI in the middle.

Setup:
    pip install google-genai
    setx GEMINI_API_KEY "your-api-key-here"   # get one at https://aistudio.google.com/apikey

Usage (matches the extension's {input}/{output}/{prompt} placeholders):
    python gemini_edit.py --in "{input}" --out "{output}" --prompt "{prompt}"

Model defaults to gemini-2.5-flash-image. Override with --model or the
GEMINI_IMAGE_MODEL env var (e.g. gemini-3-pro-image-preview).
"""
import argparse
import os
import sys

PIXEL_ART_INSTRUCTIONS = (
    "This is pixel art. Preserve the exact pixel grid: no anti-aliasing, "
    "no smoothing, no gradients, no blur. Use flat, solid colors only. "
    "Keep the transparent background transparent. Keep the same image "
    "dimensions and canvas framing."
)

DEFAULT_MODEL = "gemini-2.5-flash-image"


def main():
    parser = argparse.ArgumentParser(description="Edit a pixel-art PNG with Gemini.")
    parser.add_argument("--in", dest="input", required=True, help="input PNG path")
    parser.add_argument("--out", dest="output", required=True, help="output PNG path")
    parser.add_argument("--prompt", required=True, help="edit instructions")
    parser.add_argument(
        "--model",
        default=os.environ.get("GEMINI_IMAGE_MODEL", DEFAULT_MODEL),
        help="Gemini image model (default: %(default)s, or $GEMINI_IMAGE_MODEL)",
    )
    args = parser.parse_args()

    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        print("GEMINI_API_KEY is not set.", file=sys.stderr)
        sys.exit(1)

    if not os.path.isfile(args.input):
        print(f"Input file not found: {args.input}", file=sys.stderr)
        sys.exit(1)

    try:
        from google import genai
        from google.genai import types
    except ImportError:
        print("Missing dependency. Run: pip install google-genai", file=sys.stderr)
        sys.exit(1)

    client = genai.Client(api_key=api_key)

    with open(args.input, "rb") as f:
        image_bytes = f.read()

    full_prompt = f"{args.prompt}\n\n{PIXEL_ART_INSTRUCTIONS}"

    response = client.models.generate_content(
        model=args.model,
        contents=[
            full_prompt,
            types.Part.from_bytes(data=image_bytes, mime_type="image/png"),
        ],
    )

    candidates = response.candidates or []
    parts = candidates[0].content.parts if candidates and candidates[0].content else []

    for part in parts:
        inline_data = getattr(part, "inline_data", None)
        if inline_data is not None and inline_data.data:
            with open(args.output, "wb") as f:
                f.write(inline_data.data)
            print(f"Wrote {args.output}")
            return

    print("Gemini did not return an image.", file=sys.stderr)
    text = getattr(response, "text", None)
    if text:
        print(text, file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()
