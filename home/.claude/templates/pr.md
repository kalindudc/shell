## Summary

[Top level summary of the changes]

**Key changes:** 
[Highly technical summary]

Example:
- Implements functionality described in commit: [commit message]
- Maintains backwards compatibility with existing configurations

## Changed files

**CRITICAL REQUIREMENT**: The file tree should only display the changes files in a tree format WITHOUT any other details, the tree display should only contain information of the actual files that were changed.

[changed files as a tree]

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
[Full technical description of this change, capturing all necessary details]

**Edge cases handled:**
[Edge cases that have been handled as part of this change]

**Testing:**
[Test coverage details]

## Gotchas / Things to note

**Important considerations:**
- Review commit message for context
- Check CHANGELOG.md for user-facing impact details
- Verify test coverage matches new functionality

[Note down any other changes that are critical for an effective PR review for the reviewers]