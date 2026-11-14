# Before Anyone Sees It

What to run and look at before a page is shown, published or handed over, and after every change to it. Run the checks in a real browser, headless where it can be, on the page as it will be published. A page failing any step is reported as unfinished with each failure named.

## The Gate, in Order

1. The parts and the guard. Evaluate `scripts/gate.js` whole in the page (Puppeteer's `page.evaluate(source)`, a browser tool's evaluate, or the devtools console). It answers with what the page lacks or gets wrong: the head's names and favicon, the header with its seal, route, Keys button and switch, one title and the brief, the skip link, a Keys list that ? opens and Escape closes, the Markdown twin and `llms.txt`, the byline, a figure for each part (or `data-figure` saying why), drawing labels under 12px, serif text under 15px, lines of prose over 84 characters, requests that leave the site, colours typed into `style` attributes, and private traces (paths, thread ids, TODOs). It presses keys, so run it on a page nobody is reading. An empty list passes. Run it at 320, 390, 768 and 1400px, in both themes.
2. Accessibility and layout, measured. Run the `ux-design` skill's `scripts/audit-page.js` at 1400px in light and dark, and at 390px with `window.__uxAuditOptions = { minTarget: 44 }`. Mark the narrative (ledes, part openings, captions, prose and points' sentences) with `data-content` first, so its long-block count covers interface text only. Expect 0 contrast failures, 0 horizontal overflow, 0 text outside its box and 0 overlapping text; confirm every other count on a screenshot before reporting it. 
3. Look. Screenshot the first screen at 1400 by 900 and 390 by 844 in light and dark, and zoomed crops at device scale 2 of every drawing, plate row, table and the memo head. Look at each one yourself before claiming anything about it.
4. Beside the model. Open the page beside `starter/index.html` or `starter/overview.html`, part by part, and list what the model has that this page lacks: the seal, the route, the brief, a numbered frame, a fold, a state, a caption. Add each or say why it is gone. When the page joins a site, compare it with the site's other pages at about 1700px wide: widths, rules and spacing must match.
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

## Publishing a Quick Site

After deploying, fetch the live page back and look at it; never trust the deploy's own report. Quick sites are behind single sign-on, so a plain headless browser cannot open them: fetch the files with `quick curl <url>` and serve them locally to run the gate, or open the live page in a browser session that is already signed in.
