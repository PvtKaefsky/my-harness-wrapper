# golang security

Instruction ID: rule/golang/security.

## Codex adapter

Follow the wrapper and target AGENTS.md policies first. Interpret Claude/ECC tool and agent names through the currently available native Codex tools; use the configured Windows shell when a procedure says Bash. Slash-command references identify the corresponding harness-workflow skill. Inherit the operator's model choices; Claude model names do not select a Codex model. Never fabricate unavailable tools, reviewers or completion evidence. External actions still require task authorization.

## Upstream instructions

# Go Security

> This file extends [common/security.md](../common/security.md) with Go specific content.

## Secret Management

```go
apiKey := os.Getenv("OPENAI_API_KEY")
if apiKey == "" {
    log.Fatal("OPENAI_API_KEY not configured")
}
```

## Security Scanning

- Use **gosec** for static security analysis:
  ```bash
  gosec ./...
  ```

## Context & Timeouts

Always use `context.Context` for timeout control:

```go
ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
defer cancel()
```
