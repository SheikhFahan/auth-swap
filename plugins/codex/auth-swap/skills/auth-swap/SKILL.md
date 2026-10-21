---
name: auth-swap
description: "List the user's saved Codex logins and switch the Codex account with the auth-swap CLI. Use when the user invokes $auth-swap, asks to switch Codex account or login, or has hit a usage limit and wants to continue on another saved login."
---

# auth-swap

The user keeps several ChatGPT/Codex logins saved with the `auth-swap` command-line tool at `~/.local/bin/auth-swap`. Switching makes another saved login the active one; this chat continues after Codex reconnects.

## List the saved logins

Run:

```
~/.local/bin/auth-swap list codex
```

Show the output exactly as printed. The `*` marks the login that is active now. If the user did not say which login to switch to, ask them to pick a name from the list.

## Switch to a saved login

When the user names a login, run exactly (replace `<name>`):

```
~/.local/bin/auth-swap use codex <name> --detach
```

This command changes `~/.codex/auth.json` and restarts Codex's background server, which the sandbox does not allow. Request escalated permissions for it (`sandbox_permissions: "require_escalated"`) with the justification "switch the Codex login with auth-swap".

Show its output exactly as printed, then tell the user: this window disconnects for a moment and reconnects on the new login; after that they can send their next message and the chat continues. If the window says the connection could not be restored, they can run `codex resume`.

## Rules

- Never run `codex logout`, `codex login`, or `/logout`. Logging out cancels the active login on the server.
- Never read, print, copy or edit `~/.codex/auth.json` or anything under `~/.auth-swap`. Only run the two commands above.
- If a command fails, show its output and suggest the user run the same command without `--detach` in a terminal: `auth-swap use codex <name>`.
- To add another login, tell the user to run `auth-swap login codex <name>` in a terminal (it opens the browser). Do not run it yourself.
