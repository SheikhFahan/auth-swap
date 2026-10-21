# Test helpers. Every test runs with a throwaway HOME, the stub `security`,
# and stub `claude` / `codex` first on PATH — never the real keychain or logins.
emulate -R zsh
setopt extended_glob

typeset -g ROOT=${ROOT:-${${(%):-%x}:A:h:h}}
typeset -g T_REAL_HOME=$HOME

t_setup() {
  export HOME=$(/usr/bin/mktemp -d /tmp/auth-swap-test.XXXXXX)
  export TMPDIR=$HOME/tmp; mkdir -p $TMPDIR
  export USER=tester
  export STUB_KC=$HOME/kc STUB_LOG=$HOME/stub.log STUB_DAEMON_STATE=$HOME/daemon.state
  export AUTH_SWAP_SECURITY=$ROOT/tests/stubs/security
  export AUTH_SWAP_LOCK_TIMEOUT=2
  export PATH=$ROOT/tests/stubs:/usr/bin:/bin:/usr/sbin:/sbin
  unset CLAUDE_CONFIG_DIR CLAUDE_SECURESTORAGE_CONFIG_DIR CLAUDE_CODE_OAUTH_TOKEN CODEX_HOME
  touch $STUB_LOG
}

t_teardown() {
  [[ $HOME == /tmp/auth-swap-test.* ]] && rm -rf -- $HOME
}

as() { $ROOT/bin/auth-swap "$@" }

fail() { print -ru2 -- "  assertion failed: $*"; exit 1 }
assert_eq() { [[ $1 == $2 ]] || fail "expected [$2] got [$1]${3:+ ($3)}" }
assert_contains() { [[ $1 == *$2* ]] || fail "expected to contain [$2] in [$1]" }
assert_not_contains() { [[ $1 != *$2* ]] || fail "expected NOT to contain [$2] in [$1]" }

kc_get() { $AUTH_SWAP_SECURITY find-generic-password -a ${2:-$USER} -s $1 -w 2>/dev/null }
kc_put() { $AUTH_SWAP_SECURITY add-generic-password -U -a ${3:-$USER} -s $1 -X $(print -rn -- $2 | xxd -p | tr -d '\n') }
kc_has() { $AUTH_SWAP_SECURITY find-generic-password -a ${2:-$USER} -s $1 >/dev/null 2>&1 }

# ---- Claude fixtures ----
claude_blob() { # <tag> [extra-json] -> keychain blob for account <tag>
  /usr/bin/jq -cn --arg t $1 --argjson x ${2:-'{}'} '{
    claudeAiOauth: {accessToken: ("at-" + $t), refreshToken: ("rt-" + $t), expiresAt: 1, refreshTokenExpiresAt: 1761755280000,
      scopes: ["user:inference", "user:profile"], subscriptionType: ("plan-" + $t), rateLimitTier: "x", clientId: "c"},
    organizationUuid: ("org-" + $t)
  } + $x'
}
claude_oa() { # <tag>
  /usr/bin/jq -cn --arg t $1 '{accountUuid: ("acct-" + $t), organizationUuid: ("org-" + $t), emailAddress: ($t + "@example.com"), organizationName: ("Org " + $t)}'
}
claude_live_setup() { # <tag>: make <tag> the active Claude login, with machine-wide keys + caches
  mkdir -p $HOME/.claude
  kc_put "Claude Code-credentials" "$(claude_blob $1 '{"mcpOAuth":{"srv":"keep-me"}}')"
  /usr/bin/jq -n --argjson oa "$(claude_oa $1)" \
    '{numStartups: 7, theme: "dark", oauthAccount: $oa, modelAccessCache: {a: 1}, startupPrefetchedAt: 5, cachedUsageUtilization: {u: 2}}' \
    > $HOME/.claude.json
}

# ---- Codex fixtures ----
b64url() { print -rn -- $1 | base64 | tr -d '\n=' | tr '/+' '_-' }
codex_auth() { # <tag> [refresh-suffix] -> auth.json content
  local payload idt
  payload=$(/usr/bin/jq -cn --arg t $1 '{email: ($t + "@example.com"),
    "https://api.openai.com/auth": {chatgpt_user_id: ("user-" + $t), chatgpt_account_id: ("ws-" + $t), chatgpt_plan_type: "plus"}}')
  idt="$(b64url '{"alg":"none"}').$(b64url $payload).sig"
  /usr/bin/jq -n --arg idt $idt --arg t $1 --arg r "${2:-}" '{auth_mode: "chatgpt", OPENAI_API_KEY: null,
    tokens: {id_token: $idt, access_token: ("at-" + $t), refresh_token: ("rt-" + $t + $r), account_id: ("ws-" + $t)},
    last_refresh: "2026-10-21T00:00:00Z"}'
}
codex_live_setup() { # <tag> [daemon-state]
  mkdir -p $HOME/.codex
  codex_auth $1 > $HOME/.codex/auth.json
  print -r -- ${2:-running} > $STUB_DAEMON_STATE
}
