---
name: house-style
description: The user's house visual style for every web page an agent builds for them, including static sites, learning guides, HTML reports, dashboards and slide-like explainers. It provides the colour palette (light and dark), typography, semantic colour roles, drop-in CSS and the content rules that pair a short written story with figures that carry the evidence, so pages are neither walls of text nor walls of diagrams. Load it BEFORE choosing any colour, font, theme or layout for a new page, before writing a page's copy, and whenever the user asks for "our colours", "the palette" or "the house style".
---

# House style

Every new web page you build for this user uses one palette, one type system and one way of presenting content, so all sites look and read like a family. The palette is a warm off-white paper with muted ink and accents in light mode, and a warm charcoal in dark mode. The user rejected gruvbox as too yellow, so there is no yellow or cream anywhere.

## Files in this skill

- `palette.css`: the drop-in. It holds the colour tokens for light and dark, semantic role names, the Google Fonts import and base body, link, focus and code styles. Copy it into the site, for example as `assets/palette.css`, and link it before your own CSS.
- `tokens.json`: the same values for JavaScript, SVG, charts and Mermaid `themeVariables`.
- `components.css`: reference components built on the tokens: kicker, lede, numbered h2 with a rule, sticky mono top bar, panels, cards, callouts, tags, buttons, segmented buttons, tables and footer, plus figures with captions, a capped prose measure for wide pages, and the evidence set (fact line, hover tip, chips, flags, status board, stacked bar, stepper and checklist). Copy the parts you need.

## Rules

1. ALWAYS use the tokens. Never type a raw hex colour in a component; reference `var(--name)`. If you need a colour the palette lacks, ask the user instead of inventing one.
2. There is no yellow and no cream. The page is `--paper` (#f6f3ec light, #24221f dark). Use orange for warnings; never reintroduce gruvbox or amber backgrounds.
3. Support light and dark. Follow `prefers-color-scheme`, and let a toggle force a theme with `data-theme` on `<html>`. Set the theme before first paint with a tiny inline script that reads localStorage, so the page never flashes the wrong theme.
4. Pair colours by role, not by look:

| Role | Token | Notes |
| --- | --- | --- |
| Page, panels, code and table heads | `--paper`, `--card`, `--deep` | `--card` sits on `--paper` |
| Borders and rules | `--rule`, `--rule-soft` | 1px |
| Text | `--ink`, `--ink-soft` | secondary text uses `--ink-soft` |
| Links, focus, primary buttons, kickers | `--blue` | button text is `--on-accent` |
| Good, correct, done | `--aqua` with `--aqua-soft` | `--aqua-fill` for strokes |
| Warning, surprise, paused | `--orange` with `--orange-soft` | |
| Error, wrong, deprecated | `--red` with `--red-soft` | |
| Accent, proposed, planned | `--purple` with `--purple-soft` | |
| Secondary, mixed | `--green` with `--green-soft` | |
| Chart series order | blue, aqua, orange, purple, red, green | from `tokens.json` roles.series |

5. Coloured text sits on `--paper`, `--card`, `--deep` or its own `-soft` tint only. Every such pair meets WCAG AA (4.5:1) except dark-mode red on `--red-soft` (4.44:1). Keep that one to short tags, or put red text on `--card` instead.
6. Typography:
   - Body text is Source Serif 4 at 19px with line height 1.65 (17.5px on narrow screens), in a reading column of about 700px. Overview and dashboard pages use a wider container of about 1160px and may step h1 down to 34px and h2 to 22px.
   - Kickers, navigation, labels, tags, buttons and code use IBM Plex Mono at 11 to 13px. Kickers and labels are uppercase with letter spacing.
   - h1 is 40px. h2 is 27px with a top rule and a mono section number (`01`, `02`) in `--blue`.
7. Charts, SVG and diagrams read colours from CSS variables at render time (`getComputedStyle(document.documentElement).getPropertyValue("--blue")`). Re-render them when the theme changes. For Mermaid, use `theme: "base"` with `themeVariables` mapped from the tokens.

## Content: tell the story, show the evidence

The user reads these pages to understand something and decide what to do. A good page reads as a short story told in sentences, with a figure wherever it shows what a sentence cannot. Both failures are real: a wall of text the reader must dig through, and a wall of cards, chips and diagrams that never says what they mean or what to do next.

1. Know the kind of page, because the balance follows from it. When unsure, treat it as a design page.

| Kind | Examples | Balance |
| --- | --- | --- |
| Status overview or dashboard | the state of a migration, a tracker, a catalog | Mostly figures and labels, with a fact line of the key numbers. Sentences for the headline, the lede and the takeaway each figure needs. |
| Design, decision or incident page | how a change will work, which option to pick, what went wrong | Direction in sentences, evidence in figures. This kind most often drowns in blocks. |
| Reading page | a learning guide, a full report | Prose in the 700px column, with a figure where it explains better than text. |

2. Lead with the answer. The first screen holds a headline that states the finding, a lede of one or two sentences (about 40 words) that says why it matters, and the reader's next action. Add a fact line only when the story turns on a few numbers the reader would otherwise hunt for; counts that teach nothing, and numbers the next sentences repeat, are decoration. No introduction about the page itself.
3. Give direction, not only description. Open each section with one to three sentences that make its point: what is decided or recommended, why, what each reader must do now, what is still open and what happens next, and who acts. When a page has several audiences, say what each one does, even when the answer is "nothing yet". A reader who reads only the headline, the lede and these openings gets the whole argument and knows their next step. Causes, trade-offs, judgements and caveats belong in sentences; they lose their meaning when chopped into chips or boxes.
4. A figure earns its place. Draw one when it shows what a sentence cannot: a trend, many items compared on several attributes, shares of a whole, a flow with branches, loops or several actors, or the status of many items. When the content is two or three facts or a straight line of steps, write it. If the reader would not miss the figure once it became a sentence, keep the sentence.

| Content | Form |
| --- | --- |
| A cause, a trade-off, a recommendation, a next step | Sentences |
| Key numbers | Fact line: a big serif figure with a short mono label |
| A trend over time | Line or bar chart |
| Shares of a whole | Stacked bar with a legend |
| Items compared on several attributes | Table with short cells and tags |
| Status of many items (more than about six) | Board with one column per state, or a table with tags |
| A flow with branches, loops or several actors | One diagram |
| A sequence the reader follows or tracks | Stepper, or a numbered list |
| Before and after | A two-column table, or one diagram with the change marked |
| Findings, risks or gaps | A short list with a tag on each item and what to do about it; chips only for items of one to three words |
| Actions the reader will tick off | Checklist that remembers ticks in localStorage |

5. Budget the blocks. A section or subsection gets one main figure and at most one supporting block, such as a short table, list or checklist, and none when words make its point. Never show the same facts twice. The common cases are cards or chips that repeat what the diagram beside them draws (a flow's outcomes shown again as chips), a fact line whose numbers the sentences repeat, and a closing checklist that restates the recommendation. Give every figure a one-sentence caption that says what to notice, and put a sentence between two figures.
6. Words come before blocks. The sentence that says what a block means sits above it. A string of loose sentences after a block, each adding one more fact, means the section's point was never written; fold them into its opening.
7. Short prose, not fragments. Paragraphs run two to four sentences and, on overview and design pages, about 60 words at most. Cards, chips, table cells, steps and flags carry labels of two to six words and at most one short subline; the sentences around them say what the labels mean. Give all prose on a page one fixed width, so paragraphs, captions and lists end at the same edge: the 700px reading column (`--read`), or `--measure` (820px) in the wide container. Use pixels, not `ch`, which changes with the font size. Inside an existing site, use the width its other pages already use.
8. Keep the essentials in view. Hover and focus tips (`data-tip`) and collapsible sections hold extra detail only: a definition, a source, an exact figure, implementer notes or a long list. The decision, the reason, the risk and the next step are always visible, because skimmers and touch readers never open a tip. Every tip target is focusable.
9. Long-form lives behind an Evidence link. Full reports, sources and method sit on separate reading pages in the 700px column. The overview links to them and never repeats them. Overview and design pages keep under about 250 words in the first screen, navigation included, and on-screen instructions to a short mono hint beside a heading, such as "hover for detail".
10. Reading pages open with a short summary, a fact line or one figure, and add a figure about once every screen and a half of reading, not once a paragraph.
11. Check before handing over. Screenshot the first screen at 1400px and 720px wide in light and dark mode. When the page joins an existing site, also compare it with the site's other pages at a desk width of about 1700px: text widths, rules and spacing should match. Then read only the sentences, top to bottom: they must give the answer, the reasons and the next step without the figures, and each figure must add something they do not. When the `ux-design` skill is installed, run its `scripts/audit-page.js`. Mark the narrative (ledes, section openings, captions and reading prose) with `data-content` so its long-block count covers interface text only, and expect 0 long text blocks outside the narrative, 0 contrast failures, no text under 11px and no horizontal overflow.

## When not to apply it

- Someone else's site, or a site with an established look: do not restyle it unless asked.
- The user names a different palette for a specific project: follow the user, and do not edit this skill unless they say the house style itself changed.
- A skill that ships its own fixed theme keeps it unless the user asks for the house palette there.

## Changing the house style

Only the user changes it. When they change colours or type, update `palette.css`, `tokens.json` and this file together, and re-check contrast for every text and background pair. When they change the content rules, update this file and the matching components in `components.css`.
