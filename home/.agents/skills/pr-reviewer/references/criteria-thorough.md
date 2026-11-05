# THOROUGH critic criteria

The Stage 3 criteria for a THOROUGH review. The reviewer reads this before the Stage 2 pre-filter and puts it in the critic brief as written, with the THOROUGH severity tiers from Stage 2.

THOROUGH criteria. REJECT if any of these apply:
- Formatting, or anything a configured linter or formatter catches
- A preference with no stated cost to users, callers, operators or readers
- Theoretical optimization or speculative concern without evidence
- Scope creep (redesign beyond the PR)
- Hallucinated standard, API behavior or codebase convention
- Pre-existing issue the PR does not introduce or make worse
- Missing nil/null check with no reachable failure path
- An intentional design decision the PR gives a reason for, unless the finding shows a concrete defect in it. A PR that only states a behavior ("auto-expires on X") has not given a reason for it
- Encapsulation re-litigation (called method already handles it)
- Production standard applied to scripts, CLI tools, or test fixtures
- A practice a specialist source's exemption file sanctions, for the claim and subject it names
- Severity overstated enough to mislead the author (a nit sold as Medium)

KEEP only if ALL true:
- ACCURATE: the claim matches the code, verified by reading it
- INTRODUCED or made worse by this PR (added or modified lines, or missing tests for them)
- ACTIONABLE: names a specific change the author can make
- WORTH THE AUTHOR'S TIME at its stated severity

A simplicity or scope finding is a factual claim when it cites the stated intent and either a simpler form or the behavior nothing asks for. Judge it on these rules:
- A simpler form that covers at least the cases that matter is not a preference: the complexity's cost falls on every reader, and that is a stated cost. KEEP it; REJECT it only when the proposed form drops a case the intent or evidence needs, including variants a client can produce for free. A form that also widens the match qualifies only when the finding cites the PR's own evidence that the added matches are harmless; without that citation, a widening form is a behavior change, not a simplification. Judge the finding against the best simpler form you can verify, not only the one it proposes: if a scope-preserving form exists, the complexity claim stands even when the proposed form is too broad. Name that form in your verdict, and the reviewer replaces the finding's suggestion with it before posting.
- Weigh a stated reason against the PR's own evidence. A reason the PR's own analysis undercuts, such as a time limit "for safety" on a change the PR shows is harmless to keep, is not a reason, and neither is a bare statement of the behavior.
- When an automatic expiry, timeout or kill switch ends a mitigation, the state it returns to is the problem the PR exists to fix. That is the behavior's cost, not a neutral baseline, and it needs no evidence that the replacement will be late.
- Precedent counts only from code that does the same job: a time window for a scheduled event is no precedent for ending a mitigation on a date.
