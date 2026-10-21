# Changelog

All notable changes to auth-swap are listed here. Versions follow [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-10-21

First release.

### Added
- `auth-swap` CLI (zsh, macOS built-in tools only): `login`, `save`, `use`, `list`, `remove`, `doctor`, `version`.
- `login claude|codex <name>` runs Claude's or Codex's own login into a throwaway temp folder and saves the result; the live login is never touched.
- `use claude <name>` swaps the Claude Code login in the keychain and `~/.claude.json` under Claude's own lock files; open chats switch on their next message.
- `use codex <name>` stops Codex's shared daemon, swaps `~/.codex/auth.json` and starts it again; open Codex windows reconnect. `--detach` runs the switch in the background (used from inside Codex).
- Every switch first saves the current account's latest tokens back to the vault.
- Claude Code plugin with a `/auth-swap` command (runs without starting a Claude turn, so it works when an account is out of usage).
- Codex plugin with an `$auth-swap:auth-swap` skill.
- `install.sh` (install, update, `--uninstall`) that links `~/.local/bin/auth-swap` and installs both plugins from local marketplaces.
- Test suite with a fake keychain and fake `claude`/`codex`; research notes with citations in `docs/research/`.

### Verified on real accounts (macOS 26.5.2, Claude Code 2.1.305, Codex 0.163.0)
- Keychain read/write, including long and non-ASCII values.
- Claude and Codex temp-folder logins leave the live login untouched.
- Codex switch from a terminal: open window reconnects on the new account; switching back works.

### Not yet confirmed
- An open Claude Code chat showing the new account in `/status` after a switch.
- Switching Codex from inside a Codex chat through the skill.

[0.1.0]: https://github.com/SheikhFahan/auth-swap/releases/tag/v0.1.0
