---
name: house-style
description: The user's house style for every web page an agent builds for them, including static sites, hosted sites, learning guides, proposals, HTML reports, dashboards and slide-like explainers. It ships a kit to copy whole (colour tokens for light and dark, a fluid type scale, a space ladder, base typesetting, components, a small script and self-hosted Source Serif 4 and IBM Plex Mono), three forms to pick from (a memo to read, a status page, and a project site of hub and boards with cards, timelines and tabs for long-running work with a lot going on) with a model page for each, dropdowns the page draws itself, the parts every page must have, the content rules that tell a short story in sentences with a figure wherever it shows what a sentence cannot, and a gate script that fails a page missing any of it. Load it BEFORE choosing any colour, font, theme or layout for a new page, before writing a page's copy, and whenever the user asks for "our colours", "the palette" or "the house style".
---

# House Style

Every new web page you build for this user is one of a family: one palette, one type system, one way of moving, and one way of telling a story. The vibe is a warm off-white paper with muted ink and accents in light mode and a warm charcoal in dark mode, set in Source Serif 4 with IBM Plex Mono for labels, data and code. There is no yellow and no cream anywhere; the user rejected gruvbox as too yellow.

The bar is a page that reads like a well-kept engineering memo and is still the fastest way to understand the thing. Generic competence is the failure: a page of rounded cards, pills and a stock navbar "looks like bootstrap" however tidy it is. Type is the material, space is the hierarchy, and hairlines replace boxes.

The memo is one of three forms, not the default for everything. A project site, with many teams, many items, live data and several pages, takes the project form: the same paper, type, space, seal and header, with cards, timelines, tabs and folding groups, because a reader scans it rather than reads it. Pick the form first (Pick a Form, below).

## What Makes a Page Ours

Five signatures, on every page. They are what a reader recognises before reading a word, and `scripts/gate.js` checks for them.

1. The route: the header is the page's parts as stops on one line, with a dot for each part you have passed, a ring with a halo on the part you are reading, and the line between them filling as you read. On a wide desk it runs down the left margin under the seal and leaves the reading space and its height clear; on a narrower desk it is one quiet row; on a tablet or a phone it folds into a strip that names where you are, opens every part, and draws a reading line. The Keys button and the theme switch, both small rings, sit at the top right in every form.
2. The seal: the site's initial in the serif's italic, the face of every heading's turn, inside a hairline ring like the ring that opens each part, drawn by `scripts/mark.py`, which writes the favicon from the same outlines.
3. The memo head: a kicker set as a path ("Shuttle / a bb plugin"), the two-part title, the lede, and the brief, a ruled list of the two to five facts a reader needs first (status, what is asked, owner, next, updated).
4. Ruled parts: every part opens on a hairline across the wide line with a ring on its left end, and on a desk its numeral hangs in the margin beside the label; the ring of the part being read fills with the tint.
5. Numbered frames: every drawing sits in a hairline frame on a barely-there dot grid, and its caption closes the frame as "Fig. 1".

On a project site the signatures hold with two changes: the hub may open on its headline cards in place of the brief, and its parts open on the status page's plain rule.

States are small square chips (`.state`), a word in the mono on its hue's soft tint. Headings have two parts, a plain lead and an italic turn in the tint: "Every PR that needs you, *in one place.*"

The method behind the kit (its measuring, its gate, its rules for words and figures) is adapted from the web-design skill Joel Gerber built for his agents (public, MIT, in `github.com/Jitsusama/core.nix`, `modules/theme/web/skill`). Its look is not ours to borrow: no centred masthead with an emblem above the title, no fleurons between parts, no drop caps, no centred captions and no key line under the title (`references/figures.md`, What Is Not Ours). The two-part heading is the one thing both houses share, and the user chose to keep it.

## What Matters, in Order

Five things are gates, not polish. A page that fails one is reported as unfinished, never as done, and none is traded for another.

1. Accessibility, with WCAG 2.2 AA as the floor, measured rather than judged by eye.
2. The words: a reader who was not there understands it on one read (`references/writing.md`).
3. The parts: every page has the parts listed below.
4. The ways to move: the keyboard reaches everything, the header's Keys button and the Keys list work, and nothing moves that the reader did not move.
5. The style: the kit's tokens and components, never a value retyped.

Then the look, judged against the model pages in `starter/`. The gates make a page fit to show; only the look makes it ours.

## The Kit

Copy these into the site as `kit/` and keep them together:

- `palette.css`: the colour tokens for light and dark (unchanged), semantic roles, the site's tint, the faces with metric-matched stand-ins, fluid type steps, the space ladder, the lines (`--measure`, `--wide`, `--full`), radius and motion.
- `base.css`: the type set as a typesetter would set it, one focus ring, links, code, keys, tables, folds that grow open, fields, reduced motion and forced colours.
- `components.css`: the page, its ground and its lines, the header's three forms (the margin index, the route bar and the strip) and the seal, the memo head and its brief, ruled parts with their rings and numerals, prose and run-in heads, numbered figures on graph paper drawn wide and narrow, plates, numbers, the fact line, ledger tables, points, state chips, screenshots (`.shot`), code to copy (`figure.code`), folds, side sheets, pull quotes, callouts, source lines, the stepper, stacked bars, boards, checklists, controls, dropdowns (`.pick`), hover tips, the Keys list and the foot; and for the project form, cards (`.cards`, `.card`), the headline, the tally, the phase strip, groups that fold (`details.group`) with their rows, the timeline, tabs, the filter row, the live line and sourced numbers (`.fact`). Loading regions use `.skeleton-frame`, `.skeleton-line` and `.skeleton-status`.
- `site.js`: the three-way theme switch, the j, k, g, G and ? keys and their off switch, the current part's ring, its stop on the route and the strip's menu and reading line, every `<select>` drawn as the page's own dropdown and `house.pick()` for one a script fills, tabs that open by arrow key and by `#hash`, checklists that remember, Copy buttons (`data-copy`), blocks that arrive once, and `house.onTheme(draw)`, `house.color(name)`, `house.series()` and `house.mermaid()` for charts.
- `scripts/mark.py`: draws the seal inline and as the favicon.
- `fonts/`: Source Serif 4 (upright and italic, variable weight and optical size) and IBM Plex Mono 400, 500, 600 and italic, Latin subset, under the SIL Open Font License (`fonts/LICENSE.md`). No request leaves the site.
- `tokens.json`: the same values for scripts, SVG generators, charts and Mermaid.

Start every page from a model in `starter/`, which together form a small two-page site: `index.html` is a page to read and `overview.html` a status page, each with its Markdown twin (`index.md`, `overview.md`), sharing one `favicon.svg`, one header and one `llms.txt`. `starter/project/` is a second small site in the project form: `index.html` is the hub and `board.html` a board, with their twins, favicon and `llms.txt`. Copy the folder for your form whole beside `kit/`. Their content is invented; replace every word, number and drawing, and keep the structure. On a site of one page the header leaves out `nav.pages`; the route always lists the page's own parts. The head of every page loads, in this order:

```html
<meta name="color-scheme" content="light dark">
<script>try{const t=localStorage.getItem("theme");if(t==="light"||t==="dark")document.documentElement.dataset.theme=t}catch{}document.documentElement.classList.add("js")</script>
<link rel="preload" href="kit/fonts/source-serif-4.woff2" as="font" type="font/woff2" crossorigin>
<link rel="preload" href="kit/fonts/source-serif-4-italic.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="kit/palette.css">
<link rel="stylesheet" href="kit/base.css">
<link rel="stylesheet" href="kit/components.css">
<link rel="stylesheet" href="site.css">
```

and ends with `<script src="kit/site.js" defer></script>`. A site's own `site.css` names tokens, never a colour, a size or a face. When it needs a value the kit lacks, derive it from roles with `color-mix()` and say why in a comment; if every site would need it, it belongs in the kit.

## Pick a Form

Decide first which form you are building. The memo is not the default: pick by what the reader does with the page. All three share the palette, the type, the space ladder, the seal, the header, the switch, the focus ring, the Keys list and the foot, so a site can mix them and still be one family.

| | A page to read: `.page` | A status page: `.page.overview` | A project site: `.page.overview.project` |
| --- | --- | --- | --- |
| What it is | a proposal, design, decision, review, incident write-up, explainer or learning guide | the state of one piece of work, a tracker, a catalog or a dashboard on one page | a long-running project with a lot going on: many teams and items, live data, several pages that others already know |
| The reader | reads one argument through | glances at the state of many things | comes back often, scans for what changed and what is theirs |
| Memo head | kicker, display title (42 to 64px) with its turn, lede and brief, on the measure | the same with a smaller title, and on a desk the brief beside it | the status page's head; the hub may open on its headline cards instead of the brief |
| Parts | a rule across the wide line with a ring, the numeral in the margin, the label and a two-part heading | a rule, the numbered label and a plain heading, on a `--full` desk | the same as a status page |
| Its pieces | sentences, figures, points, folds | figures, ledger tables, states, a board | cards, the headline, a tally, a phase strip, groups that fold, timelines, tabs, a filter row with dropdowns, a live line |
| Model | `starter/index.html` | `starter/overview.html` | `starter/project/index.html` and `board.html` |

When unsure between the first two, it is a page to read. A site with several pages about one project, live states or more than a handful of teams is a project site, and its pages pick from a small set, each in the project form unless it is a guide:

| Page | Its job | Its pieces |
| --- | --- | --- |
| The hub | what is built, what has moved and what is left, in one screen | the headline (three soft cards), a tally for the unit that measures progress, the phase strip, where the work is (a stacked bar), what happens next (a timeline) |
| A board | every item by team or owner, and what each waits on | a tally, a filter row, one group card per team or app that folds once all of it is done, rows with states, the live line |
| A tracker | the milestones of each phase | one card per phase with its milestone rows, states and owners, and a timeline where dates matter |
| A catalog | every thing in scope, searchable | a done-versus-remaining summary (a tally or a stacked bar), the filter row, a list that pages or groups when it is long, rows that open for detail |
| A design | how the new thing works and how one moves to it | drawings in numbered frames, tabs for parallel tracks, steppers and timelines for rollouts |
| A guide | how to do one thing | a page to read |

Every page has the same header, and the kit picks its form by the room there is. From 1340px a page to read has no bar at all: the seal and the site's name sit top left, the site's pages (when it has several) and then the route run down the left margin beside the wide line, and the Keys button and the switch sit top right, so nothing takes height from the page or crowds the measure. Between 1100 and 1340px, and on every desk for a status page, which reads across and wants its height for the table, the route is one sticky row that shows every part's name; when its stops don't fit the row, `site.js` marks the header `.tight` and it shows the strip instead. Below 1100px it is the strip: the seal, "/ 03 Inbox" as a button that opens a list of every page and part, the controls, and a reading line with a tick where each part starts. The sticky forms are translucent paper with a blur behind. `site.js` keeps `--header-room` at their height, which the kit gives the content as its scroll margin, so no jump hides a heading and moving focus through the header never scrolls the page.

A project site's header never measures itself, so it has one shape from the first paint and never flickers between forms. From 861px it is a row of the seal, the site's pages and the controls over the reading line, with no route: a project page's parts change with its data and its tabs, and a row of stops that may not fit would jump. From 1680px it is the margin index, the pages and the route down the left margin, with the page centred between equal margins. On a phone it is the strip, whose list holds every page and part.

## Every Page Has Its Parts

Words are what an agent writes first and pictures are what it leaves out, so the parts are listed here and `scripts/gate.js` finds each one missing.

- The header, `<header class="topbar">` before `<main>`, written once and styled into all three forms: in `.inner`, the `.home` link (the seal and the site's name), then `.index` holding `nav.pages` for a site of several pages and `nav.route[aria-label="Parts"]` with an `<ol>` linking every part, then `.actions` with the Keys button and the theme switch. `site.js` builds the strip's button, menu and reading line from the route, so the page writes none of them. `starter/index.html` is the markup to copy.
- The seal, drawn once and shown twice: `python3 scripts/mark.py S --favicon favicon.svg` prints the inline `svg.mark.seal` for the home link and writes the favicon from the same outlines (`references/figures.md`).
- A head that names the page wherever it is shared: a `<title>` that is the pithy title, the lede as `description`, `og:title`, `og:description`, `og:type` and `theme-color`.
- A skip link, the first thing focus reaches, one `<h1>`, and the brief (`dl.brief`) under the lede; a project hub may open on its headline (`.headline`, two or three cards) instead.
- The Keys button in the header, `<button class="iconbtn" data-open-keys aria-label="Keys"><kbd>?</kbd></button>`, which opens the Keys `<dialog>` for a pointer or a finger as ? does from the keyboard; the Keys list holds a "Character shortcuts" toggle that turns j, k, g, G and ? off for good (WCAG 2.1.4), leaving the button. Beside it the three-way theme switch (Light, Match System, Dark). Both need script, so both show only once it runs.
- A figure for every part that explains: a drawing (inline SVG with `role="img"`), a table or a chart. A part with nothing to picture says why on its section, `data-figure="each open question with what settles it; a drawing would only repeat the words"`, and a page to read draws at least one picture.
- The thresholds are the kit's own and need nothing from the page: each part's rule with its ring and margin numeral, and the numbered frame round every drawing. A pull quote may carry one voice. Decoration lives at thresholds and in the mark, never on the facts.
- The twin for agents: each page's own Markdown (`index.md` for `index.html`, `overview.md` for `overview.html`) linked as `<link rel="alternate" type="text/markdown">`, holding that page's facts, every number, row and action, as plain Markdown; and `llms.txt` at the site's root listing every page and its twin.
- The foot, below `main`: the page's own links on the left and the byline `by Kalindu De Costa` on the right, quiet in `--ink-soft` italics: `<footer class="foot"><div class="inner"><span>…links…</span><span class="by">by Kalindu De Costa</span></div></footer>`. Keep the byline to those four words, with no link, logo or date.

## Rules

1. ALWAYS use the tokens. Never type a raw hex colour in a component or a `style` attribute; reference `var(--name)`. If you need a colour the palette lacks, ask the user instead of inventing one.
2. There is no yellow and no cream. The page is `--paper` (#f6f3ec light, #24221f dark), and the kit gives it a ground rather than a flat fill: a faint wash of the voice under the memo head that fades out within the first screen, and a fixed grain that is felt rather than seen. The grain only lightens light paper and only darkens dark paper, so it never lowers contrast. The wash does, so its strength is two tokens, `--wash-hue` (6%) and `--wash-tint` (3%), and `scripts/gate.js` measures every text colour in its reach against the darkest paper it can make. Both sit behind everything, carry nothing, and print as plain paper. Add no other texture, gradient or image behind text. Use orange for warnings; never reintroduce gruvbox or amber backgrounds.
3. Support light and dark. Follow `prefers-color-scheme`; the switch forces a theme with `data-theme` on `<html>`, applied before first paint by the head's inline script, and Match System removes the stored choice.
4. Pair colours by role, not by look:

| Role | Token | Notes |
| --- | --- | --- |
| Page, plates, code and table heads | `--paper`, `--card`, `--deep` | `--card` sits on `--paper` |
| Borders and rules | `--rule`, `--rule-soft` | 1px hairlines; decoration only |
| Strokes that carry meaning in a drawing | `--stroke` | connectors, arrows and node edges, 3:1 on every surface (WCAG 1.4.11) |
| Text | `--ink`, `--ink-soft` | secondary text uses `--ink-soft` |
| The site's tint: kicker, labels, part and figure numbers, links, primary button, the page's current link | `--tint` | `--orange`, the house's own, unless the site picks another hue (below) |
| The site's voice: the seal, a heading's italic turn, the current part's ring and its stop, the reading line, the ground's wash | `--voice` | the tint unless the site gives it a second hue (below) |
| Focus ring | `--focus` | always `--blue`, the one place the keyboard is drawn |
| Good, correct, done | `--aqua` with `--aqua-soft` | `--aqua-fill` for strokes and segments |
| Warning, surprise, paused | `--orange` with `--orange-soft` | |
| Error, wrong, deprecated | `--red` with `--red-soft` | |
| Accent, proposed, planned | `--purple` with `--purple-soft` | |
| Secondary, mixed | `--green` with `--green-soft` | |
| Chart series order | blue, aqua, orange, purple, red, green | `house.series()`, or `tokens.json` roles.series |

   The house leads in orange, the palette's own (#8c4b19 light, #e78a4e dark), and keeps teal (`--blue`) as its cool counterpart: the focus ring, information, and the first chart series. Orange is also the warning hue, so every warning carries its word and never rests on orange alone: a state chip (`.state`) in text, a label with a dashed edge in a drawing, a worded legend in a chart. The tint marks the site and where the reader is, never a state. A site may give itself its own feel with one line, `:root { --tint: var(--purple); }`, or keep a teal structure with an orange voice: `:root { --tint: var(--blue); --voice: var(--orange); }`. Nothing else changes a site's colours.
5. Coloured text sits on `--paper`, `--card`, `--deep` or its own `-soft` tint only. Every such pair meets WCAG AA (4.5:1) except dark-mode red on `--red-soft` (4.44:1); keep that one to short tags, or put red text on `--card`. Text on a coloured segment uses `--on-accent` and must be measured: `--on-accent` on `--aqua-fill` in light mode is 4.39:1, so label such segments elsewhere.
6. Colour goes on marks, glyphs, strokes and bars, and on the tint's few words (the kicker, labels, a heading's italic turn, part and figure numbers, links); body text and the lead of every heading stay `--ink`. Nothing is told by colour alone: every state chip carries its word (`.state`), and every chart colour means the same thing everywhere on the page.
7. Typography:
   - Source Serif 4 for every word to read and every heading; IBM Plex Mono for kickers, labels, navigation, states, identifiers (a file, a host, a command), figures in tables, keys and code. No sans.
   - Body text runs from 17.5px on a phone to 19px on a desk (`--step-body`), line height 1.6. No serif text on a page is under 15px (`--step-small`); mono labels sit at 12 to 13px (`--step-label`), uppercase with tracking.
   - Headings rank by weight and the face's optical size before size, and all sit flush left in the centred column. The page's title is `--step-display` (42 to 64px, weight 650) on a page to read and `--step-title` on an overview; a part's heading is `--step-title` (28 to 36px, weight 620); a sub-heading `--step-large`. The italic turn is weight 560 so it holds its own beside the upright. `font-optical-sizing: auto` gives display sizes Source Serif's display cut.
   - A heading is a whole sentence with its full stop, or Title Case, never a sentence without its stop. The best headings have two parts: a plain lead and an italic turn in the tint, `<h2>Half of every build <em>is a download.</em></h2>`.
   - The lede is upright at `--step-large` in `--ink`. Figures that are data sit in the mono or in Source Serif's lining tabular numerals (`.num`); never let a column of numbers wobble.
   - `text-wrap: balance` on headings and `pretty` on paragraphs, real apostrophes and quotes, hyphens only on narrow screens; `base.css` does it.
8. Space and lines:
   - Every gap is a rung of the ladder, set as `gap` or margin on the parent of what it separates, each rung wider than the one inside it: `--tie` 4px inside a mark or a number and its unit, `--pair` 8px between a mark and its words, `--apart` 12px between parts of a row, `--rows` 16px between rows and paragraphs, `--group` 24px between groups and inside a frame, `--block` 40px between prose and the figure or table beside it, `--part` 96px between parts, and `--gutter` (18 to 48px) at the page's edge. A heading has more room above it than below, so it belongs to what follows.
   - Every page is one centred column with every block set flush left inside it, so the page never leans. Prose, headings, ledes, captions and lists hold `--measure`, about 70 characters of body text (608px at 19px); measured in Source Serif 4 at 19px, a 700px column runs to 82 characters a line and 880px to 103, both past the readable limit of about 75. A figure, table, board or set of plates that needs more room takes `.wide` (`--wide`, 880px), which breaks out equally past both edges, never to one side; its caption stays on the measure. The header's row and strip and the foot span `--full` (1160px); the margin index sits outside the wide line and never overlaps it. An overview sets its lines flush left on a `--full` desk. Inside an existing site, use the widths its other pages already use.
   - Things side by side end level, by layout (grid rows and subgrid), never by padding or a fixed height, and none is narrower than 256px. Layouts adapt by their own width with container queries: a table stacks into labelled rows, plates fall into one column and give up their frame, and a drawing swaps to its narrow twin.
   - Alignment is exact: equal inset on both sides of every frame, marks centred on the capitals of their words, a number on the line of the thing it measures. Nothing wraps inside a date, an id, a number and its unit, or a kicker's part.
9. Surfaces: hairlines, space and weight group things; boxes do not. No card grids, pills, rounded badges, banners or boxes around prose, and no box inside a box, except the project form's cards (rule 16). A frame is for a drawing (`.fig`, `.plate`), code, a dialog or a control. Corners use `--radius` (4px); a state chip's are 2px. Findings, risks, options and open questions are `.points`: hairline-topped items with a state chip, a short title and one or two sentences.
10. Tables hold one-line cells. A row whose cells are sentences becomes a point with labelled facts. Figures in tables are mono (`td.fig`), so their digits line up; a table's caption is a label above it. A wide table scrolls inside its own `.table` region, never the page.
11. Charts, SVG and diagrams read colours from CSS variables when they draw, and draw again when the theme changes: `house.onTheme(draw)` does both. For Mermaid, `mermaid.initialize(house.mermaid())`. Drawings follow `references/figures.md`: the page's faces and ink classes, labels placed and never only on hover, never under 12px on screen, drawn twice (wide and narrow) rather than shrunk.
12. Stacked bars, progress strips and segmented timelines MUST have small visible separators between adjacent segments. Use the existing site's separator treatment; the house default is a 2px inset separator matching the surrounding surface, not another chart colour. For percentage widths that sum to 100%, use an inset separator rather than adding flex gaps or margins that shrink the segments. The reference `.stackbar` uses `--segment-surface`, defaulting to `--paper`; set it to `var(--card)` when the bar sits on a card. When reusing an existing component, inspect its full selectors, including parent scopes: matching a class name alone does not guarantee the same styling. Extend or reuse the existing separator rule for the new bar rather than creating a slightly different version. Check the boundaries in light and dark themes at desktop and narrow widths, including the smallest non-zero segment so a separator does not hide it.
13. Motion: nothing moves under the reader unless they moved it. A block may arrive once as it scrolls into view (`.arrives`); state changes are transitions on `--ease` with `--leave`, `--arrive` and `--settle`; the theme sweeps in with a View Transition. Animate only `opacity`, `transform`, `translate`, `clip-path` and `filter`. Numbers change in place, never by counting up. With less motion asked for, or without script, the page is still and whole.
14. Keys and touch: everything works from the keyboard with one focus ring. On every page j and k step part to part, g goes to the top and G to the last part, ? (or the header's ? button) opens the Keys list and Escape closes it with focus back where it was. Character shortcuts never fire in a field or with a modifier held, and the Keys list can turn them all off. An interface adds its own keys to the same list. Every standalone control (a route stop, a menu link, a fold's summary, a button, a header or foot link) is at least 44px tall on a touch screen; links in running text are exempt.
15. Categories: a page that labels many groups that are not states (teams, tracks, traffic groups, phases, catalog tags) may give each group its own pastel from the category set in `palette.css`: `--cat-1` to `--cat-7` (blue, aqua, orange, purple, red, green and a neutral), each with a `-soft` fill and an `-ink` that reaches 4.5:1 on that fill in both themes (`tokens.json` roles.categories lists the values). Chips use `.cat.c1` to `.cat.c7`, the state chip's shape on the group's pastel; bars, swatches and top edges use the solid `--cat-N`. A group keeps its number everywhere on the site and its name is always on the chip or in the legend; states stay on `.state` and its hues. The set is for overviews, trackers and catalogs, and for keeping an established site's pastels when it adopts the house's type and space, rather than repainting them in the tint. Such a site may lead in its own hue for both tint and voice: `:root { --tint: var(--blue); --voice: var(--blue); }`. `scripts/gate.js` measures every `.cat` chip on its fill.
16. The project form (`<main class="page overview project">`): cards are its unit, because a reader scans a project site for their team, their app and what changed. A card is a hairline frame on `--card` with a 3px top edge in its group's category (`.card.c1` to `.c7`) or its state (`.good`, `.info`, `.warn`, `.bad`), `--radius` corners and no shadow. A soft card (`.card.soft`) is filled with its category's pastel and keeps its words in `--ink` and `--ink-soft`. A card holds a label, a number or a title, a note, a short list and at most a mini bar, never another card. Cards in a row end level and none is narrower than 256px.
   - The hub opens on its headline: three soft cards, what is built, what has moved and what is left, each a big number with its meaning, a note and three or four lines. Under it a tally names the unit that measures progress and its counts by state. The headline changes as the project moves on: keep its items in a small data file the keeper edits (such as `data/headline.json`, with a short README), never typed into the page.
   - Every number drawn from data is a `.fact` with a `data-tip` that names its source and when it was true, and the page shows no number it cannot source. Where a number is waiting on a check, mark it in one place that a single edit clears.
   - A group of items (a team's PRs, an app's hosts) is a `details.group` card with its name, a mini bar and its counts in the summary, and its items as `.rows`. A group whose every item is done starts folded, so what still needs work stays in view.
   - Rollouts and milestones keep their timelines (`.timeline`) and steppers, and a design keeps its drawings; a project site never trades them for prose. Parallel tracks of one part are tabs (`.tabs`), and old links to a tab keep working.
   - A long list gets the filter row: a search field, dropdowns (rule 17) and how many show. Past a few hundred rows it pages or groups, inside the same design.
   - Live status (a sync state, a refresh time) is a `.live` line in the page beside what it describes, never in the header, so the header keeps its shape on every page.
   - Keep the site recognisable when polishing one: its layout, its components and every old link and redirect stay, and its pastels stay (rule 15).
17. Dropdowns are drawn by the page, never the system menu. Write a native `<select>`, so the page works without script, and `site.js` draws it as a `.pick`: a button that names the choice and a list in the page's palette and type, opened in the top layer so no card clips it, with the arrows, Home, End, a letter, Enter, Space, Escape and Tab working as they do in a native control. The `<select>` stays as the value and still fires `change`. A filter (`<select data-filter>`, or any `house.pick()`) wears a tinted edge while it is set; a choice that shows a state may wear its state's chip (give the `<select>` the chip's class). Options name what they show and may carry a live count ("Open · 4"). A row of toggle buttons is for two or three choices at most; more is a dropdown. `scripts/gate.js` fails a page that shows a system dropdown.

18. Skeleton frames are the standard first-load state for a region that waits for data. Put them in the initial HTML so the reader sees the region's shape on the first paint. Match the real layout and approximate its first visible height; use the same responsive grid or rows. Keep them still: no shimmer, pulses, timers, fake values or focusable controls. Use a short, visible status such as “Loading namespaces…” outside the `aria-busy="true"` region, and hide the decorative frames from assistive technology with `aria-hidden="true"`. Set busy to false on success, empty and failure, clear the loading status and show real rows, an empty message or an error with a next step. Keep the last usable view in place during background refresh; report freshness in a live line instead of showing a skeleton again. Render all static content immediately and provide a no-script fallback. See [Loading regions](references/checks.md#loading-regions) for markup and checks.

## Content: Tell the Story, Show the Evidence

The user reads these pages to understand something and decide what to do. A good page reads as a short story told in sentences, with a figure wherever it shows what a sentence cannot. Both failures are real: a wall of text the reader must dig through, and a wall of cards, chips and diagrams that never says what they mean or what to do next. `references/writing.md` has the full rules, the walk for each kind of page and the cold-reader check.

1. Lead with the answer. The first screen holds a pithy title of three to eight words that states the finding, a lede of one or two sentences (under about 40 words) that says why it matters, and the brief: where things stand, what is asked and of whom. The brief never repeats the lede. No introduction about the page itself.
2. Walk in the order a sceptic asks. For a proposal: the problem in the reader's terms, the idea, how it works, what it costs, the evidence, where it stands, what is still open. Each part opens with one to three sentences that make its point and ends on the question the next part answers. Reading only the headings gives the argument; reading the headings and openings gives the whole case and the reader's next step.
3. Give direction, not only description: what is decided or recommended, why, what each reader must do now, what is still open and who acts. A proposal states its case; it never poses its owner's decisions as questions. Causes, trade-offs and caveats belong in sentences.
4. A figure earns its place. Draw one when it shows what a sentence cannot: a trend, many items compared on several attributes, shares of a whole, a flow with branches, loops or several actors, the status of many items. When the content is two or three facts or a straight line of steps, write it.

| Content | Form |
| --- | --- |
| A cause, a trade-off, a recommendation, a next step | Sentences |
| Key numbers on the first screen | Fact line (`.facts`) |
| A few measured numbers, each with its meaning | Numbers ledger (`.numbers`) |
| A trend over time | Line or bar chart |
| Shares of a whole | Stacked bar with a legend |
| Items compared on several attributes | Ledger table (`table.ledger`) with states |
| Status of many items (more than about six) | Board, or a ledger table with states |
| A flow with branches, loops or several actors | One drawing |
| Before and after, or two designs | Two plates side by side (`.plates`) |
| A sequence the reader follows or tracks | Stepper, or a numbered list |
| What the product looks like | A screenshot (`img.shot`) on the wide line, with a caption saying what to notice and ending in an "Open full size" link (`a.full-size`) |
| Commands or a prompt to run | A code block with a Copy button (`figure.code`) |
| Findings, risks, options, open questions | Points (`.points`), each with a state and what settles it |
| A person's words that carry the argument | Pull quote (`.pull`) |
| Depth a sceptic may want | A fold (`details.more`) whose summary is their question |
| Actions the reader will tick off | Checklist that remembers ticks |
| What a project has built, moved and left | The headline: three soft cards (`.headline`) |
| Counts of many items by state | A tally (`.tally`) with its thin bar |
| The phases of a project | The phase strip (`.phases`), a linked card each |
| Many items by team, app or owner | Groups that fold (`details.group`) with rows |
| Dated steps of a rollout or a plan | A timeline (`.timeline`) |
| Parallel tracks of one part | Tabs (`.tabs`), each a timeline, list or drawing |
| A long list to narrow | The filter row (`.filters`): a search field and dropdowns |

5. Budget the blocks. A part gets one main figure and at most one supporting block, and none when words make its point. Never show the same facts twice: no cards or points that repeat what the drawing beside them draws, no fact line whose numbers the sentences repeat, no closing checklist that restates the recommendation. Give every figure a one-sentence caption that says what to notice, and put a sentence between two figures.
6. Words come before blocks. The sentence that says what a block means sits above it. A string of loose sentences after a block means the part's point was never written; fold them into its opening.
7. Short prose, not fragments. Paragraphs run two to four sentences and, on overview and design pages, about 60 words at most. Labels in tables, points, steps and plates run two to six words with at most one short subline. Every number comes with its meaning first and what it is compared with.
8. Keep the essentials in view. Hover tips (`data-tip`), folds and side sheets hold extra detail only: a definition, a source, an exact figure, a long list. The decision, the reason, the risk and the next step are always visible. Every tip target is focusable, and a tip meets WCAG 1.4.13: it stays while its target is hovered or focused, the pointer can move onto it, and Escape hides it (the kit does all three).
9. The present, not the history. The page says where things stand now, with one true "Updated" date in the brief; it is never a log of how the work or the page got there. A living page keeps its structure and changes a number or moves an item rather than adding a paragraph. Evidence sits in a quiet `.source` line under its part, and long-form reports live on their own reading pages behind an Evidence link.
10. Nothing the reader cannot open: no internal task ids, thread ids, file paths on someone's disk, unpushed branches or agent jargon. Say what the evidence is in words ("production metrics, 4 November").

## Check Before Handing Over

Run the gate in `references/checks.md` on the page as it will be published, in this order, and report the page as unfinished with each failure named if any step fails:

1. `scripts/gate.js` in the page at 320, 390, 768 and 1400px in both themes: it answers with every missing part, sizes under the floor, lines past the measure, requests that leave the site, typed colours and private traces. An empty list passes.
2. The `ux-design` skill's `scripts/audit-page.js` at 1400px in both themes and at 390px with `minTarget: 44`, with the narrative (ledes, openings, captions and prose) marked `data-content`: expect 0 contrast failures, 0 horizontal overflow and nothing spilling from its box, and confirm each other count on a screenshot.
3. Screenshots of the first screen at 1400px and 390px in light and dark, and zoomed crops (device scale 2) of every drawing, plate row and table. Look at each one yourself.
4. Hold the page beside its model in `starter/` (or `starter/project/` for the project form) part by part, and beside the site's other pages at a desk width of about 1700px: the seal, the route, the brief, every numbered frame, fold and state the model has, this one has too, or says why not.
5. Read only the headings and part openings, top to bottom: they must give the answer, the reasons and the next step without the figures, and each figure must add something they do not.

## When Not to Apply It

- Someone else's site, or a site with an established look: do not restyle it unless asked.
- The user names a different palette for a specific project: follow the user, and do not edit this skill unless they say the house style itself changed.
- A skill that ships its own fixed theme keeps it unless the user asks for the house palette there.

## Changing the House Style

Only the user changes it. When they change colours or type, update `palette.css`, `tokens.json` and this file together, re-check contrast for every text and background pair, and keep the fonts in `fonts/` in step with `palette.css`. When they change the content rules, update this file, `references/writing.md` and the matching components. When a verdict of theirs on a real page settles a question, write it here in a sentence so no agent asks again.

- Nov 18, 2026, on an internal tracker site: replacing the project layout with a docs layout lost the architecture drawings, the PR cards that fold away when done, and the timelines. Keep those components and the site's layout while adopting the house's type, space, header and switch. Project sites take the project form (rule 16), not the memo. The header never moves or flickers (live status goes in the page), and every dropdown is the page's own (rule 17).
- Nov 18, 2026, on an internal tracker site: an existing site with its own pastel identity keeps its hues. It adopts the house's faces, type steps, space ladder, focus ring and theme switch, leads in its own tint, and labels its groups with the pastel category set (rule 15), not with orange and teal alone.
