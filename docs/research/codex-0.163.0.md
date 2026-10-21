# Codex CLI 0.163.0 — auth + daemon internals (verified)

Source: `openai/codex` at tag `rust-v0.163.0`; paths are under `codex-rs/`. Local `codex --version` = `codex-cli 0.163.0`.
Verified 2026-10-21. Re-verify on every Codex update — auth-swap's `doctor` warns when the version differs.

## auth.json
- Path `$CODEX_HOME/auth.json` (default `~/.codex`), mode 0600 on create (`login/src/auth/storage.rs:162-164`, `:225`).
- Store mode `cli_auth_credentials_store`: `file` (default) | `keyring` | `auto` | `ephemeral` (`config/src/types.rs:136-145`). Keyring service `Codex Auth`, account `cli|<sha256(canonical home)[:16]>` (`storage.rs:243-256`). auth-swap v1 supports `file` only.
- Fields (`AuthDotJson`, `storage.rs:49-73`): `auth_mode`, `OPENAI_API_KEY` (always written, `null` when unset), `tokens{id_token, access_token, refresh_token, account_id}`, `last_refresh`, plus `agent_identity`, `personal_access_token`, bedrock fields.
- `tokens.account_id` comes from the id_token claim `chatgpt_account_id` (`login/src/server.rs:856-860`) — a **workspace** id, not a user id.
- id_token claims present on a real ChatGPT login (key names read 2026-10-21): `email`, `name`, `sub`, `https://api.openai.com/auth.{chatgpt_account_id, chatgpt_plan_type, chatgpt_user_id, user_id, organizations[], chatgpt_subscription_active_until, …}`.
- **Write is in place, no temp file, no cross-process lock** (`storage.rs:220-228`: `truncate(true).write(true).create(true)`).
- **Refresh is a read-modify-write of the file on disk** (`login/src/auth/manager.rs:1606-1621`).

## `codex login` / `codex logout`
- Dispatch `cli/src/main.rs:1587-1612`. Browser (default) and `--device-auth` flows first revoke the existing login (`cli/src/login.rs:126-157`, `:338-358`); `--with-api-key` / `--with-access-token` save without revoking.
- **Revoke targets only what is in the current storage, and only ChatGPT-mode tokens**: `revoke.rs:59-61` (no stored auth → return Ok), `revoke.rs:80-81`. Best-effort (`login.rs:140`). URL `https://auth.openai.com/oauth/revoke` (`manager.rs:213`).
  → `CODEX_HOME=<empty temp dir> codex login` has nothing to revoke.
- OAuth: issuer `https://auth.openai.com`, port 1455 (fallback 1457) (`server.rs:77-80`), client `app_EMoamEEZ73f0CkXaXp7hrann` (`manager.rs:1718`).
- `codex logout` revokes what is on disk, then deletes the store (`login.rs:549-555` → `manager.rs:994-1019`).

## AuthManager behaviour
- Caches auth; **does not watch the file**: "External modifications to stored credentials will NOT be observed until reload() is called explicitly." (`manager.rs:2040-2041`).
- Proactive refresh within 5 min of JWT expiry or when `last_refresh` > 8 days (`manager.rs:203-204`, `:3014-3022`).
- Refresh first does an **account-guarded reload**: same account changed on disk → adopt it, skip refresh (`:2867-2869`); different `account_id` → permanent error "you have since logged out or signed in to another account" (`:211`, `:2485-2518`, `:2872-2876`).
- 401 recovery uses the same guarded reload (`:2004-2009`).
- Usage limit = HTTP 429 `usage_limit_reached` → `CodexErr::UsageLimitReached` (`codex-api/src/api_bridge.rs:185-210`); **no auth reload** on that path (`model-provider/src/provider.rs:172-176`).
- `models_cache.json` entries carry an identity hash; mismatch = cache miss (`models-manager/src/manager.rs:757-760`); missing file = miss (`cache.rs:194-196`). No action needed on swap.

## Shared app-server daemon
- Socket `$CODEX_HOME/app-server-control/app-server-control.sock` → symlink into `/tmp/codex-daemon-<uid>/` (`app-server-transport/src/transport/mod.rs:53-70`; `unix_socket.rs:113-116`). Mode 0600, parent 0700 (`unix_socket.rs:31`, `:55-73`). WebSocket over the unix socket; `initialize` handshake required.
- TUI probes the socket (`tui/src/lib.rs:523-558`), auto-starts the daemon (`tui/src/startup_orchestration.rs:311-324`, `:508-578`), falls back to an embedded server (`lib.rs:575-604`).
- One AuthManager shared by every thread (`app-server/src/lib.rs:584-587`). The daemon keeps the environment it was started with (`app-server-daemon/README.md:22-24`).
- Subcommands: `bootstrap, start, restart, update, enable/disable-remote-control, stop, version` (`cli/src/main.rs:652-695`); each prints one JSON object.
- `stop`: SIGTERM, SIGKILL after `shutdownGraceSeconds` (default 60, max 300) (`backend/pid.rs:177-233`; `settings.rs:15-16`). The server drains first — rejects new turns, waits for running turns (`app-server/src/lib.rs:272-304`) — then disconnects all. Loaded thread ids are saved and restored on next start (`daemon_thread_recovery.rs:1-2`).
- Connected TUIs **auto-reconnect** and rejoin threads: delays 0,1,2,4,8 s repeating within 120 s (`tui/src/app/reconnect.rs:1`, `:53-54`); after that "Server connection could not be restored" (`:121`). Embedded sessions can't reconnect (`:40-42`).
- Whether a reconnecting TUI starts a new daemon itself: **not determined**.
- Daemon reloads auth from disk only after login/logout through itself (`app-server/src/request_processors/account_processor.rs:474, 570, 972, 998`) or a fresh start. **Daemon `account/logout` reloads from disk, then revokes what it loaded** (`:998`; `manager.rs:2958-2961`) — after an external swap that revokes the newly swapped-in account.

### Ruled out: `account/login/start {type:"chatgptAuthTokens"}`
`/// [UNSTABLE] FOR OPENAI INTERNAL USE ONLY - DO NOT USE.` (`v2/account.rs:86-88`); kept in a process-global ephemeral store (`storage.rs:544`, `manager.rs:1129-1144`), refresh token stored empty (`manager.rs:1748`), refresh delegated to clients via broadcast `account/chatgptAuthTokens/refresh` with 10 s timeout (`external_auth.rs:18-61`), and while active it blocks ChatGPT/API-key logins (`account_processor.rs:414`, `:446-448`).

## Sandbox (commands the model runs)
- workspace-write roots = configured `writable_roots` + cwd + `/tmp` + `$TMPDIR` (`protocol/src/protocol.rs:1364-1419`); a top-level `.codex` under any root stays read-only (`permissions.rs:2387-2393`). → `~/.codex/auth.json` is not writable from the sandbox.
- The daemon socket dir is denied to sandboxed commands (`seatbelt.rs:1058-1064`; `seatbelt_daemon.rs:11-12`).
- Keychain (`com.apple.SecurityServer`) only allowed with network enabled (`seatbelt_network_policy.sbpl:18-19`).
- Escalation: the model sets `sandbox_permissions: "require_escalated"` + `justification`; approved commands run outside the sandbox (`prompts/templates/permissions/approval_policy/on_request.md:3, 26-30`). User rule `prefix_rule(pattern=["auth-swap"], decision="allow")` in `~/.codex/rules/default.rules` pre-approves.
