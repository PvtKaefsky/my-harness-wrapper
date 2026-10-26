# Native environment

Native Windows desktop/CLI with PowerShell, Git and Python 3.12 is primary.
The observed development CLI was 0.164.0-alpha.11.1; version alone proves no integration.
Generated hooks use the actual Python executable.
Codex's default Windows command-hook runner uses COMSPEC; generated registrations use its quoting rules.
Every Windows argument is quoted; percent, exclamation, quote and newline characters in hook launch paths are rejected before installation writes.
The hook runner is separate from the user's preferred PowerShell tool/terminal shell.
Source, interactive user, Codex home, target Git context and wrapper state are distinct.
A restricted account is not the interactive user's install destination.
Normal tasks do not install or repair the harness.

Credentials, network and sandbox policy remain with Codex and the user.
The wrapper does not request full access, change trust or rewrite Git settings.
Isolated imports never search target directories.
Harness module loaders compile source directly and never execute timestamp caches or sourceless bytecode.

Windows checks require the current user or the active token's Administrators default owner and reject write grants to other principals.
An Administrators owner is accepted only when it equals the current token's default owner; other users remain invalid owners.
Directory deletion authority is treated as a write grant.
Installation records existing trusted roots for state, profile and Codex home and checks the complete descendant chains on later operations.
The profile is an explicit operator boundary; custom state/home roots anchor at their nearest existing parent on first installation.
Ancestors outside those recorded roots remain operator trust assumptions.
System, Administrators and Windows Owner Rights are trusted owner/system entries.
Existing unsafe directories are preserved and reported; tests secure only newly created fixture roots.
Disposable Windows fixtures assign the current token user as owner, including elevated runners.
See [Microsoft SID definitions](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/understand-security-identifiers).
Windows assigns new objects their [token's default owner](https://learn.microsoft.com/en-us/windows/win32/secauthz/owner-of-a-new-object).
