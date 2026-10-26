# typescript coding-style

Instruction ID: rule/typescript/coding-style.

## Codex adapter

Follow the wrapper and target AGENTS.md policies first. Interpret Claude/ECC tool and agent names through the currently available native Codex tools; use the configured Windows shell when a procedure says Bash. Slash-command references identify the corresponding harness-workflow skill. Inherit the operator's model choices; Claude model names do not select a Codex model. Never fabricate unavailable tools, reviewers or completion evidence. External actions still require task authorization.

## Upstream instructions

# TypeScript/JavaScript Coding Style

> This file extends [common/coding-style.md](../common/coding-style.md) with TypeScript/JavaScript specific content.

## Immutability

Use spread operator for immutable updates:

```typescript
// WRONG: Mutation
function updateUser(user, name) {
  user.name = name  // MUTATION!
  return user
}

// CORRECT: Immutability
function updateUser(user, name) {
  return {
    ...user,
    name
  }
}
```

## Error Handling

Use async/await with try-catch:

```typescript
try {
  const result = await riskyOperation()
  return result
} catch (error) {
  console.error('Operation failed:', error)
  throw new Error('Detailed user-friendly message')
}
```

## Input Validation

Use Zod for schema-based validation:

```typescript
import { z } from 'zod'

const schema = z.object({
  email: z.string().email(),
  age: z.number().int().min(0).max(150)
})

const validated = schema.parse(input)
```

## Console.log

- No `console.log` statements in production code
- Use proper logging libraries instead
- See hooks for automatic detection
