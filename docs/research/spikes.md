# Spikes — empirical checks on a real machine

Machine: macOS 26.5.2 (25F84), Claude Code 2.1.305, Codex 0.163.0.

| Id | What | Status |
|---|---|---|
| S1 | `CLAUDE_CONFIG_DIR=<tmp> claude auth login` writes only the temp keychain item + temp `.claude.json`; live login untouched | **passed 2026-10-21** |
| S2 | Running Claude chat picks up a swapped keychain login on its next message after ≥30 s, with no re-login prompt, same transcript | pending |
| S3 | `CODEX_HOME=<tmp> codex login` writes only `<tmp>/auth.json`; live `~/.codex/auth.json` untouched | **passed 2026-10-21** |
| S4 | `auth-swap use codex B` from a terminal: open TUI reconnects, `/status` shows B, next turn served | **passed 2026-10-21** |
| S5 | Codex skill runs `auth-swap use codex B --detach` (escalated) in-chat and the switch completes | dropped (plugins removed) |
| S6 | Keychain write/read via `security` | **passed 2026-10-21** |

## S6 — keychain I/O (passed)
Test service `auth-swap-test`, account `$USER`; deleted afterwards (find → exit 44).
- (a) `add-generic-password -U -a … -s … -X <hex>` piped to `security -i`, full command 3858 chars → exit 0, read back byte-for-byte (1896 bytes).
- (b) same via argv with 8992 hex chars → exit 0, read back byte-for-byte (4496 bytes).
- (info) stdin with a 6058-char command → `security: unknown command "<rest of hex>"`, exit 1, **and a truncated value (2015 bytes) was stored**. `security -i` splits long lines, so a too-long stdin command silently writes partial data. Rule: stdin only when the full command is ≤ 4032 chars (Claude's own limit), else argv.

## S6b — non-ASCII values (passed, 2026-10-21)
- Stored `{"v":"Zoë Ångström ü"}` as raw UTF-8 → `find-generic-password -w` printed it as **hex** (`7b2276223a225a6fc3ab…`), not text.
- Stored the same JSON ASCII-escaped (`jq -ac`, `Zoë …`) → read back byte-for-byte.
- Consequences in auth-swap: every JSON it writes to the keychain is ASCII-escaped (`jq -a`), and `as_kc_read` decodes a pure-hex answer back to bytes (a JSON object never looks like hex). The test stub mimics the hex behaviour.

## S3 — Codex temp login (passed, 2026-10-21)
Run by the user: `auth-swap save codex main` (08:00:35Z), then `auth-swap login codex second` (08:01:38Z, second ChatGPT account in the browser).
- Vault entry `second`: `auth_mode` = `chatgpt`, refresh token present, identity differs from `main`.
- Live `~/.codex/auth.json`: sha256 prefix `346e86eeff2d9414` before (06:46Z) and after (08:02Z); mtime unchanged.
- No `auth-swap.*` temp folder left in `$TMPDIR` or `/tmp`. The daemon kept running on 0.163.0.
- Claude side in the same window: live `Claude Code-credentials` mdat, blob hash and `oauthAccount` hash unchanged; still 4 `Claude Code-credentials*` items (the 3 pre-existing suffixed ones + the live one).

## S4 — Codex switch from a terminal (passed, 2026-10-21)
Run by the user with a Codex window open: `auth-swap use codex second`, then `auth-swap use codex main`. User report: "the codex swap worked flawlessly" (window reconnected on the new account, turns served, switch back worked).
- Save-back on each switch: vault `updatedAt` for `main` 08:21:45Z (saved when leaving it) and `second` 08:22:21Z (saved when switching back).
- Switching back to `main` worked, so leaving an account does not revoke it.
- Daemon running on 0.163.0 afterwards.

## S1 — Claude temp login (passed, 2026-10-21)
Run by the user: `auth-swap login claude second` (12:19:39Z, a second Claude Max account in the browser), then `auth-swap use claude second` (12:21:11Z).
- The login printed "Login successful." and saved `second` with its own email and refresh expiry.
- The live login was still `main` after it: `use` found the live account, matched it to `main` and saved it back (`main` updatedAt 12:21:11Z) instead of refusing it as unsaved.
- Still 4 `Claude Code-credentials*` items afterwards (the temp item was deleted) and no `auth-swap.*` temp folder left. An earlier attempt that ended with "claude auth login did not finish" also left nothing behind.

## S2 — not yet confirmed
After the switch above, the Claude Code chat that was already open kept answering in the same transcript. Still to confirm: `/status` in that chat shows the new account.
