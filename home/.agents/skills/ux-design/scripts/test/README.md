# Audit regression tests

These minimal HTML fixtures exercise clipping and rendered sizes in a real browser. The runner uses Node's built-in modules and an existing bb headless browser session; it installs no packages.

Open a session on the same host as these files:

```sh
bb status --json
bb browser-automation open --backend local --headless --machine <host-id> --json
```

Keep the returned session ID. Run from this directory:

```sh
node run.mjs --session <session-id> --host <host-id> --output /tmp/ux-audit-after.json
bb browser-automation close <session-id> --json
```

The runner fixes the viewport at 800 by 600 CSS pixels and evaluates the actual audit source in each page. It sends at most four reports per browser call to stay below the CLI's response limit. Failed assertions give a nonzero exit code.

To compare revisions, first save the original audit outside the checkout and run it with the same fixtures:

```sh
node run.mjs --session <session-id> --host <host-id> --audit /tmp/original-audit-page.js --output /tmp/ux-audit-before.json
node run.mjs --session <session-id> --host <host-id> --compare /tmp/ux-audit-before.json --output /tmp/ux-audit-after.json
```

The original audit is expected to fail the regression assertions. The comparison checks the report and summary keys on every case, and exact equality of the complete unscaled and plain-offscreen baseline reports.

## Fixtures

- `fixtures/clipping.html?clip=<mode>` checks `paint`, `layout-paint`, `strict`, `content`, `clip`, `hidden`, `auto`, `x-clip` and `y-clip`. A wide child must not count as viewport overflow when horizontally clipped. A hidden label must not overlap a label outside the pan window. Vertical-only clipping must leave real horizontal overflow and overlaps detectable. The `y-hidden` case checks a wide child completely hidden vertically; `y-hidden-spill` adds real, unclipped text overflow to check the document-level fallback.
- `fixtures/offscreen.html` has two genuinely offscreen elements inside an ancestor with inline `overflow: visible`. They must both be counted. `?plain=true` removes that declaration and checks unchanged behaviour without the selector-heuristic case.
- `fixtures/scaling.html?mode=<mode>` checks scaled-down block and inline labels, scaled-up labels, zoom, nested scales, combined zoom and transforms, and the individual CSS `scale` property. Downscaled labels render at 7.7 px. Crowded 30 px targets render at 21 px and must be flagged; 16 px targets scaled up to 32 px must not be flagged.
- `fixtures/svg-scaling.html` checks a downscaled SVG label.
- `fixtures/baseline.html` checks an ordinary page, including a 10 px label and an 11 px label with fractional line height. Its complete report must remain unchanged.
