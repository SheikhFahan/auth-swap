```text
╭───╮╭───╮╭───╮╭───╮╭───╮╭───╮╭───╮╭───╮╭───╮
│ a ││ u ││ t ││ h ││ - ││ s ││ w ││ a ││ p │
╰───╯╰───╯╰───╯╰───╯╰───╯╰───╯╰───╯╰───╯╰───╯
```

**one Mac · many accounts · zero logouts**

Switch Claude Code and Codex between several accounts without logging out. Open chats keep going on the new account.

```text
  personal  ▕██████████▏ 100%   rate-limited. mid-thought. classic.
  work      ▕░░░░░░░░░░▏   0%

  $ auth-swap use claude work

  personal  ▕██████████▏ 100%   resting
  work      ▕█░░░░░░░░░▏  10%   ◀ you are here. same chat.
```

macOS only. Plain zsh, nothing to install first.

## 01 · install

```sh
git clone git@github.com:SheikhFahan/auth-swap.git
cd auth-swap
zsh install.sh
```

Update: `git pull && zsh install.sh`. Check setup: `auth-swap doctor`.

## 02 · use

Save the account you're logged into now, then add others (opens the browser):

```console
$ auth-swap save claude personal
Saved the active Claude login as 'personal' (me@example.com).

$ auth-swap login claude work
Opening the Claude login for 'work'. Your current login and open chats are not touched.
...
Saved Claude login 'work' (me@work.example.com). Switch with: auth-swap use claude work
```

List and switch:

```console
$ auth-swap list
PROVIDER NAME             EMAIL                            PLAN       ACTIVE
claude  personal         me@example.com                   max        *
        refresh expiry (as recorded by Claude): 2026-11-17 16:32Z
claude  work             me@work.example.com              max
        refresh expiry (as recorded by Claude): 2026-11-20 09:05Z

Saved logins that sit unused may expire on the server; if a switch stops working, run auth-swap login again.

$ auth-swap use claude work
Claude → work (me@work.example.com). Open chats switch on their next message sent at least 30 s after their last request.
```

Codex works the same way: replace `claude` with `codex`. After a Codex switch, open Codex windows reconnect within about 2 minutes. If one can't, run `codex resume`.

## 03 · commands

| Command | |
|---|---|
| `auth-swap login <claude\|codex> <name>` | add an account |
| `auth-swap save <claude\|codex> <name>` | save the account you're logged into now |
| `auth-swap use <claude\|codex> <name>` | switch |
| `auth-swap list` | show saved accounts |
| `auth-swap remove <claude\|codex> <name>` | forget a saved account |
| `auth-swap doctor` | check setup |

## 04 · how it works

```text
  saved logins
  ┌──────────┐
  │ personal │─┐
  │ work     │─┼── auth-swap use ──▶ live login (every chat reads it)
  │ team     │─┘
  └──────────┘
        ▲
        └── the account you leave gets saved back first
```

Saved logins live in the macOS keychain (Claude) and `~/.auth-swap` (Codex). Nothing is sent anywhere. See [SECURITY.md](SECURITY.md).

## !! · don't /logout

```text
  ╔════════════════════════════════════════════════════╗
  ║ !! DON'T /logout                                   ║
  ║                                                    ║
  ║ it cancels the login on the server, and the        ║
  ║ copy auth-swap saved goes down with it.            ║
  ║                                                    ║
  ║ to forget an account:  auth-swap remove            ║
  ╚════════════════════════════════════════════════════╝
```

## ?? · notes

- `save` is for the account you're already logged into. For a new account use `login`. If your browser is signed in to an account you already saved, open the login link in a private window.
- Needs `/usr/bin/jq` (verified on macOS 26.5; the installer stops if it's missing) and Codex's default file login store. Verified with Claude Code 2.1.305 and Codex 0.163.0; `doctor` warns on other versions.
- Uninstall: `zsh install.sh --uninstall` (keeps saved logins).
- Tests: `zsh tests/run.zsh`.

---

<sub>[MIT](LICENSE) · no tokens were revoked in the making of this switch.</sub>
