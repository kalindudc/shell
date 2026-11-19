# Before Anyone Sees It

What to run and look at before a page is shown, published or handed over, and after every change to it. Run the checks in a real browser, headless where it can be, on the page as it will be published. A page failing any step is reported as unfinished with each failure named.

## The Gate, in Order

1. The parts and the guard. Evaluate `scripts/gate.js` whole in the page (Puppeteer's `page.evaluate(source)`, a browser tool's evaluate, or the devtools console). It answers with what the page lacks or gets wrong:
   - UTF-8, the page's language, a title, an SVG favicon that loads, and the description, Open Graph title, description and type, and theme-colour metadata.
   - A main element and the header with its seal, a route linking every part, the Keys button and theme switch; exactly one visible title; and a brief with at least two facts. The project form must also be an overview, and may replace the brief with a headline of at least two cards.
   - A skip link as the first focusable element, pointing to an element on the page; a Keys list that ? opens and Escape closes with focus returned; and the Character shortcuts toggle.
   - A visible system dropdown: load the kit's script so the page draws every `<select>` itself.
   - Live status in the header (`.live`, `[data-live]` or `[aria-live]`): put it in the page beside what it describes.
   - A visible `.fact` in `main` without a non-empty `data-tip` naming its source and as-of time.
   - An open `details.group` whose non-empty set of `.rows .state` elements are all `.good`: leave out `open` so it starts folded.
   - A Markdown twin and root `llms.txt` that load non-empty content rather than HTML, and the exact foot byline, `by Kalindu De Costa`.
   - A figure for each part (or `data-figure` saying why it has none), and an SVG drawing on a page to read unless its main element explains why not.
   - Drawing labels under 12px on screen, serif text under 15px, prose lines over 84 characters, or prose whose longest non-final line is under 40 characters on a desk of at least 1024px.
   - Horizontal page overflow, including on a touch screen whose layout viewport has widened.
   - Text on the ground's wash below 4.5:1 contrast (3:1 for large text), or ground colours that cannot be measured as sRGB.
   - A visible, non-empty `.cat` chip without a readable, non-transparent pastel fill or with text contrast below 4.5:1 on its fill: use `.cat.c1` to `.cat.c7` and the matching `--cat-N-ink` on `--cat-N-soft`.
   - Requests that leave the site, colours typed as hex, RGB or HSL into `style` attributes, and private or unfinished traces in prose (machine paths, thread ids, local addresses, TODOs and placeholder text).

   It presses keys, so run it on a page nobody is reading. An empty list passes. Run it at 320, 390, 768 and 1400px, in both themes.
2. Accessibility and layout, measured. Run the `ux-design` skill's `scripts/audit-page.js` at 1400px in light and dark, and at 390px with `window.__uxAuditOptions = { minTarget: 44 }`. Mark the narrative (ledes, part openings, captions, prose and points' sentences) with `data-content` first, so its long-block count covers interface text only. Expect 0 contrast failures, 0 horizontal overflow, 0 text outside its box and 0 overlapping text; confirm every other count on a screenshot before reporting it. 
3. Look. Screenshot the first screen at 1400 by 900 and 390 by 844 in light and dark, and zoomed crops at device scale 2 of every drawing, plate row, table and the memo head. Look at each one yourself before claiming anything about it.
4. Beside the model. Open the page beside `starter/index.html`, `starter/overview.html` or, for the project form, `starter/project/index.html` or `board.html`, part by part, and list what the model has that this page lacks: the seal, the route, the brief, a numbered frame, a fold, a state, a caption. Add each or say why it is gone. When the page joins a site, compare it with the site's other pages at about 1700px wide: widths, rules and spacing must match.
5. Read the sentences only. Top to bottom, read the title, lede, part headings and part openings: they must give the answer, the reasons and the next step without the figures, and each figure must add something they do not. Then the cold-reader check in `references/writing.md`.

## Widths and States

Check at 320, 390, 768, 1024, 1400 and 1700px, in both themes, with every fold closed and then open. At each:

- Nothing scrolls sideways, nothing spills from its box, and no text runs over other text.
- Every top-level block starts and ends on the column's edges, or, if `.wide` or `.full`, extends the same distance past both edges.
- Things side by side end level, and opening a fold moves nothing beside or above it.
- Drawings show their wide form only where their labels stay at 12px or more.

Then once more with `prefers-reduced-motion: reduce` (nothing moves, the page is complete) and once with JavaScript off (the page is whole; only the keys, the switch and arrival are gone).

## Keys and Access

- Tab from the top: the skip link shows first; every control is reached once, in reading order, with the one focus ring.
- j, k, g and G step through the parts, and the heading each lands on is in plain view, not under a sticky bar; ? opens the Keys list; Escape closes it and focus returns; single letters do nothing in a field; the Keys list's Character shortcuts toggle turns all of them off across a reload; the header's ? button opens Keys by pointer; the ring of the part in view is filled and its stop on the route is current.
- The header in each form: the margin index at 1340px and 1400px shows every part and page name whole, with nothing clipped and no sideways scroll, and never overlaps the page; at 1100 to 1339px no two stops on the route row overlap, or the strip takes over; Tab and Shift-Tab through a sticky header leave the reading position where it was; at 390px the strip's button names the part in view, opens a menu below the strip with focus on the current part, and Escape closes it with focus back on the button.
- The switch: Light, Match System and Dark each hold across a reload with no flash of the other theme, and Match System follows the system when it changes.
- Turn the screenshot to greyscale: every state, series and selection still reads (WCAG 1.4.1).
- Each drawing's labels stay near the body text's size at every width, 12px and up but never larger than the prose beside them: measure them at 720px, where a phone drawing is most tempted to stretch.
- Each screenshot's caption ends in an Open full size link.
- Targets are at least 24px, and 44px on touch (emulate a phone with touch, `isMobile` and `hasTouch`), except links in running text.
- Meaningful strokes in every drawing (connectors, arrows, node edges) measure 3:1 against their surface in both themes; the kit's `--stroke` does, `--rule` does not.
- Each page's Markdown twin holds that page's facts: compare its numbers, rows and actions with the page, since the gate only checks that it loads.

## Speed

- No request leaves the site: fonts and scripts come from `kit/`. The first view's fonts are Source Serif 4 upright and italic and one weight of the mono, about 260KB together.
- No layout shift as fonts arrive (the stand-ins are matched), and none when a fold opens or the theme changes.
- Idle means zero: no timers, polling or animation frames while nothing changes.

## Loading Regions

Use the same grid or list for the skeleton and the real data. One frame per visible card or row is enough. Keep the short status outside the busy subtree so updates are not held until the request ends.

```html
<p class="skeleton-status" id="results-status" role="status">Loading results…</p>
<div id="results" aria-busy="true">
  <div class="skeleton-frame" aria-hidden="true">
    <span class="skeleton-line short"></span>
    <span class="skeleton-line"></span>
  </div>
</div>
<noscript><p>JavaScript is needed to load results. <a href="results.csv">Download the results.</a></p></noscript>
```

- Delay just the data request. The surrounding content and navigation must work before it resolves. The frames must fit the layout at 390 and 1400px in both themes, with no shimmer or other movement.
- Compare the region before and after data arrives. Reserve the first visible layout, not a placeholder for every row. Inactive tabs should not fetch or build their lists before being opened.
- Test success, no matches, an HTTP failure and JavaScript off. In every settled case, remove the frames and set `aria-busy` to false; clear the status on success or replace it with an actionable error on failure. On background refresh keep the real content visible and never steal focus.
- Inspect the accessibility tree: only the plain loading status is exposed, never the decorative frames. The tab order is the same with or without the frames.

## Publishing a Site Behind Single Sign-On

After deploying, fetch the live page back and look at it; never trust the deploy's own report. A plain headless browser cannot open a site behind single sign-on: fetch the files with the hosting platform's authenticated fetch command and serve them locally to run the gate, or open the live page in a browser session that is already signed in.
