## Summary

<TOP_LEVEL_SUMMARY_OF_THE_CHANGES>

**Key changes:**
<TECHNICAL_SUMMARY>

Example:
- Implements functionality described in commit: <COMMIT_MESSAGE>
- Maintains backwards compatibility with existing configurations

## Changed files

**CRITICAL REQUIREMENT**: The file tree should only display the changes files in a tree format WITHOUT any other details, the tree display should only contain information of the actual files that were changed.

<CHANGED_FILES_AS_A_TREE>

File tree format:
```
foo/bar/
├── src/
│   ├── modules/
│   │   ├── foo.rs                           (+100 -10)
│   │   └── tests/
│   │       └── foo.rs                       (+1,000 -100)
│   └── tests.textpb                         (+0 -200)
├── config/
│   └── config.json                          (+200 -10)
└── docs/                                    (new)
    └── README.md                            (+500 -10)

5 files changed: 1,800 insertions, 330 deletions
```

## Technical Details / Edge cases

**Implementation changes:**
<FULL_TECHNICAL_DETAILS_DESCRIPTION>

**Edge cases handled:**
<HANDLED_EDGE_CASES_AS_BULLETS>

**Testing:**
<TEST_COVERAGE_DETAILS>

## Gotchas / Things to note

**Important considerations:**
- Review commit message for context
- Check CHANGELOG.md for user-facing impact details
- Verify test coverage matches new functionality

<NOTE_ANY_OTHER_CHANGES_THAT_ARE_CRITICAL_OR_IMPORTANT>
