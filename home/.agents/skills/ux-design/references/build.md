# Build mode

Build from an approved brief: first explore, then converge on one direction, then build every screen and state in it. A mock and production UI follow the same rails; a mock is a self-contained HTML page, production is the product's own components.

## Theme and tokens

- Inside a host app, colours, radius and fonts come from the host's theme variables, so the surface follows whatever theme the person runs. Use the host's utilities or variables (its catalog entry lists them); never type a hex value in a component.
- In a standalone mock, load the product's real tokens as CSS variables with the same names: capture them from the running product with `scripts/capture-tokens.js`, or use a host entry's captured file. Show every theme the product supports, or at least the person's own and one of the other polarity (light and dark).
- Respect the theme's radius and font. When the theme is monospace or square, so is the design; do not add a font family inside a host.
- Status colours carry meaning: primary for the main action and the selection's accent, success for done, warning for paused or attention, destructive for failed or blocked. Pair each with a word or a shape. Tints, glows and shadows mixed from these tokens (`color-mix(in oklab, …)`) are yours to use for depth and focus.
- Keep "needs you" and "selected" visibly different: needs-you uses an attention surface and a mark; selected uses the selection surface.
- Measure text tokens on every surface they sit on. A token that passes on the background can fail on a card or a tinted row.

## Explore, then converge

Great design comes from many options, cheaply, before one is polished. For a new product or a redesign:

1. Diverge on structure. Sketch five or more quick alternatives for the hero screens (the landing view and the main work view): rough boxes or a few lines of HTML, minutes each. Make them different in kind, not in colour: list-first, visual-first, canvas, timeline, a conversational or a radical option. Include at least one deliberately bold idea. Gather references for mood and behaviour, borrowing ideas, never another product's identity.
2. Critique them against the jobs and the feel words: which one makes the top job effortless, which one people would remember, what each costs. Keep two or three.
3. Push the finalists to directions. Each has a name, three words for the feel, its signature moment, and its choices for depth, type, motif, data visuals and motion. Build them at fidelity on the hero screens with real fixtures and the signature moment running. Prototype the riskiest interaction for real rather than describing it.
4. Show them: a screenshot of each at the main width in the person's theme (check the other polarity before converging), a frame of each signature moment, and a short comparison (feel, risk, cost to build) with a recommendation.
5. Choose. When the user is in the loop, they pick, and may mix. In an autonomous run, pick the strongest, keep the others in the work folder, and say why in `why.md`.

Scale this to the work: a small change follows the existing direction and skips straight to building. When people can be reached and the task allows it, test the riskiest behaviour with one or two of them; a fresh agent's impression is a hint, not a test.

## Use the host's kit, and go beyond it

Before building, list what the host gives you: its own components (status glyphs, icons, pickers, code and diff viewers, chat, info rows), its registry or design system (menus, tooltips, hover cards, popovers, command palette, tabs, segmented toggles, tables, charts, progress, skeletons, empty states), and what the product may bundle (React libraries). The host's catalog entry lists them. Start from these defaults when they fit the job:

- Every state on screen has a glyph or icon from the host's set, paired with a word.
- Detail on demand is an overlay from the kit: a tooltip for the why of a control, a hover card for a thing's facts (what a ticket waits on and unblocks), a popover for a small form, a menu for rare actions.
- Lists use the kit's rows, filter and sort menus, and selection; facts use its label and value rows; long text uses its clamp; a conversation an agent had is the host's own chat view, not a copy of its posts.
- Numbers that change over time get the kit's chart or a sparkline; progress gets its progress bar or phase strip.
- Reuse the host's standard controls (menus, dialogs, tooltips, inputs) for their behaviour: they already own focus, keyboard and the phone layout.
- Custom layouts, views, visuals and motion may replace the kit's equivalents whenever they serve the job better and meet the rails (accessibility, theme) and a performance budget. Libraries the host lets a product bundle (motion, graph and chart libraries, custom SVG, canvas or WebGL) are fair game; record each and its size in `why.md`.
- Design the best experience first. What the host cannot do today is a host ask: draw it in the mock, mark it with `data-host-ask="<what the host would need>"`, and give the fallback you ship now. Do not cut an idea only because the host lacks it.
- In a mock, draw each component as the real one looks (its size, density, icon, overlay) and name it in `data-part` with the kit's name or your own component's, so the build maps one to one.

## Interface copy

Interface copy is not documentation: labels, values and short phrases, with the state word and two or three facts on a row. Keep inline what people need to act safely or to learn something unfamiliar (consequences, recovery, a first-time interaction); put other explanations one step away. The audit's text load checks it (`principles.md`, "Show more than you tell"): mark people's and agents' text with `data-content`, and errors and empty states with `role="alert"`, `role="status"`, `data-empty` or `data-error`.

## Signature

A product's own look, inside a host's theme, comes from what you do with the theme, not from new colours. Starting points, all defaults:

1. A motif that carries meaning, drawn with craft and used where it counts. Draw it from what the product does, not its name alone; it is strongest when it also encodes data (for example, a strip whose segments are the work's phases, with state shown by fill).
2. A rhythm: one spacing scale (4 px steps are a common start), consistent row and header heights, aligned columns. Rhythm reads as craft.
3. Typographic hierarchy inside the host's font: bold weight and size steps (a hero number can be very large), the host's foreground, muted and subtle colours, and a recognisable style for section labels.
4. Words: few, consistent and plain, in a voice that fits the feel words. Sentence case. Buttons name the action and its object. State words fixed across the product.
5. Depth and light: layers for what you act on and what is context, tints, shadows and glows mixed from the theme's tokens, used where they guide focus, so the signature has room to land.
6. Motion: one family of easings and durations (budgets in `principles.md`), changes animated from old place to new, and the signature moment given its own choreography.

Avoid the shared default look of AI-made pages (`references/models.md`): it is nobody's signature. Write the signature down in `why.md` so the production build keeps it.

## Layout

- Find out what the host already draws (a title bar, navigation, side panels) from its catalog entry, and never repeat it: a title the host shows is not repeated as an h1.
- Give the content the person came for most of the first screen; keep chrome compact. A signature visual that answers the top job is content, not chrome.
- Let long text from agents or people be clamped with a way to read all of it, so one item never sets the height of its neighbours.
- Patterns for common jobs are in `catalog/patterns.md`, each scoped to the jobs it serves: for an operational tool, the operational screen, status line, group by whose move, master-detail, decision queue, fact line and event history; for any product, confirm in place, detail on demand, folds with counts and problem states. Pick by job; a pattern that does not serve your person is not a requirement.

## States matrix

For each view, and each component that has them, design and show: default, hover, focus-visible, active, disabled, loading, empty, error, stale, and the many case (the real maximum count). A mock includes a way to switch between them.

## Fixtures

Use the product's own type and field names and real-looking values: real titles from the product's data if available, the longest real names, counts at their real maximum, the longest real block of text, timestamps in the product's format. Write the real maximums into the brief. No "Lorem", "Item 1", "John Doe" or "Task A".

## The mock

- One self-contained HTML file, `mock/index.html`, no network requests, inline CSS and JS. Start from `assets/mock-shell.html`, or from the host entry's shell when it has one: it draws the frame, the theme switch, a width switch (1400, 1000, 720, 390) and a state switch.
- Every screen of the brief is reachable through the mock's own navigation, with the states matrix behind the state switch.
- Name the production component each piece becomes in a `data-part` attribute, so the build can map mock to code.
- Keep the mock honest: anything the host cannot render today carries `data-host-ask` and appears in `why.md` with its fallback.

## Look at it

Open the mock, or the real product, in a headless browser: Playwright, Puppeteer, or the host's own browser automation (its catalog entry says how).

- Screenshot each main screen at the widths people use (for a desktop tool 1400×900 and 720, plus 390 if it reaches a phone; 320 for reflow), in the themes you support.
- Run `scripts/audit-page.js` in the page on each of them. To audit only the product inside a frame or host, set `window.__uxAuditOptions = { root: "<selector>" }` first. The root must cover everything the product draws: its own sidebar and the overlays it portals, not only its page (in the mock shell, `#frame`, not `[data-page]`). Audit again with each overlay open (palette, dialogs, hover cards, menus, toasts), and at phone width with `minTarget: 44`.
- Keep the screenshots and audit JSON in the work folder; the report links them.
- Look at every screenshot yourself before claiming anything about it.
- Never redefine a host token in terms of itself (`--x: color-mix(… var(--x) …)`): that is a cycle, the token becomes invalid in that subtree, HTML colour falls back to the inherited value and SVG fill to black. Mix into a new property name.
- Fix every layout defect the audit lists (text spilling from pills and cards, text over text, sticky bars over content, diagram labels wider than their node, connectors that miss their node or meet it at a corner, nodes cut by the frame), in each state actions open as well as the default.
- Look at a zoomed crop (device scale 2) of each diagram, card row and sticky bar before reporting. Zero audit failures on whole-page screenshots hid every one of these defects in one mock (`catalog/hosts/bb/README.md`, Lessons).
- The audit measures what a script can. Also tab through each main task, check custom widgets' names and roles, and resolve every `contrastUnknown` (text over images or gradients) by sampling the pixels.

## From mock to production

- Map each `data-part` to a component file. Reuse the product's primitives; add a shared primitive only when two places need it.
- Keep every test hook the product's tests rely on (roles with names, `data-*` attributes) or update the tests in the same change.
- Walk the action inventory: every retained item is reachable in the new UI. Note any that moved; any that changed or went is documented and authorized in the brief.
- Run the product's tests and type checks, then the audit on the real page in each supported theme, including its layout-defect counts with real data: the longest titles, counts and labels.

## `why.md`

One page, read by a reviewer before any screen:

- The jobs and the feel words (copied from the brief), and the direction chosen, with the alternatives considered and why this one won.
- What changed and why, a short paragraph per change, each tied to a job or a measured problem.
- Departures from defaults: each one, with what it does for the person.
- What was dropped, and where each dropped thing went (every retained action still has a home; anything removed was authorized).
- Kept exactly: the rules and behaviours that did not change.
- Host asks: what the host cannot do today, why it matters, and the fallback that ships.
- Libraries added, with their size.
- Not sure yet: open questions, each with the alternative you considered.
