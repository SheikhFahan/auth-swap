# Codex flows against a fake HOME and the stub codex daemon.

test_codex_save_and_list() {
  codex_live_setup a
  out=$(as save codex a) || fail "save failed: $out"
  assert_contains "$out" "a@example.com"
  assert_eq "$(stat -f %Lp $HOME/.auth-swap/codex/a.auth.json)" 600
  out=$(as list codex --json)
  assert_eq "$(jq -r '.[0].active' <<< $out)" true
  assert_eq "$(jq -r '.[0].plan' <<< $out)" plus
}

test_codex_login_uses_temp_home() {
  codex_live_setup a
  before=$(shasum -a 256 < $HOME/.codex/auth.json)
  export STUB_CODEX_AUTH="$(codex_auth b)"
  out=$(as login codex b -- --device-auth) || fail "login failed: $out"
  assert_contains "$(cat $STUB_LOG)" "args=--device-auth"
  assert_contains "$(cat $STUB_LOG)" "CODEX_HOME=${TMPDIR:A}"
  assert_eq "$(shasum -a 256 < $HOME/.codex/auth.json)" "$before" "live auth.json untouched"
  assert_eq "$(jq -r .tokens.refresh_token $HOME/.auth-swap/codex/b.auth.json)" rt-b
  assert_eq "$(ls $TMPDIR | wc -l | tr -d ' ')" 0 "temp folder removed"
}

test_codex_login_rejects_api_key_login() {
  export STUB_CODEX_AUTH='{"auth_mode":"apikey","OPENAI_API_KEY":"sk-x"}'
  out=$(as login codex k 2>&1) && fail "should refuse"
  assert_contains "$out" "not a ChatGPT login"
}

test_codex_use_stops_daemon_saves_back_writes_restarts() {
  codex_live_setup a running
  as save codex a >/dev/null
  export STUB_CODEX_AUTH="$(codex_auth b)"
  as login codex b >/dev/null
  codex_auth a -rotated > $HOME/.codex/auth.json   # daemon refreshed a
  : > $STUB_LOG
  out=$(as use codex b) || fail "use failed: $out"
  assert_contains "$out" "Codex → b (b@example.com)"
  assert_eq "$(cat $STUB_LOG)" $'daemon stop\ndaemon start email=b@example.com' "stop, then start on the new login"
  assert_eq "$(jq -r .tokens.refresh_token $HOME/.codex/auth.json)" rt-b
  assert_eq "$(stat -f %Lp $HOME/.codex/auth.json)" 600
  assert_eq "$(jq -r .tokens.refresh_token $HOME/.auth-swap/codex/a.auth.json)" rt-a-rotated "saved back"
}

test_codex_use_leaves_stopped_daemon_stopped() {
  codex_live_setup a stopped
  as save codex a >/dev/null
  export STUB_CODEX_AUTH="$(codex_auth b)"
  as login codex b >/dev/null
  : > $STUB_LOG
  as use codex b >/dev/null || fail "use failed"
  assert_eq "$(cat $STUB_LOG)" "" "no stop/start when the daemon wasn't running"
}

test_codex_use_refusal_restarts_daemon() {
  codex_live_setup a running
  export STUB_CODEX_AUTH="$(codex_auth b)"
  as login codex b >/dev/null
  : > $STUB_LOG
  out=$(as use codex b 2>&1) && fail "should refuse unsaved live login"
  assert_contains "$out" "isn't saved yet"
  assert_eq "$(cat $STUB_LOG)" $'daemon stop\ndaemon start email=a@example.com' "daemon brought back on the old login"
  assert_eq "$(jq -r .tokens.refresh_token $HOME/.codex/auth.json)" rt-a
}

test_codex_use_refuses_keyring_mode_and_codex_home() {
  codex_live_setup a
  as save codex a >/dev/null
  print -r -- 'model = "x"
cli_auth_credentials_store = "keyring"
[plugins."x@y"]
enabled = true' > $HOME/.codex/config.toml
  out=$(as use codex a 2>&1) && fail "should refuse keyring mode"
  assert_contains "$out" "'keyring' mode"
  print -r -- '[profiles.x]
cli_auth_credentials_store = "keyring"' > $HOME/.codex/config.toml
  as use codex a >/dev/null || fail "a table-scoped key is not the top-level setting"
  out=$(CODEX_HOME=$HOME/x as use codex a 2>&1) && fail "should refuse CODEX_HOME"
  assert_contains "$out" "CODEX_HOME is set"
}

test_list_empty_message_and_remove() {
  out=$(as list)
  assert_contains "$out" "No saved logins yet"
  codex_live_setup a
  as save codex a >/dev/null
  as remove codex a >/dev/null || fail "remove failed"
  [[ ! -e $HOME/.auth-swap/codex/a.auth.json ]] || fail "vault file should be gone"
  [[ -f $HOME/.codex/auth.json ]] || fail "live login must stay"
}

test_codex_use_refuses_unreadable_live_login_and_restarts_daemon() {
  codex_live_setup a running
  export STUB_CODEX_AUTH="$(codex_auth b)"
  as login codex b >/dev/null
  print -r -- '{not json' > $HOME/.codex/auth.json
  : > $STUB_LOG
  out=$(as use codex b 2>&1) && fail "should refuse"
  assert_contains "$out" "could not read"
  assert_eq "$(cat $HOME/.codex/auth.json)" '{not json' "live file untouched"
  assert_eq "$(sed -n 2p $STUB_LOG | cut -d' ' -f1-2)" "daemon start" "daemon brought back"
}

test_codex_use_of_active_login_keeps_fresh_tokens_and_daemon() {
  codex_live_setup a running
  as save codex a >/dev/null
  codex_auth a -rotated > $HOME/.codex/auth.json   # daemon refreshed a
  : > $STUB_LOG
  out=$(as use codex a) || fail "use failed: $out"
  assert_contains "$out" "already using 'a'"
  assert_eq "$(cat $STUB_LOG)" "" "daemon left alone"
  assert_eq "$(jq -r .tokens.refresh_token $HOME/.codex/auth.json)" rt-a-rotated "fresh tokens stay live"
  assert_eq "$(jq -r .tokens.refresh_token $HOME/.auth-swap/codex/a.auth.json)" rt-a-rotated "saved back"
}

test_codex_save_of_already_saved_account_points_to_login() {
  codex_live_setup a
  as save codex one >/dev/null || fail "first save failed"
  out=$(as save codex two 2>&1) && fail "second save should fail"
  assert_contains "$out" "already saved as 'one'"
  assert_contains "$out" "auth-swap login codex two"
}
