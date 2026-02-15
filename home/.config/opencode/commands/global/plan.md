---
description: Creates a structured plan for implementing a vertical slice of working software
---

YOU MUST READ THE FOLLOWING SECTIONS AND FOLLOW THE INSTRUCTIONS IN THEM.
- Start by reading the plan concept in `$HOME/.config/opencode/concepts/plan.md`
- Next read our plan template structure `$HOME/.config/opencode/templates/plan.md`

Think hard about the above concept

Help the user create a comprehensive Plan document for: $ARGUMENTS

## Instructions for Plan Creation

Research and develop a complete Plan based on the feature/product description above. Follow these guidelines:

## Research Process

Begin with thorough research to gather all necessary context:

1. **Documentation Review**

   - Check for relevant documentation in the `docs/` directories
      - `$HOME/shared/docs/`
      - `$HOME/tmp/docs/`
      - `$HOME/docs/`
      - `**/docs/`
   - Identify any documentation gaps that need to be addressed

2. **Web Research**

   - Use web search to gather additional context
   - Research the concept of the feature/product
   - Look into library documentation
   - Look into sample implementations in https://github.com/GoogleCloudPlatform/service-extensions/tree/main/plugins/samples
   - Look into examples in StackOverflow
   - Look into other example of proxy-wasm usage in github.com
   - etc...

3. **Template Analysis**

   - Use `$HOME/.config/opencode/templates/plan.md` as the structural reference
   - Ensure understanding of the template requirements before proceeding

4. **Codebase Exploration**

   - Identify relevant files and directories that provide implementation context
   - Focus on the relevant plugin and use other plugins as reference or usage patterns
   - Look for patterns that should be followed in the implementation

5. **Implementation Requirements**
   - Confirm implementation details with the user
   - Ask about specific patterns or existing features to mirror
   - Inquire about external dependencies or libraries to consider

## Plan Development

Create a Plan following the template in `$HOME/.config/opencode/templates/plan.md`, ensuring it includes the same structure as the template.

## Context Prioritization

A successful Plan must include comprehensive context through specific references to:

- Files in the codebase
- Web search results and URL's
- Documentation
- External resources
- Example implementations
- Validation criteria

## User Interaction

After completing initial research, present findings to the user and confirm:

- The scope of the Plan
- Patterns to follow
- Implementation approach
- Validation criteria

## Output format

- The plan MUST be created as a markdown file using the structure defined in `$HOME/.config/opencode/templates/plan.md` template and generate a new plan into `./tmp/plan/<feature_name>-plan.md`.
- After creation, inform the user of where to find the plan and provide a brief summary

## Rules and requirements
- NEVER create multiple plans for the same features / task
- ALWAYS use a single plan as the source of truth
- MAINTAINABILITY above all else
- ALWAYS follow KISS (keep it simple stupid), AVOID over engineering

If the user answers with continue, you are on the right path, continue with the Plan creation without user input.

Remember: A Plan is requirement doc + curated codebase intelligence + agent/runbook—the minimum viable packet an AI needs to ship production-ready code on the first pass.
