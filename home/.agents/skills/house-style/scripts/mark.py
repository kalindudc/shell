#!/usr/bin/env python3
"""Draw a site's seal: its initial in Source Serif 4 Italic, the face of every heading's turn,
inside a ring like the rings that mark each part. The letters are outlines (mark-glyphs.json),
so the seal needs no font and draws the same in the header and in a browser tab.

  python3 scripts/mark.py S                        the inline SVG for the header's home link
  python3 scripts/mark.py S --favicon favicon.svg  the favicon too

The inline seal is coloured by the kit (.seal .edge and .seal .glyph are --tint), so it follows
the theme. The favicon is the same seal filled, the initial knocked out of a disc of the tint,
since a hairline ring vanishes at 16px; it cannot read the page's properties, so it carries
each theme's hex. Pass --tint when the site's voice is not orange.

Outlines from Source Serif 4 (c) Adobe, SIL Open Font License 1.1 (fonts/LICENSE.md), set at
weight 600 and optical size 24 by mark-glyphs.py."""
import argparse, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
TINTS = {"blue": ("#3f6b78", "#7daea3"), "aqua": ("#3d6a51", "#89b482"), "orange": ("#8c4b19", "#e78a4e"),
         "purple": ("#6e4b67", "#d3869b"), "red": ("#9d3a2e", "#ea6962"), "green": ("#566326", "#a9b665")}
ON_ACCENT = ("#fbf9f4", "#1d1c1a")


def letters(text, cap):
    """Paths for one or two capitals, their ink centred on the seal; italics lean right, so the
    centre sits a little right of the middle to look centred."""
    font = json.load(open(os.path.join(HERE, "mark-glyphs.json")))
    text = text.upper()
    if not 1 <= len(text) <= 2 or any(ch not in font["glyphs"] for ch in text):
        sys.exit("a seal holds one or two of A to Z and 0 to 9")
    scale = cap / font["capHeight"]
    placed, x = [], 0.0
    for i, ch in enumerate(text):
        glyph = font["glyphs"][ch]
        placed.append((ch, x))
        x += glyph["advance"] * (0.86 if i == 0 and len(text) == 2 else 1)
    x0 = min(font["glyphs"][ch]["bounds"][0] + dx for ch, dx in placed)
    x1 = max(font["glyphs"][ch]["bounds"][2] + dx for ch, dx in placed)
    y0 = min(font["glyphs"][ch]["bounds"][1] for ch, _ in placed)
    y1 = max(font["glyphs"][ch]["bounds"][3] for ch, _ in placed)
    cx, cy = 16.4, 16.0
    tx = cx - (x0 + x1) / 2 * scale
    ty = cy - (y0 + y1) / 2 * scale
    return "".join(f'<path class="glyph" transform="translate({tx + dx * scale:.2f} {ty:.2f}) scale({scale:.5f})" d="{font["glyphs"][ch]["d"]}"/>' for ch, dx in placed)


def inline(text):
    cap = 15.5 if len(text) == 1 else 11
    return ('<svg class="mark seal" viewBox="0 0 32 32" aria-hidden="true"><circle class="edge" cx="16" cy="16" r="14.75"/>'
            + letters(text, cap) + "</svg>")


def favicon(text, light, dark):
    cap = 17 if len(text) == 1 else 12
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
  <style>
    .disc {{ fill: {light}; }} .glyph {{ fill: {ON_ACCENT[0]}; }}
    @media (prefers-color-scheme: dark) {{ .disc {{ fill: {dark}; }} .glyph {{ fill: {ON_ACCENT[1]}; }} }}
  </style>
  <circle class="disc" cx="16" cy="16" r="16"/>
  {letters(text, cap)}
</svg>
"""


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("letters")
    parser.add_argument("--favicon")
    parser.add_argument("--tint", default="orange", choices=sorted(TINTS))
    parser.add_argument("--light")
    parser.add_argument("--dark")
    args = parser.parse_args()
    light, dark = TINTS[args.tint]
    if args.favicon:
        open(args.favicon, "w").write(favicon(args.letters, args.light or light, args.dark or dark))
    print(inline(args.letters))
