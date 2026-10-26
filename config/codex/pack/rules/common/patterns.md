# common patterns

Instruction ID: rule/common/patterns.

## Codex adapter

Follow the wrapper and target AGENTS.md policies first. Interpret Claude/ECC tool and agent names through the currently available native Codex tools; use the configured Windows shell when a procedure says Bash. Slash-command references identify the corresponding harness-workflow skill. Inherit the operator's model choices; Claude model names do not select a Codex model. Never fabricate unavailable tools, reviewers or completion evidence. External actions still require task authorization.

## Upstream instructions

# Common Patterns

## Skeleton Projects

When implementing new functionality:
1. Search for battle-tested skeleton projects
2. Use parallel agents to evaluate options:
   - Security assessment
   - Extensibility analysis
   - Relevance scoring
   - Implementation planning
3. Clone best match as foundation
4. Iterate within proven structure

## Design Patterns

### Repository Pattern

Encapsulate data access behind a consistent interface:
- Define standard operations: findAll, findById, create, update, delete
- Concrete implementations handle storage details (database, API, file, etc.)
- Business logic depends on the abstract interface, not the storage mechanism
- Enables easy swapping of data sources and simplifies testing with mocks

### API Response Format

Use a consistent envelope for all API responses:
- Include a success/status indicator
- Include the data payload (nullable on error)
- Include an error message field (nullable on success)
- Include metadata for paginated responses (total, page, limit)
