# auth-swap — Claude Code. Every rule here mirrors Claude Code 2.1.305 (checked against its binary).

typeset -g AS_CLAUDE=${AUTH_SWAP_CLAUDE:-claude}
typeset -g CLAUDE_KC_SERVICE="Claude Code-credentials"
# Keychain keys that belong to one login: Claude's own login deletes exactly these.
typeset -g CLAUDE_LOGIN_KEYS_JSON='["claudeAiOauth","organizationUuid","trustedDeviceToken","trustedDeviceEnrolledAfterRefusalAtMs","enterpriseGateway","designOauth","cloudSessionsOauth"]'
# ~/.claude.json keys that Claude's login and logout clear (oauthAccount is set separately).
typeset -g CLAUDE_CACHE_KEYS_JSON='["additionalModelOptionsCache","additionalModelOptionsAnsweredAt","additionalModelCostsCache","modelAccessCache","orgModelDefaultCache","cachedArtifactRoster","artifactRosterDenied","lastSeenOrgDefaultUpdatedAt","clientDataCache","clientDataCacheSlots","autoCompactWindowsCache","cachedUsageUtilization","metricsStatusCache","metricsStatusCacheByPrincipal","githubWebConnectionStatusCache","unusedLimitResetStatusCache","startupPrefetchedAt"]'
typeset -g CLAUDE_LOCK_TIMEOUT=${AUTH_SWAP_LOCK_TIMEOUT:-20}

claude_global_config() { # same choice Claude makes between .config.json (legacy) and ~/.claude.json
  local legacy=$HOME/.claude/.config.json main=$HOME/.claude.json
  if [[ -f $legacy ]] && { [[ -s $legacy ]] || [[ -w $legacy && ! -e $main ]] }; then
    print -r -- $legacy
  else
    print -r -- $main
  fi
}

claude_kc_account() { # process.env.USER || os.userInfo().username, else "claude-code-user"
  local u=${USER:-}
  [[ -n $u ]] || u=$(id -un 2>/dev/null)
  [[ $u =~ '^[a-zA-Z0-9._-]+$' ]] || u=claude-code-user
  print -r -- $u
}

claude_env_check() {
  local v
  for v in CLAUDE_CONFIG_DIR CLAUDE_SECURESTORAGE_CONFIG_DIR CLAUDE_CODE_OAUTH_TOKEN; do
    [[ -z ${(P)v:-} ]] || as_die "$v is set; auth-swap only manages the single ~/.claude login (unset $v and retry)"
  done
}

# Snapshot = the login-scoped keychain keys + oauthAccount.
claude_snapshot() { # <blob-json> <oauthAccount-json>; ASCII-only (-a) because it goes to the keychain
  $AS_JQ -acn --argjson b $1 --argjson oa $2 --argjson keys $CLAUDE_LOGIN_KEYS_JSON \
    '{loginKeys: ($b | with_entries(select(.key as $k | $keys | index($k)))), oauthAccount: $oa}'
}

claude_meta() { # <snapshot-json> -> index metadata (no secrets)
  $AS_JQ -c '{
    identity: ((.oauthAccount.accountUuid // "") + ":" + (.oauthAccount.organizationUuid // "")),
    email: .oauthAccount.emailAddress,
    plan: .loginKeys.claudeAiOauth.subscriptionType,
    org: .oauthAccount.organizationName,
    refreshExpiresAt: .loginKeys.claudeAiOauth.refreshTokenExpiresAt
  }' <<< $1
}

claude_validate_snapshot() { # a login Claude itself would keep: refresh token + user:inference scope
  $AS_JQ -e '
    (.loginKeys.claudeAiOauth.refreshToken // "" | length > 0)
    and ((.loginKeys.claudeAiOauth.scopes // []) | index("user:inference"))
    and (.oauthAccount.accountUuid // "" | length > 0)
  ' <<< $1 >/dev/null
}

claude_live_identity() { # from ~/.claude.json oauthAccount; empty when logged out
  $AS_JQ -r '.oauthAccount | select(. != null) | (.accountUuid // "") + ":" + (.organizationUuid // "")' \
    $(claude_global_config) 2>/dev/null
}

# Claude's own locks, in Claude's order: refresh lock, legacy lock, credential-write lock.
claude_lock_credentials() {
  local deadline=$(( SECONDS + CLAUDE_LOCK_TIMEOUT )) cfg=$HOME/.claude
  [[ -d $cfg ]] || as_die "Claude Code isn't set up on this Mac yet (no $cfg); run claude once first"
  as_lock_acquire $cfg/.oauth_refresh.lock 60 $(( deadline - SECONDS )) \
    && as_lock_acquire ${cfg:A}.lock 60 $(( deadline - SECONDS )) \
    && as_lock_acquire $cfg/.storage-write.lock 15 $(( deadline - SECONDS )) \
    || as_die "Claude Code is busy refreshing its login; try again in a few seconds"
}

claude_read_live() { # sets live_blob, live_oa (empty when absent)
  live_blob=$(as_kc_read $CLAUDE_KC_SERVICE $(claude_kc_account)) || live_blob=
  live_oa=$($AS_JQ -c '.oauthAccount // empty' $(claude_global_config) 2>/dev/null) || live_oa=
}

claude_write_config() { # <oauthAccount-json>: set it and clear the account caches, under Claude's config lock
  local oa=$1 cfg out
  cfg=$(claude_global_config)
  as_lock_acquire ${cfg:A}.lock 10 $CLAUDE_LOCK_TIMEOUT || return 1
  if [[ -f $cfg ]]; then
    out=$($AS_JQ --argjson oa $oa --argjson drop $CLAUDE_CACHE_KEYS_JSON \
      '.oauthAccount = $oa | delpaths([$drop[] | [.]])' $cfg) || { as_lock_release ${cfg:A}.lock; return 1 }
  else
    out=$($AS_JQ -n --argjson oa $oa '{oauthAccount: $oa}')
  fi
  print -r -- $out | as_write_atomic $cfg 600
  local rc=$?
  as_lock_release ${cfg:A}.lock
  return $rc
}

claude_save() { # <name>
  local name=$1 live_blob live_oa snap
  claude_env_check
  vault_init; vault_lock
  claude_lock_credentials
  claude_read_live
  as_release_all_locks
  [[ -n $live_blob && -n $live_oa ]] || as_die "no Claude login is active right now"
  snap=$(claude_snapshot $live_blob $live_oa) || as_die "could not read the active Claude login"
  claude_validate_snapshot $snap || as_die "the active Claude login is not a full subscription login"
  vault_refuse_saved_elsewhere claude $name "$(claude_meta $snap)"
  vault_store claude $name $snap "$(claude_meta $snap)"
  print -r -- "Saved the active Claude login as '$name' ($($AS_JQ -r '.oauthAccount.emailAddress' <<< $snap))."
}

claude_login() { # <name> [claude auth login flags...]
  local name=$1; shift
  local tmp sha acct blob oa snap
  command -v $AS_CLAUDE >/dev/null || as_die "claude is not installed (no '$AS_CLAUDE' on PATH)"
  vault_init
  [[ -z $(vault_entry claude $name) ]] || as_die "'$name' already exists; pick another name or 'auth-swap remove claude $name'"
  acct=$(claude_kc_account)
  tmp=$(as_mktemp_dir) || as_die "cannot create a temp folder"
  sha=$(as_sha8 $tmp)
  AS_CLEANUP+=("as_kc_delete ${(q)CLAUDE_KC_SERVICE}-$sha ${(q)acct}" "as_kc_delete 'Claude Code-$sha' ${(q)acct}" "rm -rf -- ${(q)tmp}")
  print -r -- "Opening the Claude login for '$name'. Your current login and open chats are not touched."
  env -u CLAUDE_CODE_OAUTH_TOKEN -u CLAUDE_SECURESTORAGE_CONFIG_DIR -u CLAUDE_CONFIG_DIR \
    CLAUDE_CONFIG_DIR=$tmp $AS_CLAUDE auth login "$@" || as_die "claude auth login did not finish"
  blob=$(as_kc_read "$CLAUDE_KC_SERVICE-$sha" $acct) || as_die "the login finished but its keychain item was not found"
  oa=$($AS_JQ -c '.oauthAccount // empty' $tmp/.claude.json 2>/dev/null)
  [[ -n $oa ]] || as_die "the login finished but no account profile was written"
  snap=$(claude_snapshot $blob $oa) || as_die "could not read the new login"
  claude_validate_snapshot $snap || as_die "the new login is not a subscription login (missing refresh token or user:inference scope)"
  vault_lock
  vault_store claude $name $snap "$(claude_meta $snap)"
  print -r -- "Saved Claude login '$name' ($($AS_JQ -r '.oauthAccount.emailAddress' <<< $snap)). Switch with: auth-swap use claude $name"
}

claude_use() { # <name> <no_save:0|1>
  local name=$1 no_save=$2 target live_blob live_oa live_id live_name snap new_blob email
  claude_env_check
  vault_init
  [[ -n $(vault_entry claude $name) ]] || as_die "no saved Claude login named '$name' (see: auth-swap list claude)"
  vault_lock
  target=$(vault_secret_get claude $name) || as_die "the saved login '$name' is missing from the keychain"
  claude_lock_credentials
  claude_read_live

  # Save the active login's current tokens first: they rotate on every refresh.
  if [[ -n $live_blob ]] && $AS_JQ -e '.claudeAiOauth' <<< $live_blob >/dev/null 2>&1; then
    live_id=$($AS_JQ -r '(.accountUuid // "") + ":" + (.organizationUuid // "")' <<< ${live_oa:-'{}'})
    live_name=$(vault_name_for_identity claude $live_id)
    if [[ -n $live_name && -n $live_oa ]]; then
      snap=$(claude_snapshot $live_blob $live_oa) && vault_store claude $live_name $snap "$(claude_meta $snap)" \
        || as_die "could not save the active login '$live_name'; nothing was changed"
      # Already active: writing the vault copy read above would replace newer tokens with older ones.
      if [[ $live_name == $name ]]; then
        as_release_all_locks
        print -r -- "Claude is already using '$name'; its latest tokens are saved."
        return 0
      fi
    elif (( ! no_save )); then
      email=$($AS_JQ -r '.emailAddress // "unknown account"' <<< ${live_oa:-'{}'})
      as_die "the active Claude login ($email) isn't saved yet. Run 'auth-swap save claude <name>' first, or add --no-save to drop it (it is not revoked)"
    fi
  fi

  new_blob=$($AS_JQ -acn --argjson live ${live_blob:-'{}'} --argjson t $target --argjson keys $CLAUDE_LOGIN_KEYS_JSON \
    '($live | with_entries(select(.key as $k | $keys | index($k) | not))) + $t.loginKeys') \
    || as_die "could not build the new login"
  as_kc_write $CLAUDE_KC_SERVICE $(claude_kc_account) $new_blob || as_die "could not write the Claude keychain item; nothing was changed"
  as_locks_touch
  if ! claude_write_config "$($AS_JQ -c '.oauthAccount' <<< $target)"; then
    if [[ -n $live_blob ]]; then
      as_kc_write $CLAUDE_KC_SERVICE $(claude_kc_account) $live_blob
    else
      as_kc_delete $CLAUDE_KC_SERVICE $(claude_kc_account)
    fi
    as_die "could not update $(claude_global_config); the previous login was put back"
  fi
  as_release_all_locks
  print -r -- "Claude → $name ($($AS_JQ -r '.oauthAccount.emailAddress' <<< $target)). Open chats switch on their next message sent at least 30 s after their last request."
}

claude_remove() { # <name>
  vault_init; vault_lock
  [[ -n $(vault_entry claude $1) ]] || as_die "no saved Claude login named '$1'"
  vault_secret_delete claude $1 || as_die "could not delete the keychain entry for '$1'"
  vault_remove_entry claude $1 || as_die "could not update $(vault_index)"
  print -r -- "Removed Claude login '$1' from auth-swap (it was not revoked; the active login is unchanged)."
}
