# Catalog

The skill's rules (`SKILL.md`, `references/`) hold for any interface. The catalog holds what is true only somewhere: reusable interaction patterns, and the facts of one host or platform. Read the catalog entry for the host your product lives in before you plan. When you learn something a later designer would need, add it if your task allows edits to the skill, or propose it in your report.

## What is here

| Entry | Holds |
|---|---|
| `patterns.md` | Interaction patterns for working tools: each with its job, its behaviour, the reason it works and a check. Build them from the host's own components. |
| `hosts/bb/` | bb (an agentic IDE whose plugins draw pages inside it): slots, theme tokens and utilities, the component kit (host components and the `@bb` registry), layout facts, the user's themes, how to look at a live page, and a mock shell with bb's frame. |

## Adding a host

Make `hosts/<host>/README.md` with these sections, and keep files the host needs (captured tokens, a mock shell with its frame) beside it:

1. What the host is, in two sentences, and where its own design guidance lives.
2. Surfaces: every place a product can draw (pages, panels, sidebars, badges, menus), the job each is for, and which are experimental.
3. Tokens: the variables or utilities that carry colour, type, radius and spacing, and the rule for using them. Captured values with the date.
4. Component kit: the host's own components and its design system or registry (icons, status glyphs, overlays, menus, lists, charts, pickers), with what each is for, and what a product may bundle itself.
5. Layout facts: what the host already draws (title bars, navigation) and the sizes left to the product at the widths that matter.
6. Hard rules the host enforces or its guide states (scoping, keyboard, phone sizes).
7. How to look at the real thing: how to open it in a headless browser, the audit options for its root element, and the token capture options.
8. Lessons: findings from past reviews that hold for any product on this host, each with its date and source.

Keep a host entry about the host. A product's own facts (its data, its worst cases, its brief) belong in that product's design folder, not here.

## Adding a pattern

Add a pattern only after it served a real job in two products, or when a host's guide or a study backs it. Give it the same five parts as the others, and name the evidence.
