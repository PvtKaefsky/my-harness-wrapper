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
Operator-approved preparation may create only the user-scope `harness-python-patterns` discovery pointer under [the native delivery contract](native-skills.md).
A denied or unsafe pointer stops native provisioning without a target-local or managed-configuration fallback.

Commit operations require the existing explicit author/committer environment identity.
Forge assignment uses `HARNESS_ASSIGNEE` when present.
The wrapper does not modify personal Git identity or signing configuration.
Network access and credentials follow the managed provider policy.
Delivery setup is offline; maintenance fetches and forge actions use existing approved access.
