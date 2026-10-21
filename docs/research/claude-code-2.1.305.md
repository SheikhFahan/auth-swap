# Claude Code 2.1.305 — auth internals (verified)

Source: the installed binary `~/.local/share/claude/versions/2.1.305` (Bun-compiled, build `2026-10-20T18:04:27Z`).
Citations are byte offsets (`@N`) into that file. The JS lives between ~215.8 MB and ~262 MB as ~2,500 `// @bun @bytecode` chunks; minified names collide across chunks, so search by the quoted string literals.
Verified 2026-10-21. Re-verify on every Claude Code update — auth-swap's `doctor` warns when the version differs.

## Where the login lives (macOS)

| What | Where | Cite |
|---|---|---|
| OAuth tokens | Keychain generic password, service `Claude Code-credentials`, account `$USER` | @218702291, @218702586 |
| Account profile | `oauthAccount` in `~/.claude.json` | @216362680, @219145124 |
| Plaintext fallback | `~/.claude/.credentials.json` (0600), only when a keychain write fails non-transiently | @218707147, @218707590, @218712141 |

### Keychain service name — `RB()` @218702291
```
function RB(e=""){let n=process.env.CLAUDE_SECURESTORAGE_CONFIG_DIR,t=n!==void 0?!n:!process.env.CLAUDE_CONFIG_DIR,
r=n!==void 0?n.normalize("NFC"):Me(),a=t?"":`-${c("sha256").update(r).digest("hex").substring(0,8)}`;
return`Claude Code${cn().OAUTH_FILE_SUFFIX}${e}${a}`}
```
- `TTe="-credentials"` @218702096; `OAUTH_FILE_SUFFIX:""` in prod @216311943.
- `Me()` @216035428 = `(CLAUDE_CONFIG_DIR ?? ~/.claude).normalize("NFC")`.
- Suffix `-<sha256[:8]>` is added only if `CLAUDE_SECURESTORAGE_CONFIG_DIR` is non-empty (hash of it) or else `CLAUDE_CONFIG_DIR` is set (hash of `Me()`).
- Account `yP()` @218702586: `process.env.USER || os.userInfo().username`; falls back to `claude-code-user` if that throws or fails `/^[a-zA-Z0-9._-]+$/`.
- A second item named plain `Claude Code` (+ suffix) holds a console API key; login and logout delete it (@219152220).

### Keychain I/O
- Read (sync) @218708881: `security find-generic-password -a "<acct>" -w -s "<svc>"`, 2000 ms timeout. Async @218711211. Exit 44 = not found, 36 = locked / interaction needed.
- Write @218710154: `add-generic-password -U -a "<acct>" -s "<svc>" -X "<hex of UTF-8 JSON>"\n` piped to `security -i` **when the whole command string is ≤ 4032 chars** (`ne=4032` @218708649); otherwise argv `security add-generic-password -U -a <acct> -s <svc> -X <hex>` @218710431.
- Delete @218710934: `security delete-generic-password -a <acct> -s <svc>`; exit 0 or 44 = success.
- In-process read cache: 30 s (`$Wt=30000` @218702718); 1 s backoff after a failed read.

### Credential blob schema
`claudeAiOauth` (`_w` @219375257): `accessToken, refreshToken, expiresAt, refreshTokenExpiresAt, scopes, subscriptionType, subscriptionTypeSource, subscriptionTypeVerifiedAt, rateLimitTier, clientId`.

Other top-level keys seen in code: `organizationUuid, trustedDeviceToken, trustedDeviceEnrolledAfterRefusalAtMs, enterpriseGateway, designOauth, cloudSessionsOauth, coworkRemoteDevice, gatewayTrust, pluginSecrets, mcpDiscoveryCacheKey, mcpOAuth, mcpOAuthClientConfig, mcpXaaIdp, mcpXaaIdpConfig, slackTag`.

**Login-scoped keys** (deleted locally by login, @239650015): `claudeAiOauth, organizationUuid, trustedDeviceToken, trustedDeviceEnrolledAfterRefusalAtMs, enterpriseGateway, designOauth, cloudSessionsOauth`. Everything else in the blob survives a login.

## `~/.claude.json`
- Path `g_()` @216362491 / `Itr` @216362680: `${CLAUDE_CONFIG_DIR||homedir}/.claude.json`; a legacy `<cfg>/.config.json` wins if it is a non-empty file.
- Write `jo` @219040873: lock dir `${path}.lock` (proper-lockfile defaults: stale 10 s, update 5 s, **realpath on** @216552054), retry delays `[200,400,800,1600,3200,4000]` ms ×(1+rand) @219037238, re-read under lock, write temp `${path}.tmp.<pid>.<6 random bytes hex>` (O_EXCL, mode 0600, fsync) then rename (`YA` @217094026/@217096987).
- Running sessions poll the file every 1000 ms (@219031331, `qu=1000` @219030973).
- `oauthAccount` fields: `accountUuid, emailAddress, organizationUuid, displayName, fullName, hasExtraUsageEnabled, billingType, accountCreatedAt, subscriptionCreatedAt, ccOnboardingFlags, claudeCodeTrialEndsAt, claudeCodeTrialDurationDays, seatTier, planDisplayName, profileFetchedAt` (@219145124) + `organizationRole, workspaceRole, organizationName` (@219138866) + `organizationType, organizationRateLimitTier, userRateLimitTier` (@234250069).

**Account cache keys** cleared by logout and by login (`C()` @239648050, 18 keys):
`oauthAccount, additionalModelOptionsCache, additionalModelOptionsAnsweredAt, additionalModelCostsCache, modelAccessCache, orgModelDefaultCache, cachedArtifactRoster, artifactRosterDenied, lastSeenOrgDefaultUpdatedAt, clientDataCache, clientDataCacheSlots, autoCompactWindowsCache, cachedUsageUtilization, metricsStatusCache, metricsStatusCacheByPrincipal, githubWebConnectionStatusCache, unusedLimitResetStatusCache, startupPrefetchedAt`.

## Locks (bundled proper-lockfile)
- Lock = `mkdir <target>.lock` (@216550226/@216550393). Stale when the dir's mtime is older than `stale` ms → rmdir and retry (@216550890). Holder re-touches mtime every `update` ms (default stale/2; min stale 2000 ms, @216552233). Acquire sets mtime to `ceil(now/1000)*1000+5` (@216549765). Released via rmdir, also on process exit (@216553267).
- **Refresh lock** @219393150: `<cfg>/.oauth_refresh.lock`, `realpath:false, stale:60000, update:5000`; then the legacy lock `<realpath(cfg)>.lock` = `~/.claude.lock` with the same options (@219393322). 5 attempts with 1–2 s random sleep (@219397177, `mH=5` @219394935).
- Owner file `.oauth_refresh.lock.owner` (@219148309) only enables early takeover of a dead holder; if absent Claude waits for normal staleness.
- **Credential write lock** @218706190: `<cfg>/.storage-write.lock` (no lockfilePath → `.lock` appended), `realpath:false`, stale 15000, 10 retries (100–1000 ms).

## Login — `claude auth login` (handler @245858459; flags `--claudeai` (default), `--console`, `--email <email>`, `--sso`)
- Calls the logout routine with `{clearOnboarding:false, preserveInProcessTokens:true, preserveNonAnthropicAuth:true}` @243784097.
- **Old `claudeAiOauth` is NOT revoked** (revoke block @239649109 is skipped with `preserveInProcessTokens`). **`designOauth` IS revoked** (@239649825).
- Deletes the 7 login-scoped keys locally (@239650015), deletes the `Claude Code` API-key item and `primaryApiKey` (`aBo`), removes Claude-Code-created `~/.config/anthropic/credentials/<profile>.json` without revoking (`Nfs` @239642721), clears the 18 cache keys.
- Saves `claudeAiOauth` only if scopes include `user:inference` (@219379908, `Mv` @216310512) and a refresh token + expiry exist (@219380022), under the refresh lock (@243782452).
- Profile: `GET https://api.anthropic.com/api/oauth/profile` (@219131163) → `oauthAccount` mapping @243784355; roles `https://api.anthropic.com/api/oauth/claude_cli/roles` (@216311505).

## Logout — `claude auth logout` / `/logout`
- Revokes the `claudeAiOauth`, `designOauth` and `cloudSessionsOauth` refresh tokens: `POST https://platform.claude.com/v1/oauth/token/revoke` `{token, token_type_hint:"refresh_token", client_id}`, 5 s timeout (@219138425, @239649109).
- Deletes the whole keychain item under the storage-write lock, writes back only `coworkRemoteDevice` (@239650416). Clears the 18 cache keys. `/logout` also resets onboarding (@239651991); `claude auth logout` does not (@245865555).

## Refresh
- `POST https://platform.claude.com/v1/oauth/token` body `{grant_type:"refresh_token", refresh_token, client_id, scope}` (@219135888); client id `9d1c250a-e61b-44d9-88ed-5944d1962f5e` (@216311838).
- New refresh token used if returned, else old kept; `expiresAt = now + expires_in*1000` (@219136205).
- `refreshTokenExpiresAt` = `now + refresh_token_expires_in*1000` if the response has that field, otherwise **carried over** from the previous value (@219133915, @219375369).
- Trigger: `now + 5 min >= expiresAt` (`bT` @219140441).

## What a running session does when the stored login changes
- `Cw` (@219385637) runs on every API client build (@220596564 — effectively once per request). With no `.credentials.json` (normal on macOS) it calls `bl` (@219386646): drops the in-memory token and re-reads storage through the 30 s keychain cache; on a changed access token it resets clients and raises a "credentials changed" event.
  → **A swapped keychain blob is used by the first request built after the session's 30 s keychain cache expires.**
- Refresh path takes the locks, re-reads, and adopts a token another process wrote (@219396792); the save is compare-and-swap on refreshToken (@219377562).
- 401 handler re-reads and adopts a different stored token (@219389037, @219391215).
- **429 / usage limit does NOT trigger a re-read.** The retry loop rebuilds its client only under @227704625 `if(b===null||Bn||gmn(H,y.model)||on||go)`; `gmn` (@227701660) covers 401/403(helper)/407/revoked/cloud-auth errors, not 429. (Searched all 152 `rate_limit_error|anthropic-ratelimit-unified|exceeded_limit` sites for credential re-read calls: none.)
- What the UI does with the "credentials changed" event: **not determined** (spike S2 checks it).

## Env overrides
- `CLAUDE_CODE_OAUTH_TOKEN` overrides stored credentials and is re-read from `process.env` (@219382470, @219391681) — another process can't change it.
- `apiKeyHelper` output is sent as `Authorization: Bearer` + `x-api-key` but switches the session to API-key mode (not subscriber) (@219349577, @220604546, @220142118). Not usable for subscription logins.
