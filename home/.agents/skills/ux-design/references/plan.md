# Plan mode

Plan before drawing. The output is a brief the user (or the parent agent) approves. Work in a folder the task names; write `brief.md` there.

## 1. Inventory what exists

Before any design, list what the current UI does, from the code and from screenshots, not from memory:

- Surfaces: every page, tab, panel, dialog and host slot (a navigation page, a sidebar, a side panel tab, a badge, a settings section; the host's catalog entry lists its slots) with the job each serves and its source file.
- Actions: every button, menu item, link, shortcut and gesture, with file and line. This list is the contract: each item stays reachable after the redesign, or the brief says why it goes and who agreed.
- Rules: what the product allows, refuses, confirms or times out. A redesign changes presentation and flow; a change to a rule or permission is documented in the brief and agreed by someone with the authority to change it.
- Components: what the host and its design system offer (its own components, its registry, what the product may bundle), from the host's catalog entry or the host's docs, so the design starts from a rich kit.
- Data: the real shapes (types, RPC results, events) with field names, and the awkward cases that exist in real data: the longest titles, the biggest counts, the walls of text, the empty and error states.
- Problems, measured: run `scripts/audit-page.js` on each main surface and record the first-screen blocks, contrast failures, small targets and text sizes. Note duplicated numbers and messages.

## 2. Write the brief

`brief.md` holds, in this order:

1. Who and when. One paragraph: the person, how often they come, on what screen, interrupted or focused, what else they run. Example: "One engineer supervising two to five agent-run projects of up to 40 tasks each, in the tool all day on a 1400 px laptop, coming back because something needs them or to see whether work moves." Another: "A parent planning a week of family meals on a phone on Sunday evening, relaxed, with ten minutes and a toddler nearby."
2. Jobs, usually five to eight, each as "When [situation], I want to [act], so I can [outcome]". Rank them by frequency and by the cost of getting them wrong. Design the top three first.
3. For each top job: the decisions the person makes, and the information each decision needs (Endsley's goal, decision, information breakdown).
4. What stays as it is: the rules and the action inventory, by reference to the inventory file.
5. Success measures you can check without users, usually three to five, each observable: "the answer to 'what needs me' is in the first screen at 1400×900", "a blocked ticket's ask is readable in under 30 seconds", "board content starts within 200 px of the page top", "0 contrast failures in both themes".
6. Constraints: the host's slots and what is experimental (from its catalog entry), theme tokens, widths to support (1400, 720, 390 if the surface reaches a phone), accessibility target (WCAG 2.2 AA), performance.
7. States to design: empty, loading, one, many (the real maximum), error, stale, partial failure, and the host's narrow widths.
8. How it should feel: three words, the moment people should remember, references for mood and behaviour (never another product's identity), and where it must stay quiet. Build mode explores directions from this; leave the layout open.
9. Non-goals.
10. Open questions: what only the user can decide. Ask them before building when the answer changes the design.

Keep the brief about the person and the jobs. A sentence such as "modern and clean" describes no product; replace it with the job it serves.

## 3. Information architecture

Decide what the product holds and how the person moves through it. Leave layout open: build mode explores several structures before one is chosen.

Decide:

- The landing view: what the person sees first, answering the top job. For a work tracker it is usually what needs them, then whether work moves, then what happened since they looked.
- Navigation: what lives in the host's navigation (a sidebar or rail the host gives the product) and what lives in the page. One obvious way to each place; counts on nav items that lead to lists.
- Grouping: by what the person decides or acts on, in one order used on every surface (for supervision and queue tools, by whose move it is: `oversight.md`).
- One canonical detail view per thing, so three surfaces never tell three versions of it. Different lenses on a collection (a list, a map, a timeline, a board) are welcome when each serves a job.
- What folds: what the person rarely needs, behind a count; never what they need to decide safely.

Note the screen sizes and budgets that matter (what must fit in the first screen at the main width), but leave the layout itself to build mode's exploration.

When the brief is done, `why.md` comes later, in build mode (`build.md`).
