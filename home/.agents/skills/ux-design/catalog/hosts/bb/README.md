# Host: bb

bb is an agentic IDE: one person runs coding agents in threads, and plugins add pages, panels and controls inside bb's window through the Plugin SDK. bb's own design guidance is the Plugin Guide inside bb (current slot list) and the bb Kit design guide (process and patterns; read 2026-11-10).

Files here:

- `theme-tokens.json`: bb's theme tokens resolved to hex, captured 2026-11-10 from the running app: gruve light (the user's theme), gruve dark and gruvbox dark (bb built-in).
- `mock-shell.html`: the skill's mock shell with bb's frame (nav rail, page sidebar, title bar) and those three themes.

## Surfaces

Each slot has a job; a surface in the wrong slot either hides or shouts in every thread. Names starting `experimental_` can change: check the Plugin Guide in bb before relying on one, and give each a fallback.

| Slot | Job | Experimental |
|---|---|---|
| `navPanel` | The plugin's page: work across threads, needs you first | no |
| `navPanel` `headerContent` | Controls in bb's title bar for the page (new, search, the page's main action) | no |
| `experimental_sidebar` | The page's own navigation, in bb's page sidebar | yes |
| `experimental_useBadge` | The count on the plugin's rail entry: what needs the person | yes |
| `experimental_tab` | One thing's detail in the side panel, beside a thread or page | yes |
| `settingsSection` | Configuration and facts about the setup | no |
| `experimental_threadContextCardSection` | A thread's context, on a laptop | yes |
| `experimental_threadContextSegment` | A thread's context where the card does not fit (phones, narrow panes) | yes |
| `app.composer.customize` | Something that holds the person's next message, only while it does | no |
| `pendingInteraction` | A question that blocks an agent | no |
| `experimental_setThreadRowStatus` | One fact about a thread that its sidebar row does not already say | yes |
| `experimental_sidebarFooter` | A cross-thread list or control both screens need | yes |
| `experimental_threadAction` | An action on a thread or a selection (thread menu; `placement: "header"` folds into the menu on a phone) | yes |
| `experimental_messageMetadata` | One line on a message: where it came from, why it woke | yes |
| `messageDirective` | A live card inside a message, such as an ask to answer in place | no |
| `homepageSection` | Starting something new from bb's compose page | no |
| Quick Bridge pages | The plugin on a phone, beyond answering questions | yes (the protocol) |

Rules from the Kit guide: put a thread's context in both the card section and the segment while the card is an experiment; there is no header chip slot any more (use a thread action); configuration goes in bb's Settings; a row takes one status, so nothing the person must see lives only there.

## Tokens

- Colours, radius and fonts come from bb's theme variables, so a plugin follows whatever theme the person runs. Never type a hex value in a component.
- bb's Tailwind utilities read them: `text-foreground`, `text-muted-foreground`, `text-subtle-foreground`, `bg-background`, `bg-card`, `border-border-seam`, `bg-state-hover`, `bg-surface-selected`, `text-primary`, `bg-primary text-primary-foreground`, `text-success`, `text-warning-text`, `text-destructive-text`, `bg-surface-attention`, `bg-surface-destructive`, `ring-ring`.
- Needs-you uses `--attention` and the attention surface; selection uses `surface-selected`. Keep them visibly different.
- Follow the theme's `--radius` (the user's themes are square: 0) and font (the user's themes are monospace throughout: JetBrains Mono). Do not add a font family.
- Use bb's own controls (dialog, menu, input, switch, tabs, the thread composer): they own focus, drafts and the phone layout.

## Component kit

bb does not expose its whole UI kit as live components. It gives plugins two things: host components for bb's own capabilities, and a shadcn registry of vendored source taken from bb's own app and matched to the bb release. Read bb's `bb-plugin-authoring` skill, `references/frontend-components.md` and `frontend-hooks-and-ui.md`, before building. Inventory taken 2026-11-10 from SDK 0.6.75 and the registry at `desktop-v0.49.0`.

Host components, `@get-bb/plugin-sdk/app`:

| Component | Use it for |
|---|---|
| `experimental_ThreadStatusGlyph` | The live status of any agent thread (working, waiting, needs input, error), the glyph bb's own lists draw |
| `experimental_Icon` | bb's icon set by name, including icons other plugins register; state marks, row marks, buttons |
| `experimental_ProviderIcon`, `experimental_PluginIcon` | Which agent or model, which plugin |
| `experimental_ShortcutHint` | A key hint beside a control |
| `experimental_DetailRow`, `experimental_InfoList`, `experimental_InfoListRow`, `experimental_InfoSection` | Label and value facts and short lists that fold behind "N more", as on bb's Info tab |
| `Markdown` | Text agents and people wrote |
| `ThreadChat` (`variant` full, compact or timeline) | A live thread inside the page or side panel, instead of re-listing its posts |
| `experimental_Diff`, `experimental_SourceCode`, `experimental_FileLink`, `UrlLink` | Changes, code, files and links with bb's code theme |
| `experimental_VoiceInputTextarea`, `experimental_VoiceInputButton` | Answer fields with voice input |
| `experimental_NewThreadComposer`, `experimental_ProviderModelPicker`, `experimental_BranchPicker`, `experimental_PermissionModePicker` | Starting work, choosing a model or branch |
| `experimental_ThreadActionsMenu`, `experimental_ThreadActionsContextMenu` | bb's thread menu on a row |
| `experimental_useAppPanel()` | Open a tab in bb's side panel from the page or a thread |
| `experimental_copyToClipboard`, `experimental_saveFile`, `toast` from `sonner` | Copy, save, and bb's own toasts |

The `@bb` shadcn registry (`npx shadcn add @bb/<name>`, about 110 items; index at `https://raw.githubusercontent.com/get-bb/bb/desktop-v<version>/packages/plugin-registry/r/index.json`):

- Overlays and menus: `tooltip`, `hover-card`, `popover`, `dropdown-menu`, `context-menu`, `command` (a command palette), `dialog` (a bottom drawer on compact screens), `alert-dialog`, `confirm-delete-dialog`, `sheet`, `drawer`, `menubar`.
- Controls: `button`, `toggle-group` (segmented), `toggle`, `tabs`, `select`, `switch`, `checkbox`, `radio-group`, `slider`, `input`, `textarea`, `form`, `calendar`, `inline-rename`.
- Lists and data: `table`, `resource-row`, `resource-list`, `resource-toolbar` (filter, sort and multi-select menus), `resource-atoms` (status, meta, card stats), `resource-pagination`, `chart` (recharts), `progress`, `workflow-progress` (`WorkflowPhaseStrip`, `WorkflowStatusPill`: bb's phase strip for multi-agent workflows), `badge`, `pill`, `avatar`, `shortcut-pill`.
- Text and layout: `expandable-text` (clamp with "Show all"), `overflow-fade`, `truncate-start` (keeps the end of paths), `resizable` (split panes), `scroll-area`, `collapsible`, `accordion`, `separator`, `split-pane-mini-map`.
- States: `empty-state`, `skeleton`, `delayed-loading`.
- Agent asks: `question-form` (bb's Ask User Question form).
- Motion and sizing: `motion`, `sortable-motion`, `coarse-pointer-sizing`, `use-compact-viewport`, `use-media-query` (dark, reduced motion).

Beyond the kit: a plugin's app bundle may include any React library from its own `node_modules` (only React, the portalling Radix families, `sonner`, `vaul`, `clsx`, `tailwind-merge` and `cva` come from the host). That makes room for motion (`motion`, formerly Framer Motion), graphs (`@xyflow/react`, `d3`, `visx`), custom SVG and canvas, and `tw-animate-css` utilities, which compile in plugin builds. Keep colour on bb's variables there too: SVG `fill: var(--primary)`, and tints as `color-mix(in oklab, var(--primary) 14%, transparent)` (the Kit guide mixes in oklab because oklch shifts the hue). Watch the bundle size, and note each library in `why.md`. What bb itself cannot do (a slot, rail-badge content, animation in bb's own sidebar or title bar) goes in the design's host asks, with the fallback shipped now; the user decides whether to raise it with bb.

Rules: the Radix overlay families, `sonner` and `vaul` are shared with the host at run time, so overlays stack correctly with bb's own. Use `experimental_SourceCode` and `experimental_Diff`, never a diff library directly. Other React libraries bundle from the plugin's own `node_modules`. Style everything with bb's token classes only.

## Layout facts at 1400×900

- bb draws a nav rail (48 px), the page sidebar (about 256 px) and a title bar (about 48 px) with the page's title. The plugin page gets roughly 1090×850 px. Do not repeat the title in the page.
- With a side panel open, a laptop page can be as narrow as a phone: check 1400, 720 and 390 px.
- On a phone: 44 px targets, 16 px text in inputs (iOS zooms smaller ones), and `env(safe-area-inset-*)` padding.

## Hard rules

- Scope every CSS rule to the plugin's root class and prefix keyframes: plugins share one document with bb and each other. Portalled overlays need the same scope.
- No key listener on `document`: it steals keys from the composer and editors. Listen on the plugin's root and ignore keys typed in fields.
- Text 4.5:1 and glyphs, rings and state marks 3:1 in every theme variant, not only the one you use.
- Under reduced motion nothing moves and every state stays visible.

## Looking at the live app

bb's browser automation drives a headless browser on the host machine (see bb's `browser-automation` skill). The host id comes from `bb status` or the error message.

```sh
bb browser-automation open --backend local --headless --machine <host> --json   # keep the id; print its previewDirective once
bb browser-automation run <id> --script 'const p = await browser.getPage("main"); await p.setViewport({width:1400,height:900}); await p.goto("http://127.0.0.1:38886/plugins/<plugin>/<path>"); await p.shot({type:"jpeg",maxEdge:1400,quality:70}); "ok"' --json
bb browser-automation run <id> --script-host <host> --script-file ~/.agents/skills/ux-design/scripts/audit-page.js --json > audit-1400.json
```

- The local bb server is `http://127.0.0.1:38886/`; plugin pages live under `/plugins/<plugin>/<path>`. No sign-in is needed in the headless session.
- A run times out at 120 s, which fits about six screenshots with their audits; it takes at most four screenshots when each is read back as an image. Copy each one out of the session's temporary folder before closing the session (the JSON names its path), and close every session you open.
- Audit only the plugin: set `window.__uxAuditOptions = { root: "<the plugin's root selector>" }` in an earlier run, or bb's chrome is counted.
- Token capture: open bb on any page and set `window.__uxTokenOptions = { skip: "^--(ansi|shiki|shuttle|sb-|gruve|xc-|diffs|lightningcss|sh-|toast|resource|pill|loom|rollout|bb-)" }` first, which leaves out other plugins' private variables and keeps the output under the CLI's 64 KB limit. To capture another theme without changing the person's settings, inject its CSS (bb repo: `apps/app/src/lib/themes/<name>.ts`) and its class in the page, then set `variant`.

## Lessons

- 2026-11-10, computed from `theme-tokens.json`: in gruvbox dark (bb built-in), `subtle-foreground` and `destructive-text` miss 4.5:1 on every surface (4.29:1 on the background, 3.37:1 on a card), and `muted-foreground` misses it on a card (4.47:1). In gruve light, `success` and `warning-text` on the selected surface are 4.42:1 and 4.41:1. Use `muted-foreground` or `foreground` for text that must be read on those surfaces, and measure.
- 2026-11-10, reviews of a large plugin page: stacked header panels above a page's tabs used about two thirds of the height bb leaves the page, so no work showed in the first screen; the page title repeated bb's title bar; one long sidebar list pushed the plugin's other entries below the fold. Plan the first screen as boxes before styling.
- 2026-11-10, first mock of a Loom redesign: the screens were written, not designed (rows as sentences, prose legends, instructions, 396 words on Home's first screen and 523 on the phase gate's) and drew everything as plain text and hairline boxes, while bb offers status glyphs, icons, hover cards, a command palette, charts and its own list rows. Plan the components with the jobs, and measure text load.
- 2026-11-10, Loom mock: in gruvbox dark, `muted-foreground` on tinted surfaces (cards, attention and selected rows, the composer placeholder on a card) measured 3.45 to 4.47:1. Lift text on those surfaces toward `foreground` with a `color-mix` in oklab under a new property name (`--loom-muted: color-mix(in oklab, var(--muted-foreground) 65%, var(--foreground))`), and measure every tinted surface. The mock's own lift redefined `--muted-foreground` in terms of itself, which is a cycle: the token became invalid inside every card, HTML muted text silently inherited `foreground` (so it measured as a pass), and SVG labels using it fell back to black fill, 1.68:1 in gruvbox dark and 1.75:1 in gruve dark.
- 2026-11-10, Loom mock: 98 audit runs reported zero failures while the mock had a pill whose text spilled, a repo card whose count left the card, a sticky footer over the gate's report, overlapping time-ruler labels at 720, labels wider than their nodes, duplicated map nodes drawn on top of each other, nodes cut by the map's camera, and edges that met a bundle bar or a node's status bar at a corner (the user saw them first). The audit now counts these layout defects; still look at zoomed crops of diagrams and run the audit in armed and focused states.
- 2026-11-10, Loom mock: audits rooted at the plugin page (`[data-page]`) missed failures in the plugin's own sidebar and in its overlays (palette 4.06:1, keys sheet 3.93:1, hover cards 4.26:1, active sidebar row 3.04:1 in gruvbox dark). Root the audit at everything the plugin draws, and open each overlay.
- 2026-11-10, Loom build, phase 1: Esc with focus on the page body sends bb to its root on any plugin page, so a plugin that uses Esc (closing a rewind, a pane) must catch it while that state is open. bb's own title-bar buttons are 28 by 28 px at 390 in a 48 px bar. bb's `DetailRow` label is muted text that measures 4.47:1 on a popover in gruvbox dark; lift it inside popovers.
- 2026-11-10, Loom build, phase 1: `bb browser-automation run` returns at most four screenshots and 500 KB per run, a refused run ends the session, and `page.evaluate` passes one argument. Screenshots come back at CSS pixels whatever `deviceScaleFactor` says; for a 2x crop, scale the page with a CSS transform.
- 2026-11-10, the user on the Loom build: the weave's stitched threads, one thin line per ticket, were "incredibly hard to read"; a segmented bar by state with one count replaced it. A signature drawn from data still has to read at a glance at its real size.
- 2026-11-10, Loom mock: `commandPaletteAction` puts a plugin's commands in bb's own palette, and `experimental_sidebar` is the plugin's own React component, so a palette entry and an animated sidebar need no host ask. `experimental_threadContextCardSection` is not in SDK 0.6.75; use the context segment and a side-panel tab.
- 2026-11-10, the user on the same redesign: bb's kit is the floor, not the ceiling. Appeal and feel drive whether people keep using a plugin; explore art directions and go beyond the kit where it earns its place.
- 2026-11-10, Kit guide: draw a dense picture with its full list one tap away, and keep phone answers where the thumb is (docked at the bottom, the main action last).
