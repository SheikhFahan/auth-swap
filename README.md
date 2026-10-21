# auth-swap

**Switch Claude Code and Codex between several logged-in accounts without logging out, and keep working in the same chat.**

![version](https://img.shields.io/badge/version-0.1.0-blue)
![platform](https://img.shields.io/badge/platform-macOS-lightgrey)
![shell](https://img.shields.io/badge/shell-zsh-green)
![license](https://img.shields.io/badge/license-MIT-yellow)

When one account hits its usage limit, run `auth-swap use claude work` in a terminal and carry on in the same conversation on another account. No logout, no new login, no second config folder.

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Switching accounts](#switching-accounts)
- [Command reference](#command-reference)
- [Troubleshooting](#troubleshooting)
- [How it works](#how-it-works)
- [Limitations](#limitations)
- [Uninstall](#uninstall)
- [Development](#development)
- [Security](#security) · [License](#license)

## Features

- **Same chat, different account.** One `~/.claude` and one `~/.codex`, so your chats, `--continue` and `codex resume` work across every account.
- **Native logins.** `auth-swap login` runs Claude's and Codex's own login in a throwaway folder. Your current login and open chats are never touched.
- **Works when you're out of usage.** Switching runs in your terminal, outside Claude Code and Codex, so it never needs the account that ran out.
- **Never loses tokens.** Before every switch, the current account's latest tokens are saved back.
- **Manual only.** auth-swap never switches on its own.
- **Nothing to install first.** Plain zsh using only tools that ship with macOS (`security`, `jq`, `shasum`, …).

## Requirements

| | Version |
|---|---|
| macOS | with `/usr/bin/jq` (verified on 26.5.2; the installer stops if it's missing) |
| Claude Code | verified with 2.1.305 |
| Codex CLI | verified with 0.163.0; must use the default file login store (`cli_auth_credentials_store` unset or `"file"`) |

You can use auth-swap with Claude Code only, Codex only, or both. `auth-swap doctor` warns when your versions differ from the verified ones.

## Installation

The repository is private: you need access to it and GitHub set up on your Mac.

**With git**

```sh
git clone git@github.com:SheikhFahan/auth-swap.git
cd auth-swap
zsh install.sh
```

On a fresh Mac, `git` first asks to install the Xcode Command Line Tools. auth-swap itself doesn't need them.

**Without git:** download the source archive of the latest release from the [Releases](https://github.com/SheikhFahan/auth-swap/releases) page, then:

```sh
cd ~/Downloads
tar xzf auth-swap-*.tar.gz
cd auth-swap-*/
zsh install.sh
```

The installer copies auth-swap to `~/.auth-swap/app` and links `~/.local/bin/auth-swap`. If `~/.local/bin` isn't on your `PATH`, it tells you.

Check the setup:

```console
$ auth-swap doctor
auth-swap 0.1.0 on macOS 26.5.2
  ok    /usr/bin/jq
  ...
  ok    /Users/you/.local/bin/auth-swap
Ready.
```

**Update:** `git pull` (or download the newer release), then run `zsh install.sh` again. Your saved logins are kept. See [CHANGELOG.md](CHANGELOG.md).

## Quick start

**1. Save the accounts you're logged into now.** You do this once per tool, because auth-swap can only switch back to accounts it has a copy of.

```console
$ auth-swap save claude personal
Saved the active Claude login as 'personal' (me@example.com).

$ auth-swap save codex personal
Saved the active Codex login as 'personal' (me@example.com).
```

**2. Add your other accounts.** This opens the normal Claude or ChatGPT sign-in page. Sign in with the *other* account.

```console
$ auth-swap login claude work
Opening the Claude login for 'work'. Your current login and open chats are not touched.
Opening browser to sign in…
If the browser didn't open, visit: https://claude.com/cai/oauth/authorize?…
Login successful.
Saved Claude login 'work' (me@work.example.com). Switch with: auth-swap use claude work

$ auth-swap login codex team
Opening the Codex login for 'team'. Your current login and open chats are not touched.
Starting local login server on http://localhost:1455.
If your browser did not open, navigate to this URL to authenticate:
https://auth.openai.com/oauth/authorize?…
Successfully logged in
Saved Codex login 'team' (me@work.example.com). Switch with: auth-swap use codex team
```

> [!TIP]
> Sign in with an account you haven't saved yet; signing in to a saved one again is refused as a duplicate. If your browser is still signed in to the saved account, open the printed link in a private window or another browser profile.

**3. See what you have.** `*` marks the active account.

```console
$ auth-swap list
PROVIDER NAME             EMAIL                            PLAN       ACTIVE
claude  personal         me@example.com                   max        *
        refresh expiry (as recorded by Claude): 2026-11-17 16:32Z
claude  work             me@work.example.com              max
        refresh expiry (as recorded by Claude): 2026-11-20 09:05Z
codex   personal         me@example.com                   plus       *
codex   team             me@work.example.com              pro
```

**4. Switch.**

```console
$ auth-swap use claude work
Claude → work (me@work.example.com). Open chats switch on their next message sent at least 30 s after their last request.

$ auth-swap use codex team
Codex → team (me@work.example.com). Open Codex windows reconnect within ~2 min; if one says the connection could not be restored, run: codex resume
```

> [!WARNING]
> **Never use `/logout` in Claude Code or Codex.** Logging out cancels that login on the server, so the copy auth-swap saved stops working too. In Codex, a logout right after a switch cancels the account you just switched *to*. To forget a saved login, use `auth-swap remove`; it never cancels anything.

## Switching accounts

Run switches from any terminal window:

```sh
auth-swap use claude work    # Claude Code
auth-swap use codex team     # Codex
auth-swap list               # what is saved, and what is active
```

**Claude Code:** every open chat moves to the new account with its next message, once 30 seconds have passed since its last request. The conversation simply continues.

**Codex:** auth-swap restarts Codex's shared background server. Open Codex windows disconnect briefly and reconnect on the new account, within about 2 minutes. Run Codex switches from a terminal rather than asking Codex to run them: a switch first waits for running Codex replies to finish, including the one that would be running the command.

## Command reference

| Command | What it does |
|---|---|
| `auth-swap login <claude\|codex> <name> [-- flags]` | Sign in to another account in the browser and save it as `<name>`. Flags after `--` go to the native login (Claude: `--claudeai`, `--console`, `--sso`, `--email`; Codex: `--device-auth`). |
| `auth-swap save <claude\|codex> <name>` | Save the account that is active right now. |
| `auth-swap use <claude\|codex> <name>` | Switch to a saved account. Saves the current one's latest tokens first. |
| `auth-swap list [claude\|codex] [--json]` | Show saved accounts. |
| `auth-swap remove <claude\|codex> <name>` | Forget a saved account. Never logs it out. |
| `auth-swap doctor` | Check tools, versions and environment. |
| `auth-swap help`, `auth-swap version` | Show usage or the version. |

`use --no-save` switches even though the active account isn't saved. That account is dropped locally (not logged out).

Names may contain letters, digits, `.`, `_` and `-`.

## Troubleshooting

**`this … account is already saved as '<name>'` when running `save`**

`save` stores the account you're logged into *now*, and that one is already saved. To add a different account, use `login`:

```console
$ auth-swap save claude work
auth-swap: the Claude account you're logged into now (me@example.com) is already saved as 'personal'.
'save' stores the account that is active right now. To add a different account, run: auth-swap login claude work
```

**`isn't saved yet` when running `use`.** The active account isn't in auth-swap, and switching away would drop it. Run `auth-swap save <claude|codex> <name>` first, or add `--no-save` if you don't need it.

**`claude auth login did not finish` / `codex login did not finish`.** The sign-in was closed or didn't complete. Nothing was saved or changed; run the same command again.

**`Claude Code is busy refreshing its login`.** Claude Code is renewing its tokens at that moment. Try again in a few seconds.

**A Codex window says the connection could not be restored.** Run `codex resume` to reopen the chat on the new account.

**`doctor` reports `BLOCK … is set`.** auth-swap manages only the default `~/.claude` and `~/.codex`. Unset `CLAUDE_CONFIG_DIR`, `CLAUDE_SECURESTORAGE_CONFIG_DIR`, `CLAUDE_CODE_OAUTH_TOKEN` or `CODEX_HOME` in the shell you use.

## How it works

| | Claude Code | Codex |
|---|---|---|
| Live login | Keychain item `Claude Code-credentials` + `oauthAccount` in `~/.claude.json` | `~/.codex/auth.json` |
| Saved logins | Keychain items with service `auth-swap` | `~/.auth-swap/codex/<name>.auth.json` (mode 0600) |
| Switch | Takes Claude Code's own lock files and rewrites only the login fields its own login writes. Other keychain data (such as MCP logins) and settings are kept; per-account caches are cleared the way Claude's login clears them. | Stops the shared daemon (`codex app-server daemon stop`), swaps `auth.json`, starts it again. |

`~/.auth-swap/accounts.json` lists names, emails and plans only, with no tokens. Every rule above was checked against the Claude Code binary and the Codex source. The notes and citations are in [`docs/research/`](docs/research/).

## Limitations

- One active account per tool at a time, shared by all open chats of that tool.
- A Codex window running without the shared daemon (`--no-daemon`) can't be switched. Restart it after switching.
- The Codex daemon that auth-swap restarts keeps the environment of the shell you ran `auth-swap` from (PATH, proxy settings and so on).
- Saved logins left unused for a long time may expire on the server. If a switch stops working, run `auth-swap login` again. `list` shows the refresh-expiry date Claude recorded.
- Some behaviour is still being confirmed on real accounts; see [`docs/research/spikes.md`](docs/research/spikes.md).

## Uninstall

```sh
zsh install.sh --uninstall
```

This removes the command. Your saved logins stay; run `auth-swap remove` for each one first if you want them gone.

## Development

```sh
zsh tests/run.zsh    # fake HOME, fake keychain, fake claude/codex
```

The tests never touch your real keychain, `~/.claude` or `~/.codex`.

| Path | Contents |
|---|---|
| `bin/auth-swap` | CLI entry point |
| `lib/` | shared helpers, vault, Claude and Codex flows |
| `tests/` | test runner, stubs for `security`, `claude` and `codex` |
| `docs/research/` | verified behaviour of Claude Code and Codex, with citations |

Issues and pull requests are welcome. Please run the tests before opening a pull request.

## Security

How auth-swap stores your logins, and how to report a problem: [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) © 2026 SheikhFahan
