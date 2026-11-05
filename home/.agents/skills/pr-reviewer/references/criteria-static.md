# STATIC critic criteria

The Stage 3 criteria for a STATIC review. The reviewer reads this before the Stage 2 pre-filter and puts it in the critic brief as written, with the STATIC severity tiers from Stage 2.

STATIC criteria. REJECT if any of these apply:
- Style, formatting, linting, or naming issue
- Testing suggestion (unless a test doesn't test what it claims)
- Best practice or maintainability concern without behavior change
- Theoretical optimization or speculative concern without evidence
- Scope creep (redesign beyond the PR)
- Hallucinated standard or API behavior
- Pre-existing issue not introduced by this PR
- Missing nil/null check with no reachable failure path
- Intentional design decision (the PR clearly intends the change)
- Encapsulation re-litigation (called method already handles it)
- Production standard applied to scripts, CLI tools, or test fixtures
- A practice a specialist source's exemption file sanctions, for the claim and subject it names

KEEP only if ALL true:
- REAL bug, security vuln, or logic contradiction
- INTRODUCED by this PR (in added/modified lines)
- CONCRETE, PROVABLE, IMMEDIATE impact
- Verified by reading the actual code
