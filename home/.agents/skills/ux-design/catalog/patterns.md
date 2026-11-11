# Patterns

Interaction patterns, each with its job, what it does, why it works, and a check a reviewer can run. They describe behaviour, not a look: build them from the host's components and tokens, in your direction's style. Use a pattern when its job is yours; none is required. Most come from working tools (products a person uses often, to watch work and make decisions); the ones under "Any product" apply more widely.

Sources: Nielsen's heuristics, Shneiderman's mantra, the oversight research in `references/oversight.md`, and one host design guide, the bb Kit guide (read 2026-11-10), where marked "host guide". The rest is design judgement.

## Working tools: landing and structure

### Operational screen

- Job: let someone who works in the tool all day see what needs them and act, without hunting.
- Does: compact chrome (around 48 to 64 px of header, the host's title not repeated), the content the person came for starting near the top and filling most of the first screen, the next action beside what it acts on, summaries in one row or a side column rather than stacked full-width panels, and long text clamped with a way to read all of it. When a visual (a map, a timeline, a phase strip) answers the top job, it is the content.
- Because: most viewing time stays in the first screen (NN/g scrolling studies), and stacked chrome pushes the work out of it.
- Check: at the main width, the top job is answerable from the first screen, and chrome takes less than about 40% of it.

### Status line

- Job: answer "is it on track, and what does it need from me?" before anything else.
- Does: one line at the top of a thing's page: a state glyph and word, then two to four short facts, then the one or two sections that matter now, then the rest folded with counts. Not a sentence: "Paused · 3 need you · oldest 4 d", not "The project is paused and three things need you."
- Because: people read the first line and the left edge; a grid of equal panels makes them assemble the answer themselves (Gerhardt-Powals: fuse data into higher-level summaries).
- Check: cover everything below the first line; the person can still say what state it is in and what it needs.

### Group by whose move

- Job: show what the person must act on before what others are doing.
- Does: every list groups in one fixed order: needs you, failed, ready for you, working, waiting on others or paused, done (folded with its count). Empty groups disappear.
- Because: the order is the person's priority, and a fixed order lets them find a group without reading (consistency, Nielsen 4).
- Check: the same thing appears in the same group on every surface; no surface invents another order.

### Master-detail

- Job: walk a list one item at a time without losing the place.
- Does: list and detail side by side; selecting a row opens its detail beside it. Below about 1000 px the detail replaces the list and Back returns to the same row, scroll and filter intact.
- Because: click, read, Back, find the place, click the next costs a re-scan each time (Shneiderman: details on demand, keep the overview).
- Check: open the fifth row, go Back: the list shows the fifth row selected at the same scroll position; nothing scrolls sideways at 720 px.

### One reading view per thing

- Job: stop the person reconciling three versions of one item.
- Does: one canonical detail view per item, which every list, map or board links to. Different lenses on a collection (a list, a map, a timeline, a board) are welcome; each shows the item the same way and opens the same detail.
- Because: duplicated detail views drift apart and each repeats numbers the others show.
- Check: open one item from every lens; each lands on the same detail, and its state and counts read the same everywhere.

### Hide noise, but say it exists

- Job: keep a quiet view without making things vanish.
- Does: hidden items leave a line with their count and a way to show them ("13 finished projects", "8 workers hidden").
- Because: silent filtering makes people distrust the list (visibility of system status, Nielsen 1).
- Check: every filter or fold that removes rows says how many it removed.

## Working tools: decisions

### Decision queue

- Job: answer what is waiting on the person, fastest first.
- Does: one row per decision: title, where it comes from, what kind of decision, what answering unblocks, and the wait on the right; the longest wait (or the most urgent) first. Opening a row shows one reading view with the recommendation, an "Other" with a note, what the answer changes, and what happens meanwhile. The recommendation is pre-selected only when the choice is low-risk and easy to undo. Keys: J and K to move, number keys to pick, Enter to send.
- Because: a recommendation makes the common answer quick; "what it changes" lets the person judge the risk without opening other pages (host guide).
- Check: from the landing view, the oldest decision can be answered with the keyboard alone, and focus moves to the next decision afterwards.

### Confirm in place

- Job: stop accidents on actions that are destructive, affect other people, or are hard to undo, without slowing everything else.
- Does: the button turns into "Yes, <action>" beside Back, with no timer; Escape is Back. Reversible actions take one click. A typed name only for irreversible data loss.
- Because: "a timer punishes a slow reader" (host guide); confirming everything trains people to click through (error prevention, Nielsen 5).
- Check: list every action that asks twice; each one is destructive, affects others or is hard to undo.

### Buttons that say what they do

- Job: let the person act without reading the help.
- Does: the label names the action and its object, briefly ("Publish to all users", "Comment on 1, 2 and 4"). Consequences sit beside it as short facts ("1,240 people · can be undone for 10 min"); for an irreversible action, say plainly what it will do.
- Because: a generic "Submit" or "OK" makes the person recall what it does (recognition over recall, Nielsen 6).
- Check: read each button out of context; you can tell what happens and to what.

## Working tools: facts and history

### Fact line

- Job: give one thing's state in a glance, in a row or a header.
- Does: short phrases, state first, separated by a middle dot or spacing, wrapping between phrases, never inside one: "Working · 3 of 8 done · 2 PRs wait on review · oldest 2 d".
- Because: people scan the start of lines (layer-cake reading, NN/g); a fact line replaces a strip of tiles at a fraction of the height.
- Check: the first word of each fact line is a state word from the product's fixed list.

### Claims beside facts

- Job: keep what an agent says apart from what the system observed.
- Does: show the agent's claim ("tests pass") beside the system's reading (the check run and its result); never turn a claim into a verdict.
- Because: supervisors over-trust automation that reports its own success (oversight research: automation bias).
- Check: every "done" or "passed" on screen links to the evidence the system read, not only to the agent's text.

### Event history

- Job: answer "what happened, and since when?".
- Does: newest first, who in bold, what happened, time right-aligned; filter chips with counts; older entries folded as "N earlier"; an action on each row where one exists (Open, Retry).
- Because: one history read the same way everywhere replaces per-surface logs.
- Check: a reload keeps the filter; the newest event is at the top without scrolling.

### Since you looked

- Job: catch up after an interruption.
- Does: a short strip of what changed since the person's last visit (landed, failed, now needs you), each a link, cleared when read.
- Because: resuming after an interruption is slow and error-prone (Mark et al. 2008); a diff of the state is faster than re-reading the whole page.
- Check: leave and come back after a change; the change is named in the first screen.

### Segmented progress

- Job: show how a whole splits across states.
- Does: one bar whose segments are the states, with the counts written as words beside it; never colour alone.
- Because: a greyscale or colour-blind reader still needs the split (WCAG 1.4.1).
- Check: the greyscale screenshot still shows every count.

## Any product

### Detail on demand

- Job: keep the screen focused while every fact stays one step away.
- Does: a hover card on a row's mark or key shows its facts (what it waits on and unblocks, its PR and checks, why it is paused); a tooltip gives the why of a control; a popover holds a small form. Each opens on hover and on focus, and by key, and never holds the only way to act.
- Because: "every extra unit of information competes with the relevant units" (Nielsen 8); progressive disclosure keeps the first level short (NN/g).
- Check: necessary instructions, consequences and recovery stay inline; every other explanation is reachable from the control it explains, by keyboard and touch.

### Fold with a count

- Does: "Done (13)", "7 earlier"; the fold remembers whether it was open.
- Because: the count keeps the hidden part visible as information (progressive disclosure, NN/g).
- Check: every fold shows a count and keeps its state across a reload.

### Clamp long text

- Does: agent output, reasons and descriptions show two or three lines with "Show all"; one item's text never sets a row's height.
- Because: one wall of text pushes everything else off the screen.
- Check: put the longest real text in; neighbouring items do not move down.

### Copy value

- Does: shows the value, copies it on click, and says "Copied" to the eye and to a screen reader (`role=status`); says so when the clipboard refuses.
- Check: a screen reader announces the result once.

### Problem states

- Does: a Retry that works; the error under the control that failed; "as of 10:42" on stale data; a one-sentence empty state that says what will fill the space.
- Because: help people recognise, diagnose and recover from errors (Nielsen 9).
- Check: unplug the data source; every region says what is wrong and offers the next step.

### Keys and gestures

- Does: every gesture has a key and a button; shortcuts are scoped to the product's root, ignored while typing in a field, and shown in hints.
- Because: a global key listener steals keys from editors and other panes (host guide); not everyone can drag or swipe (WCAG 2.5.7).
- Check: type a shortcut letter in a text field; nothing happens but the letter.

### A picture has a list

- Does: a diagram or graph keeps a complete list one step away, and the list is what a screen reader gets.
- Because: a dense picture cannot be read on a phone or by a screen reader (host guide).
- Check: every node in the picture appears in the list with its state in words.
