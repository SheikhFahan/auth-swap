# Security

auth-swap handles login tokens for Claude Code and Codex. This is what it does with them.

## Where your logins are kept

- **Claude Code:** saved logins are macOS keychain items with the service name `auth-swap` (one per saved login). The live login stays where Claude Code keeps it: the `Claude Code-credentials` keychain item and `oauthAccount` in `~/.claude.json`.
- **Codex:** saved logins are files in `~/.auth-swap/codex/` (mode 0600, folder 0700), the same protection Codex gives its own `~/.codex/auth.json`.
- `~/.auth-swap/accounts.json` holds names, emails and plans only, never tokens.

## What auth-swap never does

- It never sends tokens anywhere. It makes no network requests of its own; logins go through Claude's and Codex's own login commands.
- It never prints tokens.
- It never logs out or revokes a login. `auth-swap remove` only forgets the saved copy.

## Reporting a problem

Please don't open a public issue for a security problem. Contact the repository owner privately on GitHub instead.
