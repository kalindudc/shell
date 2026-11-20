# Critique: independent review by critics on three model families

Use critics for a high-risk change, a plan, or anything where being wrong is expensive. The question for each finding or concern is: is it real, backed by evidence, and significant, or is it speculative noise? `briefs.md` has the critic brief template.

## Choose the critics once

- Pick three critics on three different model families, so no single vendor's blind spots decide a finding. Keep the count odd, so one dissent or one critic that fails to start can't decide alone.
- Write the exact model ids your harness accepts in `RULES.md`, and use them as written every time. Don't swap a critic for another model because it's slow or fails to start: report the missing vote instead.
- Check the model each critic actually started on, from what the spawn tool or `fleet.py status` reports. A critic's answer about its own model is not evidence, so never ask it. A critic on the wrong model doesn't count as a vote.

## Run a review

1. Screen first. Check each concern against the source yourself, or with one verifier on your own model. Drop what the evidence doesn't support, and say so. Nothing left means no critics.
2. Write one brief file with the concerns, the evidence, the criteria below and the source scope. Each critic's task says to read that file in full and vote. Never send a placeholder in place of the brief.
3. Each critic investigates on its own and votes KEEP, REJECT or ABSTAIN per concern, with what it checked, the counter-argument it considered and its reasoning.
4. Call a concern validated when at least `max(2, floor(N / 2) + 1)` distinct models vote KEEP. Abstentions, timeouts and failed critics never lower that bar.
5. Agreement is a filter, not proof. One critic's verified blocker still blocks. When evidence contradicts the votes, look at that conflict and report it; don't rerun until the vote you want appears.

KEEP a concern only if it names a real issue, its evidence checks out against the actual code, docs or artifacts, and its impact is concrete. REJECT it if it is speculative, contradicted by the source, a matter of taste, a theoretical scenario with no plausible trigger, or claims more severity than its evidence supports. Intended behaviour isn't a defect unless it conflicts with the human's goals or causes concrete harm.

## Report

Consolidate the votes into one table for the human: concern, votes, main evidence and recommendation. List directly verified concerns that missed the quorum separately, labelled as not validated by consensus, and say why. After fixes, run a second pass on the new revision that marks each earlier concern fixed, partly fixed or not fixed, with evidence, and checks for regressions.
