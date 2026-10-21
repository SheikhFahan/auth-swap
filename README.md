# auth-swap

Keep several Claude Code and Codex logins on one Mac and switch between them **without logging out**, so when one account hits its usage limit you carry on in the **same chat** with another.

- One `~/.claude` and one `~/.codex`: your chats stay in one place, so `--continue` / `resume` keep working across accounts.
- `/auth-swap` inside Claude Code; `$auth-swap:auth-swap` inside Codex; `auth-swap` in any terminal.
- Switching is always manual. auth-swap never switches on its own.
- Written in zsh with only tools that ship with macOS (`security`, `jq`, `shasum`, …). Nothing to install first.

## Requirements

- macOS with `/usr/bin/jq` (verified on macOS 26.5.2; the installer stops if it is missing).
- Claude Code (verified with 2.1.305; `/auth-swap` needs 2.1.287 or later) and/or Codex CLI (verified with 0.163.0). `auth-swap doctor` warns when your versions differ.
- Codex must use its default file login store (`cli_auth_credentials_store` unset or `"file"`).

## Install

```sh
git clone git@github.com:SheikhFahan/auth-swap.git
cd auth-swap
zsh install.sh
```

The repository is private: you need access to it and GitHub set up on your Mac (an SSH key, or `gh auth login` and then `gh repo clone SheikhFahan/auth-swap`). On a fresh Mac, `git` asks to install the Xcode Command Line Tools first; auth-swap itself doesn't need them.

To update later: `git pull` in that folder, then `zsh install.sh` again (your saved logins are kept).

This copies auth-swap to `~/.auth-swap/app`, links `~/.local/bin/auth-swap`, and installs the Claude Code plugin and the Codex plugin from local marketplaces. Run `auth-swap doctor` to check everything.

## First use

```sh
auth-swap save claude max          # the Claude login you're using now
auth-swap login claude work        # another account: opens the normal Claude login page
auth-swap save codex personal      # the Codex login you're using now
auth-swap login codex team         # another account: opens the normal ChatGPT login page
auth-swap list
```

`login` runs Claude's or Codex's own login into a throwaway temp folder, saves the result, and deletes the folder. Your current login and open chats are not touched.

## Switch

| Where | Claude Code | Codex |
|---|---|---|
| Inside the app | `/auth-swap work` (no args lists logins) | `$auth-swap:auth-swap`, then name the login |
| Terminal | `auth-swap use claude work` | `auth-swap use codex team` |

- **Claude Code:** open chats switch on their next message, sent at least 30 seconds after their last request. The chat itself continues. `/auth-swap codex team` also switches Codex from inside Claude Code.
- **Codex:** auth-swap restarts Codex's shared background server. Open Codex windows disconnect for a moment and reconnect on the new login (within about 2 minutes). If a window says the connection could not be restored, run `codex resume`. From inside Codex the skill asks your permission to run, because the switch changes files outside the sandbox.

Before every switch auth-swap saves the current account's latest tokens back to its vault. Tokens change every time they refresh, so this step is needed.

## Never use /logout

Logging out in Claude Code or Codex cancels that login on the server, and the copy auth-swap saved stops working too. In Codex, a logout right after a switch cancels the account you just switched **to**. To stop using a saved login, run `auth-swap remove claude|codex <name>`. That only forgets it and never cancels anything.

## How it works

| | Claude Code | Codex |
|---|---|---|
| Live login | Keychain item `Claude Code-credentials` + `oauthAccount` in `~/.claude.json` | `~/.codex/auth.json` |
| Saved logins | Keychain items named `auth-swap` | `~/.auth-swap/codex/<name>.auth.json` (0600) |
| Switch | Takes Claude's own lock files and rewrites the login fields Claude's own login writes. Other keychain data (e.g. MCP logins) and settings are kept; per-account caches are cleared exactly as Claude's login clears them. | Stops the shared daemon (`codex app-server daemon stop`), swaps `auth.json`, starts it again. |

`~/.auth-swap/accounts.json` lists names, emails and plans only, with no tokens. Every rule above was checked against the Claude Code binary and the Codex source. The notes and citations are in [`docs/research/`](docs/research/).

## Limits

- One active account per tool at a time, shared by every open chat of that tool.
- A Codex window running without the shared daemon (`--no-daemon`) can't be switched. Restart it after switching.
- A Codex daemon started by auth-swap keeps the environment of whatever started it, so prefer switching Codex from a terminal or from Codex itself.
- Saved logins that go unused for a long time may expire on the server; run `auth-swap login` again. `auth-swap list` shows the refresh-expiry date Claude recorded for each Claude login.
- Some behaviour is still being confirmed on real accounts; see [`docs/research/spikes.md`](docs/research/spikes.md).

## Uninstall

```sh
zsh install.sh --uninstall
```

Your saved logins stay; remove them first with `auth-swap remove` if you want them gone.

## Development

```sh
zsh tests/run.zsh                          # CLI tests: fake HOME, fake keychain, fake claude/codex
claude plugin validate plugins/claude/auth-swap
claude plugin test plugins/claude/auth-swap
```
