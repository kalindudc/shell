---
name: generate-pr-description
description: Creates a structured PR description for the current branch
---

# Generate PR Description

Automatically generates a PR description for the current branch by analyzing git changes and following the required format standards: $ARGUMENT

## Rules
- ALWAYS use the `Write` tool, NEVER use the `>` tool when updating a file or create and writing to a new file
- ALWAYS use single bash commands, NEVER combine commands with `&&`
    - All commands that need to run must be run as a single command, for example `git status && git diff` should be separated into the following 2 commands
        - `git status`
        - `git diff`
- FOLLOW KISS (keep it simple stupid)
- Be thorough in analyzing the changes
- Spawn subagents if needed for complex analysis
- Always format any generated docs in markdown
- Before starting, remove the following files so you are not re-using any old research documentation
    - `rm ./tmp/research_docs/ai/current_pr_diff.txt`
    - `rm ./tmp/research_docs/ai/changed_files_summary.txt`
    - `rm ./tmp/research_docs/ai/pr_analysis.md`
    - `rm ./tmp/pr/<branch_name>-pr.md`

## PR description mission
Create a comprehensive PR description of the changes that are in the current git branch through systematic research and context curation.

**Critical Understanding**: The executing AI agent only receives:
- Start by reading and understanding the code standards and requirements of this repository by consuming the entire codebase
- For a quick start consume ./README.md and .CLAUDE.md, if they exist
- All content you create
- Its training data knowledge

**Therefore**: Your research and context curation directly determines implementation success. Incomplete context = implementation failure.

## Process
1. First, determine the parent branch:
    - Check if graphite CLI is available by running `which gt`
    - If available, run `gt log` to determine the parent branch from the stack
    - If not available, determine if the user specified a parent branch in $ARGUMENT
    - If you are unclear of which branch to use, prompt the user for more information on the parent branch
   
2. Get the git diff:
    - Run `git diff ${parent_branch}...HEAD` to get all changes
    - Store the full diff in `./tmp/research_docs/ai/current_pr_diff.txt`
    - Generate a summary of changed files with stats and store in `./tmp/research_docs/ai/changed_files_summary.txt`

3. Analyze the changes:
    - Review the diff and identify key changes, features, bug fixes, refactoring, etc.
    - Store analysis in `./tmp/research_docs/ai/pr_analysis.md`
    - You may spawn a subagent to analyze specific complex parts of the diff if needed

4. Read the PR template from `$HOME/.claude/templates/pr.md`

5. Generate the PR description:
    - Use the template structure from the file
    - Fill in all sections based on the git diff analysis
    - Include relevant code snippets or file paths where appropriate
    - Ensure the description is comprehensive and clear
    - Make sure the PR description has a maximum read time of 5 minutes. DO NOT MAKE THE DESCRIPTION TOO LONG.
    - AVOID adding unnecessary and over verbose explanations, follow KISS

6. Output the final PR description to `./tmp/pr/<branch_name>-pr.md`
7. Use the `pbcopy` tool to copy the contents of the generated pr description to the clipboard
    - `cat ./tmp/pr/<branch_name>-pr.md | pbcopy`