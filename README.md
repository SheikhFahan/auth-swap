# auth-swap

Switch Claude Code and Codex between several accounts without logging out. Open chats keep going on the new account.

macOS only. Plain zsh, nothing to install first.

## Install

```sh
git clone git@github.com:SheikhFahan/auth-swap.git
cd auth-swap
zsh install.sh
```

Update: `git pull && zsh install.sh`. Check setup: `auth-swap doctor`.

## Use

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

| Command | |
|---|---|
| `auth-swap login <claude\|codex> <name>` | add an account |
| `auth-swap save <claude\|codex> <name>` | save the account you're logged into now |
| `auth-swap use <claude\|codex> <name>` | switch |
| `auth-swap list` | show saved accounts |
| `auth-swap remove <claude\|codex> <name>` | forget a saved account |
| `auth-swap doctor` | check setup |

## Don't use /logout

Logging out in Claude Code or Codex cancels that login on the server, and auth-swap's saved copy stops working too. Use `auth-swap remove` instead.

## Notes

- `save` is for the account you're already logged into. For a new account use `login`. If your browser is signed in to an account you already saved, open the login link in a private window.
- Needs `/usr/bin/jq` (verified on macOS 26.5; the installer stops if it's missing) and Codex's default file login store. Verified with Claude Code 2.1.305 and Codex 0.163.0; `doctor` warns on other versions.
- Saved logins live in the macOS keychain (Claude) and `~/.auth-swap` (Codex). Nothing is sent anywhere. See [SECURITY.md](SECURITY.md).
- Uninstall: `zsh install.sh --uninstall` (keeps saved logins).
- Tests: `zsh tests/run.zsh`.

## License

[MIT](LICENSE)
