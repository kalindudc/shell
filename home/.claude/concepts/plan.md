## Plan concept
This plan document is to be used as a structured prompt that supplies an AI coding agent with everything it needs to deliver a vertical slice of working software—no more, no less.

### How is it different from a generic project plan
A traditional plan over-complicates and over details to a point, where context is misinterpreted, making it difficult for any AI agent to effectively implement and repeat in a meaningful and structured way. Instead, a plan keeps the goal and justification sections yet adds three AI-critical layers.

### Context
Precise file paths and content, library versions and library context, code snippets examples. LLMs generate higher-quality code when given direct, in-prompt references instead of broad descriptions. Usage of a ./tmp/docs/ directory to pipe in library and other docs for this plan.

### Implementation Details and Strategy
In contrast of a plan, this concept explicitly states how the a feature will be built. This includes the use of specific Rust crates, libraries, code standard, repo practices / existing patterns, terraform snippets, or agent patterns (ReAct, Plan-and-Execute) to use. Usage of typehints, dependencies, architectural patterns and other tools to ensure the code is built correctly.

### Validation Gates
Deterministic checks such as `dev test unit` / `dev test integration` / `dev style`, with TDD development for quality control will catch defects early and are cheaper than pivoting . Example: Each new addition should be independently tested with unit tests and comprehensively tested with integration tests, Validation gate = all tests pass.

## Rules
- ONLY generate the plan document and DO NOT implement any code change
- DO NOT generate any other documents like PR descriptions