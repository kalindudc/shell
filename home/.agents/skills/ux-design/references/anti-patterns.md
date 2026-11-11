# Anti-patterns

Four families of flags: the tells of generic machine-made UI, a wall of text, a bland screen, and the patterns that waste a working person's screen. A flag is a question, not a ban: fix it, or keep it and say in `why.md` what it does for the person. Sources on the first family are practitioner write-ups (Anthropic's frontend-aesthetics cookbook, Mowgli, Yaps); their agreement is the evidence. Their advice to make it dramatic is good when the drama serves the person (understanding, orientation, identity, delight) and bad when it only decorates.

## Generic machine-made UI

| Tell | Check | Fix |
|---|---|---|
| A card around everything, same radius, same shadow | count bordered containers per screen; most sections are identical boxes | one primary block per region; rules and whitespace, not boxes; tables for rows |
| Big-number tiles in a strip | tiles that repeat numbers shown elsewhere, or numbers without context | one status line with the numbers in words, each with its comparison |
| Icons that label nothing | icons in tinted squares beside every heading; emoji used as bullets | icons where they label an action or a state, with text for state; a playful icon set is fine when it is the product's voice |
| Decoration without meaning: stock gradients, glass, glows, a purple or neon accent | an effect that encodes nothing, or a colour outside the theme | depth and tint mixed from the theme's tokens, used to separate layers or carry focus |
| An eyebrow over every heading | count section labels per screen | labels where they name a region the person scans for |
| Grey text on grey | audit `contrast` | host text tokens that meet the contrast threshold on the actual surface in every supported theme; measure muted and subtle text too |
| Fade-up or shimmer on everything | animations on load or idle that mean nothing | motion on change and for the signature moment; an idle loop looks like work unless something is working |
| Generic copy: "Supercharge", "Seamless", "Unlock", "Overview" | copy test: could this sentence appear unchanged in another product? | name the person's object and the action |
| Placeholder data | "Lorem", "Item 1", "Task A", tidy short names only | real shapes and the longest real values |
| Only the happy state | no empty, error, stale, loading or many state | the states matrix in `build.md` |
| Text that spills from its pill, card or node; a sticky bar over the content it belongs to | audit `textSpill`, `textOutsideBox`, `svgLabelOverflow`, `overlappingText`, `coveredBySticky`, in every state and width | boxes sized from the longest real value, wrapping or a deliberate cut with the full text one step away; reserve the sticky bar's height in the scroll area |
| Diagram edges that look loosely attached: ending short of a node, landing on a node's corner or on a decoration inside it, joining a bar at its corner | audit `looseConnectors`, `clippedShapes`; a zoomed crop of every diagram | edges attach to ports on the node's border at a fixed point, enter at a consistent angle, and a bundle or junction is joined along its edge; let the layout library route edges; the camera frames whole nodes |
| One spacing value off the scale here and there | audit `offScaleSpacing`, `distinctSpacingValues` | one 4 px scale |
| Too many type sizes | audit `distinctFontSizes` over six | a scale of four or five steps |

## Wall of text and plain-text UI

The tells of an interface written instead of designed. Language models fall into them by default (`models.md`).

| Tell | Check | Fix |
|---|---|---|
| Rows whose second line is a sentence | audit `longTextBlocks`; second lines that truncate or repeat the state word | the state word plus two or three short facts; the rest in the detail view or a hover card |
| Instructions for familiar interactions | audit `instructionalText`: "click", "to see", "move with", "you can" | affordance, shortcut pills and tooltips; keep instructions for unfamiliar interactions and for consequences |
| A legend or explanation as a paragraph | text blocks under a chart or graph that explain its marks | marks with one or two words, or a tooltip on each mark |
| The next step or a consequence as a paragraph | a sentence beside the primary button that restates it | the button names the action; consequences as short facts |
| Meta text about content | a sentence about what the content below is or is not ("No summary: the author wrote prose") | drop it; show the content, or a badge |
| A column of placeholders | "not checked" repeated down a column, with a note explaining why | leave the column out until there is data |
| Plain-text UI | a screen drawn only from text, underlined links and hairline boxes, while icons, status glyphs, menus, tooltips, hover cards, charts and pickers are available | draw state with glyphs and icons; put detail on demand in overlays; give the core idea a visual |
| Hand-rolled standard controls | a custom menu, tooltip, dialog or tab bar where the host's kit has one | the kit's component, which already owns focus, keyboard, phone layout and theme; custom views and visuals are a different matter (`build.md`) |

## Bland: tidy but lifeless

| Tell | Check | Fix |
|---|---|---|
| No focal point | blur the screenshot: nothing stands out, or everything does | one hero element per screen, by scale, weight or contrast |
| One size, one weight everywhere | no size or weight step between titles, numbers and body | a bold step for hero numbers and titles inside the host's font |
| Every region is the same flat box | the same border and background on every region | layers: a raised surface for what you act on, recessed for context, from the theme's tokens |
| The product's core idea drawn only as words | its central concept (progress, a graph, a timeline) appears nowhere but in a list of words | consider a crafted visual of it, with the list one step away |
| Nothing moves when things change | rows jump between groups; a selection appears without transition | motion from old place to new (`principles.md`, motion budgets) |
| Controls that do not answer | no hover, press or pending state; a click with no response under 100 ms | state on every control; optimistic updates |
| An art direction nobody chose | no three words, no signature moment in `why.md` | explore before converging (`build.md`) |

## Space wasters on working screens

| Pattern | Check | Fix |
|---|---|---|
| Stacked header panels (about, next step, metrics, timeline) above the content | audit `firstScreen`: the content starts below about 40% of the viewport, and the panels do not answer the top job | compact chrome with the next action; the rest as facts and folds, or a side column. A visual that answers the top job is content, not chrome |
| One card's long text sets a whole row's height | a row much taller than its neighbours; empty space beside a tall card | clamp to two or three lines with "Show all" |
| Narrow column of long text in a wide table | wrapped cells three lines or more while other columns are empty | give the text column the free width; truncate with a title; move detail to the detail view |
| The same count in five places | the same number in the header, a tile, a legend, a tab badge and the sidebar | show it once where the decision is made; elsewhere a mark or nothing |
| The same "needs you" message in three places | identical sentences in the next-step bar, a tab notice and a panel | one queue item; other places link to it |
| A grid with empty columns | a five-column grid holding three cards | size the grid to its content or use a row |
| Lists that push everything else out of the sidebar | the sidebar's other groups fall below the fold | fold long groups with a count; group by what the person acts on |
| Title repeated | the host's title bar, an h1 and a breadcrumb all say the same thing | drop the h1 when the host shows the title |
| A full-width banner for a state the header could carry | a banner that says what the state word already says | the state word in the header plus the queue item |
| Tables whose model or path columns wrap | a monospace value wrapping to three lines | shorten the value (family name, last path part) and put the full value in a title or the detail view |
