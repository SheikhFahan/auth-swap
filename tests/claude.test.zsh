# Claude Code flows against the stub keychain and a fake HOME.

test_save_stores_only_login_keys_and_profile() {
  claude_live_setup a
  out=$(as save claude work) || fail "save failed: $out"
  assert_contains "$out" "a@example.com"
  secret=$(kc_get auth-swap claude:work)
  assert_eq "$(jq -r '.loginKeys.claudeAiOauth.refreshToken' <<< $secret)" rt-a
  assert_eq "$(jq -r '.loginKeys.mcpOAuth // "absent"' <<< $secret)" absent "machine-wide keys stay out of the vault"
  assert_eq "$(jq -r '.oauthAccount.emailAddress' <<< $secret)" a@example.com
  idx=$(cat $HOME/.auth-swap/accounts.json)
  assert_eq "$(jq -r '.accounts[0].plan' <<< $idx)" plan-a
  assert_not_contains "$idx" "rt-a"
  assert_eq "$(stat -f %Lp $HOME/.auth-swap/accounts.json)" 600
  assert_eq "$(stat -f %Lp $HOME/.auth-swap)" 700
}

test_save_refuses_same_account_under_second_name() {
  claude_live_setup a
  as save claude one >/dev/null || fail "first save failed"
  out=$(as save claude two 2>&1) && fail "second save should fail"
  assert_contains "$out" "already saved as 'one'"
  assert_contains "$out" "auth-swap login claude two"
}

test_login_uses_temp_folder_and_cleans_up() {
  claude_live_setup a
  before=$(kc_get "Claude Code-credentials")
  export STUB_CLAUDE_BLOB="$(claude_blob b)" STUB_CLAUDE_OA="$(claude_oa b)" CLAUDE_CODE_OAUTH_TOKEN_UNUSED=1
  out=$(as login claude second -- --claudeai) || fail "login failed: $out"
  assert_contains "$(cat $STUB_LOG)" "args=--claudeai"
  assert_contains "$(cat $STUB_LOG)" "CLAUDE_CODE_OAUTH_TOKEN=unset"
  assert_eq "$(kc_get "Claude Code-credentials")" "$before" "live login untouched"
  assert_eq "$(jq -r .oauthAccount.emailAddress $HOME/.claude.json)" a@example.com
  assert_eq "$(jq -r '.loginKeys.claudeAiOauth.refreshToken' <<< "$(kc_get auth-swap claude:second)")" rt-b
  assert_eq "$(ls $STUB_KC | grep -v '\.' | wc -l | tr -d ' ')" 2 "only live item + vault item remain (temp item deleted)"
  assert_eq "$(ls $TMPDIR | wc -l | tr -d ' ')" 0 "temp folder removed"
}

test_login_failure_cleans_up() {
  export STUB_CLAUDE_FAIL=1 STUB_CLAUDE_BLOB='{}' STUB_CLAUDE_OA='{}'
  out=$(as login claude x 2>&1) && fail "login should fail"
  assert_eq "$(ls $TMPDIR | wc -l | tr -d ' ')" 0 "temp folder removed"
  assert_eq "$(jq '.accounts | length' $HOME/.auth-swap/accounts.json)" 0
}

test_use_swaps_and_saves_back_rotated_tokens() {
  claude_live_setup a
  as save claude a >/dev/null || fail "save a"
  export STUB_CLAUDE_BLOB="$(claude_blob b)" STUB_CLAUDE_OA="$(claude_oa b)"
  as login claude b >/dev/null || fail "login b"
  # Claude refreshes account a in the meantime (tokens rotate)
  kc_put "Claude Code-credentials" "$(claude_blob a '{"mcpOAuth":{"srv":"keep-me"}}' | jq -c '.claudeAiOauth.refreshToken = "rt-a-rotated"')"
  out=$(as use claude b) || fail "use failed: $out"
  assert_contains "$out" "Claude → b (b@example.com)"
  live=$(kc_get "Claude Code-credentials")
  assert_eq "$(jq -r .claudeAiOauth.refreshToken <<< $live)" rt-b
  assert_eq "$(jq -r .organizationUuid <<< $live)" org-b
  assert_eq "$(jq -r .mcpOAuth.srv <<< $live)" keep-me "machine-wide keys kept"
  cfg=$(cat $HOME/.claude.json)
  assert_eq "$(jq -r .oauthAccount.emailAddress <<< $cfg)" b@example.com
  assert_eq "$(jq -r '.modelAccessCache // "gone"' <<< $cfg)" gone
  assert_eq "$(jq -r '.startupPrefetchedAt // "gone"' <<< $cfg)" gone
  assert_eq "$(jq -r .theme <<< $cfg)" dark "unrelated settings kept"
  assert_eq "$(stat -f %Lp $HOME/.claude.json)" 600
  assert_eq "$(jq -r .loginKeys.claudeAiOauth.refreshToken <<< "$(kc_get auth-swap claude:a)")" rt-a-rotated "saved back"
  # and back again
  as use claude a >/dev/null || fail "use a"
  assert_eq "$(jq -r .claudeAiOauth.refreshToken <<< "$(kc_get "Claude Code-credentials")")" rt-a-rotated
  assert_eq "$(jq -r .oauthAccount.emailAddress $HOME/.claude.json)" a@example.com
  for l in .oauth_refresh.lock .storage-write.lock; do [[ ! -e $HOME/.claude/$l ]] || fail "$l left behind"; done
  [[ ! -e $HOME/.claude.lock && ! -e $HOME/.claude.json.lock ]] || fail "lock left behind"
}

test_list_marks_active() {
  claude_live_setup a
  as save claude a >/dev/null
  export STUB_CLAUDE_BLOB="$(claude_blob b)" STUB_CLAUDE_OA="$(claude_oa b)"
  as login claude b >/dev/null
  out=$(as list claude --json)
  assert_eq "$(jq -r 'map(select(.active)) | .[0].name' <<< $out)" a
  assert_eq "$(jq -r '.[0] | has("identity")' <<< $out)" false
  txt=$(as list)
  assert_contains "$txt" "refresh expiry (as recorded by Claude): 2025-10-29"
}

test_use_refuses_unsaved_live_login_unless_no_save() {
  claude_live_setup a
  export STUB_CLAUDE_BLOB="$(claude_blob b)" STUB_CLAUDE_OA="$(claude_oa b)"
  as login claude b >/dev/null || fail "login b"
  out=$(as use claude b 2>&1) && fail "should refuse"
  assert_contains "$out" "isn't saved yet"
  assert_eq "$(jq -r .claudeAiOauth.refreshToken <<< "$(kc_get "Claude Code-credentials")")" rt-a "nothing changed"
  as use claude b --no-save >/dev/null || fail "--no-save should proceed"
  assert_eq "$(jq -r .claudeAiOauth.refreshToken <<< "$(kc_get "Claude Code-credentials")")" rt-b
}

test_use_with_no_live_login() {
  mkdir -p $HOME/.claude
  export STUB_CLAUDE_BLOB="$(claude_blob b)" STUB_CLAUDE_OA="$(claude_oa b)"
  as login claude b >/dev/null || fail "login b"
  as use claude b >/dev/null || fail "use should work with nobody logged in"
  assert_eq "$(jq -r .claudeAiOauth.refreshToken <<< "$(kc_get "Claude Code-credentials")")" rt-b
  assert_eq "$(jq -r .oauthAccount.emailAddress $HOME/.claude.json)" b@example.com
}

test_use_refuses_blocking_env() {
  claude_live_setup a
  as save claude a >/dev/null
  out=$(CLAUDE_CONFIG_DIR=$HOME/x as use claude a 2>&1) && fail "should refuse CLAUDE_CONFIG_DIR"
  assert_contains "$out" "CLAUDE_CONFIG_DIR is set"
  out=$(CLAUDE_CODE_OAUTH_TOKEN=t as use claude a 2>&1) && fail "should refuse CLAUDE_CODE_OAUTH_TOKEN"
  assert_contains "$out" "CLAUDE_CODE_OAUTH_TOKEN is set"
}

test_use_waits_for_claude_refresh_lock_and_takes_stale_one() {
  claude_live_setup a
  as save claude a >/dev/null
  mkdir $HOME/.claude/.oauth_refresh.lock
  out=$(as use claude a 2>&1) && fail "should time out on a fresh lock"
  assert_contains "$out" "busy refreshing"
  [[ -d $HOME/.claude/.oauth_refresh.lock ]] || fail "someone else's lock must not be removed"
  touch -t 202001010000 $HOME/.claude/.oauth_refresh.lock
  as use claude a >/dev/null || fail "stale lock should be taken over"
}

test_use_rolls_back_keychain_when_config_write_fails() {
  claude_live_setup a
  as save claude a >/dev/null
  export STUB_CLAUDE_BLOB="$(claude_blob b)" STUB_CLAUDE_OA="$(claude_oa b)"
  as login claude b >/dev/null
  mkdir $HOME/.claude.json.lock   # held by "Claude", fresh
  out=$(as use claude b 2>&1) && fail "should fail"
  assert_contains "$out" "previous login was put back"
  assert_eq "$(jq -r .claudeAiOauth.refreshToken <<< "$(kc_get "Claude Code-credentials")")" rt-a
  assert_eq "$(jq -r .oauthAccount.emailAddress $HOME/.claude.json)" a@example.com
}

test_keychain_writes_use_stdin_within_limit() {
  claude_live_setup a
  as save claude a >/dev/null
  export STUB_CLAUDE_BLOB="$(claude_blob b)" STUB_CLAUDE_OA="$(claude_oa b)"
  as login claude b >/dev/null
  as use claude b >/dev/null
  [[ -s $STUB_KC/.stdin-lengths ]] || fail "expected stdin writes"
  max=$(sort -n $STUB_KC/.stdin-lengths | tail -1)
  (( max <= 4032 )) || fail "stdin command too long: $max"
}

test_remove_never_touches_live_login() {
  claude_live_setup a
  as save claude a >/dev/null
  before=$(kc_get "Claude Code-credentials")
  as remove claude a >/dev/null || fail "remove failed"
  kc_has auth-swap claude:a && fail "vault item should be gone"
  assert_eq "$(kc_get "Claude Code-credentials")" "$before"
}

test_non_ascii_profile_round_trips_as_ascii_in_keychain() {
  claude_live_setup a
  jq '.oauthAccount.fullName = "Zoë Ångström"' $HOME/.claude.json > $HOME/c.json && mv $HOME/c.json $HOME/.claude.json
  as save claude a >/dev/null || fail "save"
  secret=$(kc_get auth-swap claude:a)
  [[ $secret == *u00eb* ]] || fail "expected ASCII escapes in the keychain value"
  [[ $secret != *ë* ]] || fail "raw UTF-8 in the keychain value"
  export STUB_CLAUDE_BLOB="$(claude_blob b)" STUB_CLAUDE_OA="$(claude_oa b)"
  as login claude b >/dev/null && as use claude b >/dev/null && as use claude a >/dev/null || fail "swap round trip"
  assert_eq "$(jq -r .oauthAccount.fullName $HOME/.claude.json)" "Zoë Ångström"
}

test_reads_live_blob_that_keychain_prints_as_hex() {
  claude_live_setup a
  # Claude stored raw UTF-8 in its own item: security -w prints it as hex
  kc_put "Claude Code-credentials" "$(claude_blob a '{"mcpOAuth":{"srv":"café"}}' | jq -c .)"
  as save claude a >/dev/null || fail "save should decode the hex form"
  export STUB_CLAUDE_BLOB="$(claude_blob b)" STUB_CLAUDE_OA="$(claude_oa b)"
  as login claude b >/dev/null && as use claude b >/dev/null || fail "use"
  assert_eq "$(jq -r .mcpOAuth.srv <<< "$(kc_get "Claude Code-credentials")")" "café"
}

test_use_of_active_login_keeps_fresh_tokens() {
  claude_live_setup a
  as save claude a >/dev/null || fail "save a"
  # Claude refreshes account a after it was saved (tokens rotate)
  kc_put "Claude Code-credentials" "$(claude_blob a | jq -c '.claudeAiOauth.refreshToken = "rt-a-rotated"')"
  out=$(as use claude a) || fail "use failed: $out"
  assert_contains "$out" "already using 'a'"
  assert_eq "$(jq -r .claudeAiOauth.refreshToken <<< "$(kc_get "Claude Code-credentials")")" rt-a-rotated "fresh tokens stay live"
  assert_eq "$(jq -r .loginKeys.claudeAiOauth.refreshToken <<< "$(kc_get auth-swap claude:a)")" rt-a-rotated "saved back"
  assert_eq "$(jq -r '.modelAccessCache | type' $HOME/.claude.json)" object "caches kept: nothing switched"
}
