---
name: house-style
description: The user's house visual style for every web page an agent builds for them, including static sites, learning guides, HTML reports, dashboards and slide-like explainers. It provides the colour palette (light and dark), typography, semantic colour roles and drop-in CSS. Load it BEFORE choosing any colour, font or theme for a new page, and whenever the user asks for "our colours", "the palette" or "the house style".
---

# House style

Every new web page you build for this user uses one palette and one type system, so all sites look like a family. The palette is a warm off-white paper with muted ink and accents in light mode, and a warm charcoal in dark mode. The user rejected gruvbox as too yellow, so there is no yellow or cream anywhere.

## Files in this skill

- `palette.css`: the drop-in. It holds the colour tokens for light and dark, semantic role names, the Google Fonts import and base body, link, focus and code styles. Copy it into the site, for example as `assets/palette.css`, and link it before your own CSS.
- `tokens.json`: the same values for JavaScript, SVG, charts and Mermaid `themeVariables`.
- `components.css`: reference components built on the tokens: kicker, lede, numbered h2 with a rule, sticky mono top bar, panels, cards, callouts, tags, buttons, segmented buttons, tables and footer. Copy the parts you need.

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
   - Body text is Source Serif 4 at 19px with line height 1.65 (17.5px on narrow screens), in a reading column of about 700px.
   - Kickers, navigation, labels, tags, buttons and code use IBM Plex Mono at 11 to 13px. Kickers and labels are uppercase with letter spacing.
   - h1 is 40px. h2 is 27px with a top rule and a mono section number (`01`, `02`) in `--blue`.
7. Charts, SVG and diagrams read colours from CSS variables at render time (`getComputedStyle(document.documentElement).getPropertyValue("--blue")`). Re-render them when the theme changes. For Mermaid, use `theme: "base"` with `themeVariables` mapped from the tokens.

## When not to apply it

- Someone else's site, or a site with an established look: do not restyle it unless asked.
- The user names a different palette for a specific project: follow the user, and do not edit this skill unless they say the house style itself changed.
- A skill that ships its own fixed theme keeps it unless the user asks for the house palette there.

## Changing the house style

Only the user changes it. When they do, update `palette.css`, `tokens.json` and this file together, and re-check contrast for every text and background pair.
