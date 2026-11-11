# Principles: defaults and their evidence

Everything here is a default unless it is marked as a rail: a strong starting point with its source and a check you can run. Break a default when the design serves the person better, and write the reason in `why.md`. The accessibility table is a rail (`SKILL.md`). Numbers marked "working threshold" are conventions for a check, not research findings; never present them as research, and treat a miss as a question to answer, not a failure. Studies are summarised with their population where it matters; a result from web pages or plant control rooms is a hypothesis for your product, not a law. Research gathered 2026-11-10.

## Appeal and feel

How a product looks and feels is part of whether people keep using it, not decoration added at the end.

- People judge visual appeal within 50 ms, and the judgement holds after longer viewing (Lindgaard et al. 2006, "Attention web designers: you have 50 milliseconds to make a good first impression", Behaviour and Information Technology 25:2).
- People rate a better-looking interface as easier to use: Kurosu and Kashimura (CHI 1995, 26 ATM layouts, 252 people) and Tractinsky et al. ("What is beautiful is usable", Interacting with Computers, 2000). The effect also hides usability problems in tests (NN/g, nngroup.com/articles/aesthetic-usability-effect), so appeal is required on top of the jobs, never instead of them, and a reviewer never lowers a severity because a screen is beautiful.
- Norman's three levels (Emotional Design, 2004) give the checks: visceral (does the first glance please?), behavioural (does every action feel immediate and under control?) and reflective (would the person show it to a colleague, and is it theirs?).

Defaults:

- An art direction before screens: three words for how it should feel, a signature moment (the interaction people remember), and how depth, type, colour and motion serve those words. Explore widely before choosing (`build.md`).
- Drama, play and atmosphere are welcome when they serve understanding, orientation, identity or delight: a bold hero number, a striking visual, a playful completion, a mood. Name the benefit. What breaks the rails or hides the top job is out, however striking.
- A clear focal point on each screen, made by scale, weight or contrast; a comparison may balance two. A screen where everything has the same weight is bland, even when it is tidy.
- Depth and material separate layers and carry focus: tints and shadows mixed from the theme's own tokens, a texture drawn from the product's motif. Decoration that means nothing, or colours outside the theme, are out.
- Data can be beautiful: visualisations drawn with care (spacing, easing, labels in place) can be the product's face. When the product has a core idea (progress, a graph, a timeline), consider drawing it as the signature visual; a plain table is right when it serves the job better.
- Motion explains change: things move from where they were to where they are. Starting budgets: 60 to 120 ms for hover and press, 150 to 300 ms for layout changes, up to about 500 ms for a choreographed signature moment, at 60 fps. No decorative idle loops; a live-activity pulse is fine when it means something, stops or can be paused (WCAG 2.2.2), and honours reduced motion.
- Feel: every action responds within 100 ms (hover, press, an optimistic update) and finishes or shows progress by 400 ms (Doherty threshold); focus lands where the person goes next; undo beats confirmation; the keyboard reaches everything.
- Check: show the first screen for a few seconds to someone, or a fresh agent, and ask for three words; compare them with the art direction's three words. Blur the screenshot: the intended focus must remain. A fresh agent's words are a hint, not a measure of appeal or retention.

## Attention and memory

- Hold at most about four things in mind. Avoid making the person remember values across a screen change, a tab or a modal; bring the compared things onto one screen. Source: Cowan 2010, "3 to 5 meaningful items" (pmc.ncbi.nlm.nih.gov/articles/PMC2864034). Miller's 7±2 is only an argument for chunking.
- Recognition over recall. Current scope, filters, selection and state stay visible. Source: Nielsen heuristic 6 (nngroup.com/articles/ten-usability-heuristics).
- The main answer fits the first screen. At 1400×900, the thing the person came for is visible without scrolling. NN/g measured 57% of viewing time above the fold and 74% in the first two screens (nngroup.com/articles/scrolling-and-attention); Few's first dashboard pitfall is exceeding one screen (perceptualedge.com, Common Pitfalls).
- Fewer equal choices decide faster (Hick). Usually one primary action per region, or a clear pair at a decision; more than about seven ungrouped peer actions need grouping, a menu or a command palette (working threshold). Hide rare actions behind one step, never delete them; frequent actions take one step or one key (Nielsen heuristic 7).
- Targets near the work (Fitts). Row actions sit on the row; the primary action sits beside what it acts on, not in a page corner.
- Spend pop-out on one or two things. Squint or blur the screenshot: the first three things you see must be the intended ones (NN/g squint test, nngroup.com/articles/visual-hierarchy-ux-definition). If three unrelated things pop (several saturated colours, bold plus colour plus icon), the emphasis is diluted.
- At most three emphasis levels per view (NN/g, same article).
- Information scent. Labels are specific nouns and verbs from the person's words, not "Overview", "Details", "More"; a link to a list shows its count or state (nngroup.com/articles/information-scent).
- Feedback within 400 ms, a pending state after that, progress after about a second (Doherty threshold, lawsofux.com).

## Show more than you tell

A working screen is scanned, not read. On an average web page people read at most 28% of the words, 20% more likely (Nielsen 2008, nngroup.com/articles/how-little-do-users-read); 79% of test users scanned every new page and 16% read word by word (Nielsen 1997, nngroup.com/articles/how-users-read-on-the-web). Concise text scored 58% higher in measured usability, scannable text 47%, and both with objective wording 124% (Morkes and Nielsen 1997, nngroup.com/articles/concise-scannable-and-objective-how-to-write-for-the-web). Krug's rule: get rid of half the words on each page, then half of what is left; instructions and "happy talk" go first (Don't Make Me Think, "Omit needless words").

- State is shown, not described: a glyph or icon with a state word, a bar, a number, a position in a group. A sentence that only restates what a mark or group already shows is noise.
- Interface copy is mostly labels, values and short phrases. Writing rules for documents (complete sentences, articles, linking words) do not apply to it.
- Keep inline the words people need to act safely or to use something unfamiliar: what an irreversible action will do, what a choice changes, how to recover from an error, how a new interaction works the first time. Everything else that explains goes one step away, in a tooltip, a hover card, a popover or the help, reachable by keyboard and touch too.
- Instructions for familiar interactions go ("click a row to…"): the control's look says it can be used, and key hints are shortcut pills.
- A legend is marks with a word or two each, or a tooltip on the mark, rather than a paragraph.
- A secondary line in a row holds two or three short facts and does not truncate; a cut-off sentence means too many words.
- Say each fact once per screen.
- Check: the audit's text load. Mark what people or agents wrote with `data-content`, and errors and empty states with `role="alert"`, `role="status"`, `data-empty` or `data-error`. The audit flags text blocks over 12 words (`maxBlockWords`) and instruction phrases outside them, and counts first-screen words (an operational screen at 1400×900 usually needs fewer than about 150 outside content). Each flag is a question: fix it, or say what the words do for the person. Then blur the content in the screenshot: the state of every row should still be clear.

## Grouping and hierarchy

- Proximity: the gap between groups is at least 1.5 to 2 times the gap inside a group (working threshold). A label equidistant between two fields fails (lawsofux.com/law-of-proximity).
- Similarity: things that look alike behave alike. Everything that looks like a link or button is one, and one kind of value (states, times, keys) has one style.
- Containers earn their place: whitespace first, then a tint, then a border. A card around every item, or containers three deep, usually means the grouping is not working (lawsofux.com/law-of-common-region; NN/g "use them sparingly").
- Greyscale test: convert the screenshot to grey. Hierarchy, status, series and selection must survive (WCAG 1.4.1).
- Scanning: people scan the left edge and headings (layer-cake), and hunt for numbers (spotted). Put the key word or value first on each line and row; headings alone must tell the story (nngroup.com/articles/f-shaped-pattern-reading-web-content).

## Density

- Density follows the person: experts using a tool all day want high density; rare or first-time tasks want more explanation. State the user and frequency before judging density.
- Dense and calm means content keeps its density while chrome loses weight (calm is not bland: the content itself can be rich, layered and visual): borders, nav, headers and icons are quieter than data, but still meet contrast (Linear's 2024 and 2026 redesign write-ups, linear.app/now).
- Hide complexity, do not remove it (Bloomberg Terminal UX write-up).
- Rich controls carry density without words: an icon or glyph per state, a hover card for detail, a menu for rare actions, a sparkline beside a number, a segmented filter with counts. A screen drawn only from text, links and boxes, when richer controls are available, is usually underbuilt.
- Count the space that does no work. Nielsen found 52% of homepage space wasted (nngroup.com/articles/homepage-real-estate-allocation). For an operational screen, the content the person came for should fill at least 60% of the first screen (working threshold). Use the audit's `firstScreen` list to measure it.
- Design minimisation, not data minimisation (Tufte): remove decoration and chrome before removing data. A change that removes a number says why.
- Tables for comparable rows: more than about eight items with three or more shared attributes belong in a table, not cards (nngroup.com/articles/data-tables; threshold is working). Numeric columns right-aligned with `font-variant-numeric: tabular-nums`.
- Every metric has context (a target, a previous value, a rate) and no more precision than a decision needs (Few pitfalls 2 and 3). "2,811,143,984 tokens" fails; "2.8B tokens, 85M per PR" passes.
- Charts: no frames, heavy grids or 3D; a gradient only when it encodes a value; label directly instead of a legend that repeats the labels; inline sparklines beside the number they explain; more than about five series on one chart means small multiples with shared axes (Tufte, edwardtufte.com sparkline pages).

## Layout

- Overview first, zoom and filter, then details on demand (Shneiderman 1996). Details open in place (a panel or a split view) and keep the list's position.
- Progressive disclosure: frequent things up front; usually no more than two levels of disclosure (nngroup.com/articles/progressive-disclosure). Never fold away what the person needs to decide safely.
- Master-detail beats click, read, Back, click next for walking a list. Back and a page reload restore the list's scroll, filter and selection.
- Space wasters to question on sight (working thresholds): stacked full-width panels where a table or a two-column grid fits; chrome taller than about 120 px above an app view, or stacked header panels that push the content below 40% of the viewport (a signature visual that answers the top job is content, not chrome); a fixed narrow max-width on data views at 1400 px and wider; a tile that repeats a number shown right below it; the page title repeated in the host's title bar, an h1 and a tab; decoration that pushes daily work down.
- Whitespace groups or it wastes. For each gap over about 24 px, name what it separates; if nothing, shrink it.
- Liquid layout: from 1280 to 2560 px wide, data regions gain width or columns, not margins (nngroup.com/articles/screen-resolution-and-page-layout). Prose keeps a reading width of about 60 to 75 characters.
- Reflow: at 320 px wide (or a narrow side panel), no two-dimensional scrolling except inside tables, maps and code (WCAG 1.4.10).

## Type

- Prose lines 45 to 75 characters; 80 is the ceiling (WCAG 1.4.8, AAA). Does not apply to tables, code or logs.
- Size floors for dense UIs (working thresholds): body and table text 13 px or more, secondary 12 px, nothing under 11 px. Inside a host, start from its sizes; the audit's `fontSizes` shows the scale. Many distinct sizes on one screen can mean there is no scale; judge the hierarchy, not the count.
- Line height: prose 1.4 to 1.6, dense rows 1.3 to 1.4, and the layout must survive WCAG 1.4.12 text spacing (line height 1.5, paragraph spacing 2, letter 0.12 em, word 0.16 em).
- Monospace for values people copy, compare character by character or align (keys, hashes, commands, logs). When the host theme is monospace everywhere, do not add a second family; build hierarchy from weight, size and colour instead.

## Accessibility: WCAG 2.2 AA (a rail)

The main checks for a working UI. This table is a summary, not the standard: when a design does something the table does not cover, check the success criteria themselves (w3.org/TR/WCAG22).

| SC | Rule | Check |
|---|---|---|
| 1.4.3 | Text contrast 4.5:1, large text (24 px, or 18.66 px bold) 3:1, unrounded | audit `contrast`; every theme, including muted text |
| 1.4.11 | Non-text contrast 3:1 for control edges, focus rings, selected states, chart marks | check borders that are the only sign a control exists |
| 1.4.1 | Colour is never the only carrier of state, selection or series | greyscale test |
| 2.4.7 | Focus always visible | tab through; no `outline: none` without a replacement |
| 2.4.11 | The focused control is not entirely hidden by sticky headers, toasts or panels | tab under sticky regions |
| 2.5.8 | Targets at least 24×24 CSS px, or spaced so a 24 px circle on each touches no other | audit `smallTargets`; inline links in sentences are exempt |
| 2.1.1, 2.1.2 | Everything works by keyboard; no trap | finish each core task with keys only |
| 2.5.7 | Dragging has a non-drag alternative | |
| 4.1.3 | Status messages announced without moving focus | `role=status` or `aria-live` on toasts and async results |
| 4.1.2, 1.3.1 | Every control has a name, a role and its state; structure is in the markup (headings, lists, tables) | audit `unnamedControls`; inspect the accessibility tree of custom widgets and visuals |
| 3.3.2 | Inputs have labels or instructions | every field and custom control |
| 2.2.2 | Moving or auto-updating content over 5 s can be paused | live strips, tickers, auto-refresh |
| 1.4.10 | Reflow at 320 px | |

Reduced motion is WCAG 2.3.3, which is AAA: honour `prefers-reduced-motion`, but do not call its absence an AA failure.

## Heuristics

Nielsen's ten, each with its check:

1. Visibility of system status: every action shows a result; loading, saved, failed and stale are visible.
2. Match the real world: the person's words, no internal codes.
3. User control and freedom: cancel, undo and a clear way out of every multi-step flow.
4. Consistency: one word, icon and position per meaning across the product.
5. Error prevention: confirmation or undo for destructive actions; constraints that make bad input impossible.
6. Recognition rather than recall.
7. Flexibility and efficiency: shortcuts and bulk actions for experts, out of a novice's way.
8. Aesthetic and minimalist design: "every extra unit of information competes with the relevant units".
9. Help users recognise, diagnose and recover from errors: plain words, what is wrong, the fix.
10. Help in context, task-focused.

Shneiderman adds "design dialogs to yield closure": a multi-step operation ends in a clear end state ("Order placed: arrives Thursday"), not a silent return to the list. Gerhardt-Powals adds: automate unwanted workload (no mental arithmetic the UI can do), fuse data into higher-level summaries, include only task-relevant information at a given time, and code important states more than one way (text plus shape plus colour).
