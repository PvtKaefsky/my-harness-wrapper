# Managed Cloud environment

The supported runtime is managed Codex Cloud.
The wrapper checkout convention is `/workspace/my-harness-wrapper`.
The delivery-state convention is `/workspace/.harness-wrapper`.
Other attached repositories remain independent task repositories.
Setup never creates discovery directories or symlinks in those repositories.

Setup requires Bash, Git, jq, Python 3.9 or newer and GNU/Linux utilities including `flock`, `realpath`, `sha256sum`, `cmp` and `mv -T`.
Workflow execution also requires the project-specific tools named in its catalog entry.
Unavailable compilers, browsers, services or connected tools are reported per workflow step.
Read-only planning and code inspection need no external workflow service.

The current-task provider exposes native agent collaboration and connected GitHub tools.
Their actual invocation is separate from pack delivery.
No fork-provided MCP, native skill dispatch or automatic shell-hook registration is established by this repository.
The runtime's managed home and configuration remain provider-owned.
Default setup writes no home or managed configuration and requests no elevated privileges.
The operator-reported preparation cannot create `$HOME/.agents`: `OSError(30): Read-only file system`.
The historical HOME provisioner remains disabled by default and inapplicable to that runtime.
The [repository-scoped experiment](native-skills.md) versions `harness-python-patterns` under the wrapper's `.agents/skills/`.
It requires the wrapper as the provider-selected working repository, with a separate attached target used read-only.
A shell `cd` and sibling checkout presence do not establish that provider selection.
User-global and target-rooted discovery remain unproven.

Commit operations require the existing explicit author/committer environment identity.
Forge assignment uses `HARNESS_ASSIGNEE` when present.
The wrapper does not modify personal Git identity or signing configuration.
Network access and credentials follow the managed provider policy.
Delivery setup is offline; maintenance fetches and forge actions use existing approved access.
