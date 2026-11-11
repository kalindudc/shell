# Models for design and review

Which model to run each mode on, and how AI designers and reviewers fail. The picks are deployment preferences for this setup, not UX principles: use what the task or the person names. Evidence gathered 2026-11-09 and 2026-11-10 from leaderboards, vendor tables and practitioner write-ups, several read through secondary summaries; leaderboards move every few weeks, so recheck before relying on a rank.

## Picks

| Mode | Model | Effort | Runner-up | Why |
|---|---|---|---|---|
| Plan and build | Claude Opus 5.5 | high or more | Claude Fable 5.2 (twice the price), Claude Sonnet 5.5 for routine screens | Tied for first on Arena's WebDev board (1818 versus Fable 5.2's 1832 on 2026-11-09, within noise); practitioners prefer it for open-ended UI; half Fable's price |
| Review | GPT-6.1 Sol | xhigh | none without the person's approval | Another family than the designer, at a cost a loop of many reviews can carry; the person's choice on 2026-11-11; no study ranks current models at UI critique |

Run the reviewer on another model family than the designer when you can: a model is blind to its own habits. No published evidence shows that maximum effort improves design or critique, and coding data shows small losses past high; more effort for a designer exploring widely is a reasonable bet, not a proven one.

## How AI designers fail

- Current models tend to share one default look when given no direction: a cream background, a serif headline with one italic accent word, numbered "01 / 02" labels, monospace eyebrows and pill buttons (Anthropic's prompting guide for Opus 5.5, read through a secondary summary; Design Drift, designdrift.io/models; Velox Themes, veloxthemes.com/blog/fable-vs-opus-web-design; 2026-11). Give the designer the host's tokens or a style guide, and question that look when nobody chose it; it is a fine choice when the direction calls for it.
- With a design guide, Opus 5.5 and Fable 5.2 produce near-identical pages: "the design you give the AI mattered more than which model you pick" (Velox Themes, 2026-11-10).
- Models invent content: awards, quotes, numbers (Design Drift on Gemini 4 Argon). Use the product's real data.
- Language models explain instead of showing: rows become sentences, legends become paragraphs, every control gets an instruction beside it, and documentation writing rules leak into interface copy (a dated example is in `catalog/hosts/bb/README.md`, Lessons). The designer checks text load with the audit before reporting; its flags are candidates to fix or explain, and a reviewer does not count prose as "more informative".
- Told to be calm and follow rules, they produce timid, uniform screens: one weight, flat boxes, no focal point, no motion, and the same layout every time. Ask for wide exploration first (`build.md`), name the feel, and judge appeal as its own lens.
- They draw from scratch: plain text, links and boxes in place of the host's icons, status glyphs, menus, hover cards and charts. The brief lists the host's kit (`plan.md`); after structural exploration, reuse the host's standard controls for their behaviour and replace kit views where a custom one serves the job better (`build.md`); the review checks the result.

## How AI reviewers fail, and the rule each needs

| Failure | Evidence | Rule |
|---|---|---|
| Many AI-only findings are wrong | MeasuringU (2026-05, measuringu.com/does-ai-find-real-ui-problems-or-just-hallucinations, one usability video, older models): about nine in ten problems only the AI raised needed correction or dismissal; Scry Design Diff Eval (2026-07, blog.scrymore.com/blog/introducing-scry-design-diff-eval, mobile screens): best recall 40% at 16% precision | Every finding cites evidence: a measured value, a DOM node, a screenshot region, an observed behaviour, or a location in the brief; a finding without evidence is dropped |
| They flag clean screens | Scry: the high-recall models flagged 92 to 100% of screens with no defect | Review at least one screen you expect to pass; "no issue found" is a valid result |
| They prefer busy pages | DesignArena judge study (2026-11-01, LinkedIn summary of the study; 1,700+ page pairs): with 2.5 times the text on the first screen, AI judges picked the busier page 83% of the time, people 63%; judges almost never called a page cluttered | Judge density against the person's job, not against "more information"; a dense page still has to answer the top job first |
| They claim compliance without measuring | A model said a screen met WCAG AA while its button measured 2.80:1 (Fello AI, felloai.com/best-ai-for-ui-design, 2026-11) | Contrast, target size and text size come from measurement (the audit, a contrast checker, the accessibility tree), never from looking; report what could not be measured |
| Typography and fine spacing are hardest | Scry: 20% best recall on typography | Measure type sizes and spacing with the audit; look at a crop, not the whole page |
| Findings vary between runs | MeasuringU | For a decision that matters, run a second pass (another model or another run); findings both raise are the strongest, and a finding only one raises is checked against the evidence, not dropped |

Vision agents that operate the page find more accessibility failures than rule checkers (86% versus 36% for axe-core, at 56% precision; arXiv 2609.09379), so a review that tabs through the page beats one that only reads screenshots.

## Cost

Use only the models in the picks above unless the person approves another, and name its price when you ask. In the Loom overhaul (2026-11-11), GPT-6 Astra cost $0.23 a call against $0.10 for Opus 5.5 and $0.03 for GPT-6.1 Sol, and its 17 review threads cost $339, more than a third of the whole project.
