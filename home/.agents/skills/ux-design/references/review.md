# Review mode

Review a brief, a mock or a shipped UI. You are independent: you change nothing you review, and you write only the outputs the task authorizes: always the review file, and screenshots and audit JSON in an evidence folder only when the task allows it. You judge against the brief's jobs and its intended feel, not your taste. If there is no brief, write the persona and jobs yourself first and mark them as assumptions.

## Procedure

1. Read the brief and `why.md` if they exist. State the person, the jobs and the success measures in three lines at the top of the review. Each complaint the requester states ("it wastes space", "big projects are hard to follow") is a hypothesis to test: make it a job or a lens, and give it a verdict with evidence in the report.
2. Inventory what you review: screens, states, modes, actions with side effects. Take screenshots at 1400×900 and 720 wide (390 if it reaches a phone), in the person's theme and one of the other polarity. Look at each one. When the product lives in a host, read the host's catalog entry for how to open it and its known lessons.
3. Measure: run `scripts/audit-page.js` on each main screen. Record contrast failures, text under 11 px, targets under 24 px, unnamed controls, truncation without a title, layout defects (`textSpill`, `textOutsideBox`, `overlappingText`, `coveredBySticky`, `svgLabelOverflow`, `looseConnectors`, `clippedShapes`), the first-screen blocks and their heights, and the number of type sizes. Run it again in the states actions open (an armed confirmation, an expanded row, a focused map, each overlay, a narrow width), because defects often appear only there. Set its root to everything the product draws, including its own sidebar and portalled overlays; a page-only root hid dark-theme contrast failures in one review. A `looseConnectors` entry with `atCorner` is not a gap: the line touches its shape at a corner, which people see as loosely attached; confirm it on a crop. Then look at zoomed crops (device scale 2) of every diagram, card row and sticky bar: a script cannot see an edge that lands on the wrong part of a node. The audit's counts are candidates: confirm each one you report on the screenshot or in the DOM. Contrast, size and target claims come only from measurement, never from looking.
4. Walk the top three to five jobs as a cognitive walkthrough. For each step, answer the four questions with screen evidence: will the person try to do the right thing; will they notice the control; will they connect the control with what they want; will they see that it worked? Each "no" is a finding.
5. Run separate lenses, writing each lens's findings before looking at the others:
   - Hierarchy and density: squint test, first screen, space wasters, duplicated numbers, and text load: sentences where marks, numbers or labels would do, instructions for familiar interactions, prose legends, and the opposite, missing words people need to act safely (`principles.md`, "Show more than you tell"; audit `longTextBlocks`, `instructionalText`, first-screen words).
   - Oversight, when agents or other people do the work: state, age and whose move on every row; the needs-you queue; projection; review load (`oversight.md`).
   - Heuristics: Nielsen's ten, each with a pass or a finding.
   - Accessibility: the WCAG 2.2 AA table in `principles.md`, with keyboard checks you can perform.
   - Appeal and feel, against the intended experience in the brief and `why.md`: the first glance (three words from a few seconds' look, against the feel words), focus under blur, depth and layers, the signature visual and moment, motion on change and under reduced motion, the response of every control, and bland or timid choices where a bolder one would serve the person better (`principles.md`, "Appeal and feel"). A quiet screen that was meant to be quiet and serves its job is not bland. A beautiful screen never lowers another finding's severity.
   - Craft: `anti-patterns.md`, spacing rhythm, type scale, states matrix, words, and use of the host's kit: hand-rolled standard controls where the kit has one, state drawn as text where glyphs and icons would do, detail inline where an overlay belongs.
   - Contract: every retained action in the inventory is reachable; any change to an action, a rule or a permission is documented in the brief and authorized.
   - Departures: for each departure from a default listed in `why.md`, does its reason hold? A documented departure is not a finding by itself.
6. Merge and de-duplicate. Rate each finding from 0 to 4 (below). A polished look never lowers a rating.
7. Write the verdict and the report.

## Severity (Nielsen)

| Score | Meaning |
|---|---|
| 4 | Catastrophe: blocks a top job, loses data, or misleads about state. Fix before shipping. |
| 3 | Major: a top job is slow or error-prone; a WCAG AA failure on a main path. |
| 2 | Minor: friction on a secondary job, inconsistency, wasted space that pushes content down. |
| 1 | Cosmetic. |
| 0 | Not a problem (use it to record a deliberate decision you checked). |

Rate every finding from frequency (how often people meet it), impact (how hard to overcome) and persistence (once or every time); no kind of finding has a fixed severity.

## Findings

Each finding has:

- Location: screen, region and element (a selector from the audit, or a screenshot path with coordinates).
- What you see, as evidence: the measured value, a quote of the text, or the behaviour you observed. Say which it is: measured, observed, or your judgement.
- Why it matters: the job it hurts, and the rule, default or principle it touches when there is one (a WCAG SC, a reference rule). A real problem that no listed rule covers is still a finding.
- Severity, 0 to 4.
- The smallest fix.

Reject your own findings that only say "feels cluttered" or "looks dated": say what the person cannot do or what it costs them, or drop it. Decline a finding about an impossible state, with the reason.

AI reviewers have known biases (`models.md`): many findings only a model raises are wrong, they flag screens that have no problem, and they prefer pages with more text. So: a finding without evidence is dropped; a screen with no real problem gets "no issue found"; density is judged against the person's job, never as "more information"; and contrast, size and target claims come from measurement. When two reviewers are used, findings both raise are the strongest; a finding only one raises is checked against the evidence, not discarded for lack of agreement.

## Report

`review.md`:

1. Verdict: ship, fix then ship, or rethink, in one sentence with the reason.
2. The person, jobs and measures you judged against.
3. Findings, highest severity first, grouped by screen.
4. What works and should stay (short).
5. Measurements: the audit summary per screen and theme, with what it could not measure (`contrastUnknown`, custom widgets, keyboard). When an evidence folder is authorized, save screenshots and each full audit there and link them; otherwise include bounded measurements, observations and limitations in the review. Never paste whole audit output into the review.
6. Coverage: the lenses you ran and did not run, and states you could not reach. State your coverage limits: one human evaluator finds about a third of the problems in heuristic evaluations (Nielsen), but that does not establish an AI reviewer's recall. Label it "expert review, not user validation" and list what needs real users.
7. Targets for the fix: observable checks a redesign must pass, one per finding of severity 3 or 4 ("a 3,000-character blocked reason takes at most three lines on the board").

## Reviewing a requirements brief

When the task is to review requirements rather than screens: check that the jobs are the person's (not the system's), ranked, and fit the scope (usually five to eight for a full product); that the inventory is complete against the code; that each success measure is observable; that the states list includes the real maximums; and that open questions are ones only the user can answer. Findings use the same format, with the brief's section as the location.
