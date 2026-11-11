---
name: ux-design
description: Plan, build and review user interfaces for people, from evidence. Job briefs and inventories, divergent design exploration, HTML mocks and production UI, and independent UX reviews with measured checks (contrast, targets, text load, first screen). Use when asked to design, redesign, mock, critique or audit a UI, a dashboard, an app page or a plugin surface, or to fix its accessibility. Not for back-end work.
---

# UX design

Design for the person who uses the screen: what they must do, how it should feel, and proof that it works. Three modes share one set of rails: plan, build and review. The rails keep the work honest, accessible and true to the product. Inside them, be bold: a memorable, beautiful interface that people enjoy is part of the job, not decoration.

## Modes

| Mode | You produce | Read |
|---|---|---|
| Plan | `brief.md`: who, jobs, what stays, how it should feel, measures, open questions | `references/plan.md` |
| Build | explorations, then a mock (`mock/index.html` and screenshots) or production UI, and `why.md` | `references/build.md` |
| Review | `review.md`: verdict, findings by severity, each with evidence | `references/review.md` |

Read what the task needs, not everything: `references/principles.md` for the defaults and their evidence; `references/anti-patterns.md` while building and reviewing; `references/oversight.md` when the UI shows work done by agents, jobs or other people; `references/models.md` when you choose models for design or review. `catalog/patterns.md` has interaction patterns to build from, each scoped to the jobs it serves, and `catalog/hosts/<host>/` has the facts of one host app or platform (slots, tokens, components, how to look at it live). Read the host's entry when the product lives inside one.

Scale the process to the work. A new product or a redesign explores widely, gets an independent review on another model family, and a second review of what changed. A small change follows the existing direction and checks the rails.

## How the rules work

Three kinds of rule, in this order of precedence:

1. Rails never bend. Breaking one is a defect, whatever the design gains.
2. Defaults are good starting points with evidence behind them (`principles.md`). Break one when the design serves the person better, and say why in `why.md`. A documented departure is not a finding by itself; a reviewer judges whether the reason holds.
3. Patterns (`catalog/patterns.md`) are options for particular jobs. Use one when its job is yours.

## Rails

1. Start from the person and the jobs, not from today's screens. Write who uses it, when, and the jobs relevant to this scope (usually five to eight for a full product).
2. Keep the contract. Inventory every action, rule, refusal and permission of the current UI. Each stays reachable, or the brief says why it goes and someone with the authority agreed. Propose new capabilities; never invent or remove them silently.
3. Accessible to WCAG 2.2 AA in every theme the product supports: contrast, keyboard, focus, names and roles, targets, reflow, and state never carried by colour or motion alone. Honour reduced motion with every state still visible.
4. Honest evidence. Measure instead of asserting, look at every screenshot before writing about it, separate what you measured from what you judge and what you guess, and call work without real users "expert review, not user validation". A zero count from an audit is not conformance: resolve or report what it could not measure.
5. The host's theme. Inside a host app, colours, type and radius come from its theme variables; mix them for tints and depth, never add a palette of your own. A standalone page follows the person's house style when they have one.
6. Real data. Design with the product's real shapes and its awkward cases: the longest names, empty, one, many, errors, stale data, a wall of text from an agent.
7. Scope. Do only what the task asks; never commit, push, publish or message anyone unless it says so.

## Aims

What great looks like. Each is a direction to push, checked in review, not a quota.

- Make it a pleasure to use. It should look good and feel immediate, and people should remember it. Give it an art direction (three words for how it should feel, and a signature moment) and the craft to match: focus, depth, type, motion and a visual of the product's core idea. Drama, play and atmosphere are welcome when they serve understanding, orientation, identity or delight; name the benefit.
- Show more than you tell. State is a glyph, a number, a bar or a position, with a word. Keep the words the person needs to act safely and understand something new, and cut the rest.
- Answer the top job first. What the person came for is the first thing they see.
- Build with the host's kit and go beyond it. Use its components for standard controls, which already own focus, keyboard and phone layouts. Build your own views, visuals and motion where they serve the job better. What the host cannot do yet becomes a host ask with a fallback, not a cut idea.

## Tools

- `scripts/audit-page.js`: measures contrast, small text, small targets, unnamed controls, truncation, line length, overflow, type and spacing variety, text load (first-screen words, long text blocks and instructions outside `data-content`), what fills the first screen, and layout defects (text spilling from its box or card, text over text, sticky bars over content, and in diagrams labels wider than their node, connectors that miss their node or meet it at a corner, and nodes cut by the frame). It runs in any page: a Playwright or Puppeteer `page.evaluate` of its text, a devtools console, or a harness that hands scripts a `browser` object. Its counts are candidates to confirm, not verdicts.
- `scripts/capture-tokens.js`: resolves a running product's CSS variables to hex, so a standalone mock uses its real colours.
- `assets/mock-shell.html`: a self-contained shell for mocks with a frame, theme, width and state switches. A host entry may carry a shell with the host's own frame.

## Done means

- Plan: the brief has the person, the jobs relevant to the scope, the inventory of what stays, how it should feel, success measures you can check without users, and open questions. It was approved before building, unless the task said to continue.
- Build: when exploration was warranted, alternatives were compared and one chosen (by the user when they are in the loop, otherwise by you, with the others kept); every job has a screen or state that serves it; every retained action is reachable, and any change to actions, rules or permissions is documented and authorized; the rails pass, with audit unknowns resolved; a signature moment, when the direction has one, works with motion and under reduced motion; text-load flags are fixed or explained; `why.md` lists what changed and why, each departure from a default with its reason, the host asks, and what is not sure yet.
- Review: a verdict (ship, fix then ship, or rethink), findings ranked by severity with evidence, the lenses covered and not covered, and the measurements.
