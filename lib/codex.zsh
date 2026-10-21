# auth-swap — Codex CLI. Every rule here mirrors Codex 0.163.0;
# see docs/research/codex-0.163.0.md for the source lines behind each one.

typeset -g AS_CODEX=${AUTH_SWAP_CODEX:-codex}
typeset -gi AS_CODEX_RESTART=0

codex_auth_file() { print -r -- $HOME/.codex/auth.json }

codex_env_check() {
  [[ -z ${CODEX_HOME:-} ]] || as_die "CODEX_HOME is set; auth-swap only manages the single ~/.codex login (unset CODEX_HOME and retry)"
  local cfg=$HOME/.codex/config.toml mode
  [[ -f $cfg ]] || return 0
  # top-level key only (before the first [table])
  mode=$(/usr/bin/awk '/^[[:space:]]*\[/ { exit }
    /^[[:space:]]*cli_auth_credentials_store[[:space:]]*=/ { sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]*#.*$/, ""); gsub(/["'\'']/, ""); print; exit }' $cfg)
  [[ -z $mode || $mode == file ]] \
    || as_die "Codex keeps its login in '$mode' mode; auth-swap supports only the default file mode (cli_auth_credentials_store = \"file\")"
}

codex_meta() { # <auth.json content> -> index metadata from the id_token claims (no secrets)
  local idt payload
  idt=$($AS_JQ -r '.tokens.id_token // empty' <<< $1 2>/dev/null)
  [[ -n $idt ]] || return 1
  payload=$(as_jwt_payload $idt) || return 1
  $AS_JQ -c '."https://api.openai.com/auth" as $a | {
    identity: ((.email // "") + "|" + ($a.chatgpt_user_id // "") + "|" + ($a.chatgpt_account_id // "")),
    email: .email,
    plan: $a.chatgpt_plan_type,
    org: null
  }' <<< $payload 2>/dev/null
}

codex_validate() { # a ChatGPT login with a refresh token and a readable identity
  $AS_JQ -e '(.auth_mode == "chatgpt") and (.tokens.refresh_token // "" | length > 0)' <<< $1 >/dev/null 2>&1 \
    && [[ $($AS_JQ -r '.email // ""' <<< "$(codex_meta $1)") != "" ]]
}

codex_read_live() { # live auth.json content (nothing when absent); fails on unreadable JSON.
  # Retries a torn read: Codex writes the file in place.
  local f=$(codex_auth_file) i content
  [[ -f $f ]] || return 0
  for i in 1 2 3; do
    content=$(cat -- $f 2>/dev/null)
    $AS_JQ -e . <<< $content >/dev/null 2>&1 && { print -r -- $content; return 0 }
    sleep 0.2
  done
  return 1
}

codex_daemon_status() { $AS_CODEX app-server daemon version 2>/dev/null | $AS_JQ -r '.status // empty' 2>/dev/null }

codex_daemon_restart_if_needed() { # cleanup hook: bring the daemon back if we stopped it
  (( AS_CODEX_RESTART )) || return 0
  AS_CODEX_RESTART=0
  $AS_CODEX app-server daemon start >/dev/null 2>&1 \
    || as_warn "could not restart the Codex daemon; run: codex app-server daemon start"
}

codex_save() { # <name>
  local name=$1 live
  codex_env_check
  vault_init; vault_lock
  live=$(codex_read_live) || as_die "could not read $(codex_auth_file) as JSON"
  [[ -n $live ]] || as_die "no Codex login is active right now"
  codex_validate $live || as_die "the active Codex login is not a ChatGPT login auth-swap can save"
  vault_refuse_saved_elsewhere codex $name "$(codex_meta $live)"
  vault_store codex $name $live "$(codex_meta $live)"
  print -r -- "Saved the active Codex login as '$name' ($($AS_JQ -r .email <<< "$(codex_meta $live)"))."
}

codex_login() { # <name> [codex login flags...]
  local name=$1; shift
  local tmp auth
  command -v $AS_CODEX >/dev/null || as_die "codex is not installed (no '$AS_CODEX' on PATH)"
  vault_init
  [[ -z $(vault_entry codex $name) ]] || as_die "'$name' already exists; pick another name or 'auth-swap remove codex $name'"
  tmp=$(as_mktemp_dir) || as_die "cannot create a temp folder"
  AS_CLEANUP+=("rm -rf -- ${(q)tmp}")
  print -r -- "Opening the Codex login for '$name'. Your current login and open chats are not touched."
  env -u CODEX_HOME CODEX_HOME=$tmp $AS_CODEX login "$@" || as_die "codex login did not finish"
  auth=$(cat -- $tmp/auth.json 2>/dev/null) || as_die "the login finished but no auth.json was written"
  codex_validate $auth || as_die "the new login is not a ChatGPT login (auth_mode chatgpt with a refresh token)"
  vault_lock
  vault_store codex $name $auth "$(codex_meta $auth)"
  print -r -- "Saved Codex login '$name' ($($AS_JQ -r .email <<< "$(codex_meta $auth)")). Switch with: auth-swap use codex $name"
}

codex_use() { # <name> <no_save:0|1>
  local name=$1 no_save=$2 target live live_meta live_name
  codex_env_check
  vault_init
  [[ -n $(vault_entry codex $name) ]] || as_die "no saved Codex login named '$name' (see: auth-swap list codex)"

  vault_lock
  target=$(vault_secret_get codex $name) || as_die "the saved login '$name' is missing ($AS_HOME/codex/$name.auth.json)"
  codex_validate $target || as_die "the saved login '$name' is damaged"

  # Already active: save its latest tokens and leave the file and the daemon alone
  # (writing the vault copy would replace newer tokens with older ones).
  # An unreadable file is handled below, once the daemon is stopped.
  live=$(codex_read_live) || live=
  if [[ -n $live ]] && live_meta=$(codex_meta $live) \
    && [[ $(vault_name_for_identity codex "$($AS_JQ -r '.identity // ""' <<< $live_meta)") == $name ]]; then
    vault_store codex $name $live $live_meta
    print -r -- "Codex is already using '$name'; its latest tokens are saved."
    return 0
  fi

  # Stop the shared daemon first: it never re-reads auth.json, and with it down
  # nothing can refresh tokens while the file changes.
  if [[ $(codex_daemon_status) == running ]]; then
    AS_CLEANUP+=(codex_daemon_restart_if_needed)
    AS_CODEX_RESTART=1
    $AS_CODEX app-server daemon stop >/dev/null 2>&1 || as_die "could not stop the Codex daemon; nothing was changed"
  fi

  live=$(codex_read_live) || as_die "could not read $(codex_auth_file) as JSON; nothing was changed"
  if [[ -n $live ]]; then
    live_meta=$(codex_meta $live)
    live_name=$(vault_name_for_identity codex "$($AS_JQ -r '.identity // ""' <<< ${live_meta:-'{}'})")
    if [[ -n $live_name ]]; then
      vault_store codex $live_name $live $live_meta
    elif (( ! no_save )); then
      as_die "the active Codex login ($($AS_JQ -r '.email // "unknown account"' <<< ${live_meta:-'{}'})) isn't saved yet. Run 'auth-swap save codex <name>' first, or add --no-save to drop it (it is not revoked)"
    fi
  fi

  print -r -- $target | as_write_atomic $(codex_auth_file) 600 || as_die "could not write $(codex_auth_file)"
  codex_daemon_restart_if_needed
  print -r -- "Codex → $name ($($AS_JQ -r .email <<< "$(codex_meta $target)")). Open Codex windows reconnect within ~2 min; if one says the connection could not be restored, run: codex resume"
}

codex_remove() { # <name>
  vault_init; vault_lock
  [[ -n $(vault_entry codex $1) ]] || as_die "no saved Codex login named '$1'"
  vault_secret_delete codex $1
  vault_remove_entry codex $1 || as_die "could not update $(vault_index)"
  print -r -- "Removed Codex login '$1' from auth-swap (it was not revoked; the active login is unchanged)."
}
