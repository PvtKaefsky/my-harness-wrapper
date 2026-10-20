# Shared Cloud workflow catalog

Use: apply workflow NAME from the shared Codex pack. These are explicit instruction reads, not native selectors or slash commands.

Run `python3 -I /workspace/my-harness-wrapper/scripts/pack-codex.py read ID` to verify and read one entry and its linked brief. Read project policy first. No setup writes to target repositories.

| Intent | ID | Exact wrapper path | Requirements |
| --- | --- | --- | --- |
| Plan / architecture | `workflow/plan` | `/workspace/my-harness-wrapper/config/codex/cloud-pack/workflows/plan.md` | requirements of role/planner |
| Implement / TDD | `workflow/tdd` | `/workspace/my-harness-wrapper/config/codex/cloud-pack/workflows/tdd.md` | requirements of skill/tdd-workflow |
| Debug build | `workflow/build-fix` | `/workspace/my-harness-wrapper/config/codex/cloud-pack/workflows/build-fix.md` | requirements of role/build-error-resolver |
| Review | `workflow/code-review` | `/workspace/my-harness-wrapper/config/codex/cloud-pack/workflows/code-review.md` | requirements of role/code-reviewer |
| Security | `skill/security-review` | `/workspace/my-harness-wrapper/config/codex/cloud-pack/skills/security-review/SKILL.md` | repository read/diff tools; optional installed scanners |
| Verify completion | `workflow/verify` | `/workspace/my-harness-wrapper/config/codex/cloud-pack/workflows/verify.md` | requirements of skill/verification-loop |
| Python | `skill/python-patterns` | `/workspace/my-harness-wrapper/config/codex/cloud-pack/skills/python-patterns/SKILL.md` | Python and repository checks |
| Go | `skill/golang-patterns` | `/workspace/my-harness-wrapper/config/codex/cloud-pack/skills/golang-patterns/SKILL.md` | Go toolchain and project build/tests |
| TypeScript | `skill/coding-standards` | `/workspace/my-harness-wrapper/config/codex/cloud-pack/skills/coding-standards/SKILL.md` | Node.js and project type/lint/test commands |
| Database | `skill/database-migrations` | `/workspace/my-harness-wrapper/config/codex/cloud-pack/skills/database-migrations/SKILL.md` | project migration runner and isolated test database |

The full lazy inventory (skills, roles, rules and explicit workflows) is `catalog.json`. Before committing, obtain real independent native reviews of the exact staged tree and use `commit-codex.sh`. Briefs alone do not satisfy that gate. Report selected ID, output, checks and capability limits at completion.
