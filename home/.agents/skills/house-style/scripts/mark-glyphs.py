"""Regenerate mark-glyphs.json, the outlines mark.py sets: the capitals and digits of Source Serif 4
Italic at weight 600 and optical size 24, flipped into SVG's y-down space.

  pip install fonttools brotli
  python3 scripts/mark-glyphs.py fonts/source-serif-4-italic.woff2 600 24 scripts/mark-glyphs.json"""
import json, sys
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.transformPen import TransformPen
src, wght, opsz, out = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
f = instancer.instantiateVariableFont(TTFont(src), {"wght": wght, "opsz": opsz})
gs = f.getGlyphSet(); cmap = f.getBestCmap()
res = {"font": f"Source Serif 4 Italic, weight {int(wght)}, optical size {int(opsz)}", "unitsPerEm": f['head'].unitsPerEm, "capHeight": f['OS/2'].sCapHeight, "glyphs": {}}
for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789":
    g = gs[cmap[ord(ch)]]
    bp = BoundsPen(gs); g.draw(bp)
    pen = SVGPathPen(gs, ntos=lambda v: ("%.1f" % v).rstrip("0").rstrip("."))
    g.draw(TransformPen(pen, (1, 0, 0, -1, 0, 0)))
    xmin, ymin, xmax, ymax = bp.bounds
    res["glyphs"][ch] = {"d": pen.getCommands(), "bounds": [xmin, -ymax, xmax, -ymin], "advance": g.width}
json.dump(res, open(out, "w"), separators=(",", ":"))
print("ok", len(res["glyphs"]), res["capHeight"])
