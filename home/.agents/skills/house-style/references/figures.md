# Drawing Figures

How to draw the figures, frames and marks on a house page so they look like the page rather than like a picture pasted into it. `starter/index.html` has a worked example of each.

## Inline SVG, in the Page's Own Ink

- Draw figures as inline `<svg>`, never as an image, so they take the page's faces, colours and theme changes. Give each `role="img"` with a `<title>` and a `<desc>` that says what it shows, and put it in a `<figure>` with a `<figcaption>` that says what to notice.
- Use the kit's ink classes instead of colours:

| Class | Draws |
| --- | --- |
| `d-line`, `d-dash` | connectors that carry meaning: `--stroke`, 3:1 on every surface, `vector-effect: non-scaling-stroke` |
| `d-thin` | gridlines and separators: decoration, in `--rule` |
| `d-node` | a thing: `--card` fill, `--stroke` edge |
| `d-tint` | the thing the figure is about: a soft tint fill, `--tint` stroke |
| `d-good`, `d-warn`, `d-bad`, `d-accent` | a thing in a state: the state's stroke, and a dash for warn and accent so shape says it too |
| `d-band` | a region or lane: `--deep` fill |
| `d-flow`, `d-arrow`, `d-arrow tint`, `d-dot` | the path the story follows, its arrowheads and markers |
| `d-text`, `d-text strong`, `d-text tint` | labels in the mono at 13px |
| `d-name` | a name in the serif at 16px, weight 600 |
| `d-voice` | an aside in the serif italic at 14px, such as "the same bytes, every job" |

- One emphasis per figure: the thing the caption names wears `d-tint` or a state; everything else stays in `d-node` and `d-line`. If three things pop, none does.
- Every colour means what it means everywhere on the page. Orange is a warning in the text, so it is a warning in the drawing.
- Labels are placed beside their things, with a leader line where needed, never only on hover, and never over another label at any width.
- Text inside a drawing is edited like prose: short, plain, no ids.

## Sizes: Drawn Twice, Never Shrunk

A label must never show under 12px on screen. A drawing scaled down to a phone shrinks its labels with it, so each drawing is made at the width it is shown and has a narrow twin.

| Where it sits | viewBox width | Labels | Swaps to narrow below |
| --- | --- | --- | --- |
| On the measure: `<figure class="fig">` | 600 | 13px | a 554px container |
| On the wide line: `<figure class="fig wide">` | 880 | 13px | an 812px container |
| In a plate | 300, shown at its own size | 13px | does not swap; the plate drops its frame on a phone |
| The narrow twin | 280, the column on a 320px phone | 13px | shown up to 340px wide |

Mark the two drawings `class="fig-wide"` and `class="fig-narrow"` inside one figure, each with its own `role="img"`, `<title>` and `<desc>`; the container query shows one and the screen reader hears it once. A narrow twin is a redrawing, not a crop: stack what sat side by side, put labels above bars, and drop what does not fit.

When a swap point differs (a drawing with 14px labels, say), compute it: the drawing may show while `container width ≥ 12 × viewBox width ÷ label size`, and add a container query for it in the site's CSS.

## Plates

Two drawings set side by side (before and after, today and next, two designs) go in `.plates`, each a `<figure class="plate">` with a header of two labels (the state on the left in the tint, a note on the right), a two-part `h3` and the drawing. Plates are one grid row and end level through subgrid, so their titles and drawings line up. One caption under the row says what changed; on a phone the plates stack and give up their frames.

## Charts

Draw simple charts as SVG by hand or with a small library, and read colours when drawing:

```js
house.onTheme(() => {
  const [first, second] = house.series();
  chart.update({ colors: [first, second], grid: house.color("--rule-soft"), text: house.color("--ink-soft") });
});
```

- `house.series()` returns blue, aqua, orange, purple, red and green in order; a series that is a state takes its state's colour instead.
- Axis labels and ticks in the mono at 12 to 13px, gridlines in `--rule-soft`, no chart border, no shadows, no 3D.
- Label lines at their ends instead of a legend where they fit; a legend, when needed, is the kit's `.legend`.
- Stacked bars use `.stackbar` with its 2px inset separators (SKILL.md rule 12); label a segment only where its text measures 4.5:1 on that colour.

## Mermaid

For a quick flow, Mermaid is acceptable when a hand drawing would not add anything. Initialize it from the theme and render again on a theme change:

```js
house.onTheme(async () => {
  mermaid.initialize({ startOnLoad: false, ...house.mermaid() });
  await mermaid.run({ nodes: document.querySelectorAll(".mermaid") });
});
```

Serve Mermaid from the site, not a CDN, and check its labels are 12px or larger on a phone; a wide flowchart usually needs a hand-drawn narrow twin.

## The Seal and the Favicon

- The seal is the site's mark: its initial in Source Serif 4 Italic at weight 600, the face of every heading's italic turn, inside a hairline ring like the ring that opens each part. It sits in the header's home link at 28px, before the site's name, and it is the one ornament the page owns.
- Draw it with `scripts/mark.py`, which sets the letter as outlines (no font needed) and writes the favicon from the same outlines: `python3 scripts/mark.py S --favicon favicon.svg` prints the inline SVG and writes the file. Pass `--tint` when the site's voice is not orange.
- The inline seal reads its colour from the kit (`.seal .edge` and `.seal .glyph` are `--voice`), so it follows the theme and the site's voice. A hairline ring vanishes at 16px, so the favicon is the same seal filled: the initial knocked out of a disc. It cannot read the page's properties, so it carries each theme's hex in a `prefers-color-scheme` media query; it is the one file where a hex is written.
- Pick the letter the reader would say: the product's initial ("S" for Shuttle), or two for a name of two words when one letter would collide with a sibling site. A site of several pages uses one seal everywhere.

## Framing and Numbering

- Every drawing sits in a hairline frame on `--card` with a barely-there dot every 24px, which the kit draws under `.fig > svg` and `.plate`. The dots are decoration only, a little darker than the frame and never as dark as a rule; nothing is aligned to them that a reader must read.
- A figure's caption closes its frame on a hairline and is numbered by the stylesheet, "Fig. 1", in the mono and the tint. A screenshot keeps its own hairline and takes the same numbered caption under it. Refer to a figure by its number in the prose only when the sentence would otherwise point at nothing.

## Ruled Parts

- Each part opens on a hairline across the wide line, with a ring on its left end. Where the margin beside the measure has room (960px and up) the part's numeral hangs in it, beside the label; narrower, the label carries the number inline ("02 / The idea").
- The ring of the part being read fills with the voice, and its stop on the route is marked current. Ring and numeral are drawn by the stylesheet and carry nothing a reader needs, since the label and the route say the same.

## What Is Not Ours

These belong to the web-design pages this style learned from, and they stay there: a centred masthead with a drawn emblem above the title, a fleuron or other ornament between parts, a drop cap, a centred caption, and the key line printed under the title. A page that has any of them reads as a copy. Our thresholds are the seal and the route, the memo head with its brief, the ruled parts and the numbered frames. The two-part heading is shared, by the user's choice.

- A pull quote (`.pull`) carries one person's words that make the argument; one a page at most. It hangs on a tinted rule at the left, never centred.
- Decoration is never put on the facts: no ornament on numbers, tables or controls.
