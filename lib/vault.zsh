# auth-swap — the vault: saved logins per provider.
#   $AS_HOME/accounts.json          index, no secrets (0600)
#   keychain "auth-swap" / claude:<name>   Claude login snapshot (Claude keeps its login in the keychain)
#   $AS_HOME/codex/<name>.auth.json        Codex auth.json copy (Codex keeps its login in a 0600 file)

typeset -g AS_VAULT_KC_SERVICE=auth-swap

vault_index() { print -r -- $AS_HOME/accounts.json }

vault_init() {
  mkdir -p -m 700 -- $AS_HOME $AS_HOME/codex || as_die "cannot create $AS_HOME"
  chmod 700 $AS_HOME $AS_HOME/codex
  [[ -f $(vault_index) ]] || print -r -- '{"version":1,"accounts":[]}' | as_write_atomic $(vault_index) 600 \
    || as_die "cannot write $(vault_index)"
}

vault_lock() {
  as_lock_acquire $AS_HOME/.lock 300 30 || as_die "another auth-swap command is running (lock $AS_HOME/.lock)"
}

vault_entries() { # [provider] -> JSON array
  $AS_JQ -c --arg p "${1:-}" '[.accounts[] | select($p == "" or .provider == $p)]' $(vault_index)
}

vault_entry() { # <provider> <name> -> JSON object or nothing
  $AS_JQ -c --arg p $1 --arg n $2 '.accounts[] | select(.provider == $p and .name == $n)' $(vault_index)
}

vault_name_for_identity() { # <provider> <identity> -> name or nothing
  $AS_JQ -r --arg p $1 --arg i $2 '.accounts[] | select(.provider == $p and .identity == $i) | .name' $(vault_index)
}

vault_upsert() { # <entry-json>; keeps addedAt of an existing entry
  local entry=$1 out
  out=$($AS_JQ --argjson e $entry --arg now "$(as_now_iso)" '
    .accounts as $a
    | ([$a[] | select(.provider == $e.provider and .name == $e.name)][0]) as $old
    | .accounts = ([$a[] | select((.provider == $e.provider and .name == $e.name) | not)]
                   + [$e + {addedAt: ($old.addedAt // $now), updatedAt: $now}])
  ' $(vault_index)) || return 1
  print -r -- $out | as_write_atomic $(vault_index) 600
}

vault_remove_entry() { # <provider> <name>
  local out
  out=$($AS_JQ --arg p $1 --arg n $2 '.accounts |= map(select((.provider == $p and .name == $n) | not))' $(vault_index)) || return 1
  print -r -- $out | as_write_atomic $(vault_index) 600
}

vault_secret_put() { # <provider> <name> <secret>
  case $1 in
    claude) as_kc_write $AS_VAULT_KC_SERVICE "claude:$2" "$3" ;;
    codex) print -r -- "$3" | as_write_atomic $AS_HOME/codex/$2.auth.json 600 ;;
  esac
}

vault_secret_get() { # <provider> <name> -> secret on stdout
  case $1 in
    claude) as_kc_read $AS_VAULT_KC_SERVICE "claude:$2" ;;
    codex) cat -- $AS_HOME/codex/$2.auth.json 2>/dev/null ;;
  esac
}

vault_secret_delete() { # <provider> <name>
  case $1 in
    claude) as_kc_delete $AS_VAULT_KC_SERVICE "claude:$2" ;;
    codex) rm -f -- $AS_HOME/codex/$2.auth.json ;;
  esac
}

# Store a snapshot under <name>. Refuses if the same account is already saved
# under a different name. <meta-json> carries identity/email/plan/org/...
vault_store() { # <provider> <name> <secret> <meta-json>
  local provider=$1 name=$2 secret=$3 meta=$4 identity other
  identity=$($AS_JQ -r '.identity' <<< $meta)
  [[ -n $identity && $identity != null ]] || as_die "could not work out which account this login belongs to"
  other=$(vault_name_for_identity $provider $identity)
  [[ -z $other || $other == $name ]] || as_die "this $provider account is already saved as '$other'"
  other=$($AS_JQ -r '.identity // empty' <<< "$(vault_entry $provider $name)")
  [[ -z $other || $other == $identity ]] \
    || as_die "'$name' already holds a different $provider account; run 'auth-swap remove $provider $name' first"
  vault_secret_put $provider $name "$secret" || as_die "could not save the $provider login '$name'"
  vault_upsert "$($AS_JQ -c --arg p $provider --arg n $name '. + {provider: $p, name: $n}' <<< $meta)" \
    || as_die "could not update $(vault_index)"
}

# `save` stores the login that is active now; point at `login` when that account is already saved.
vault_refuse_saved_elsewhere() { # <provider> <name> <meta-json>
  local other
  other=$(vault_name_for_identity $1 "$($AS_JQ -r '.identity // ""' <<< $3)")
  [[ -z $other || $other == $2 ]] && return 0
  as_die "the ${(C)1} account you're logged into now ($($AS_JQ -r '.email // "unknown"' <<< $3)) is already saved as '$other'.
'save' stores the account that is active right now. To add a different account, run: auth-swap login $1 $2"
}
