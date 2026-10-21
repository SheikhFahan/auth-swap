# auth-swap — shared helpers. Sourced by bin/auth-swap; zsh only.
# Uses only tools shipped with macOS (see README "Requirements").

typeset -g AS_JQ=${AUTH_SWAP_JQ:-/usr/bin/jq}
typeset -g AS_SECURITY=${AUTH_SWAP_SECURITY:-/usr/bin/security}
typeset -g AS_HOME=${AUTH_SWAP_HOME:-$HOME/.auth-swap}
typeset -ga AS_HELD_LOCKS=()
typeset -ga AS_CLEANUP=()

as_die() { print -ru2 -- "auth-swap: $*"; exit 1 }
as_warn() { print -ru2 -- "auth-swap: $*" }

as_require_tools() {
  local t
  for t in $AS_JQ $AS_SECURITY /usr/bin/shasum /usr/bin/mktemp /usr/bin/xxd /usr/bin/base64 /usr/bin/stat; do
    [[ -x $t ]] || as_die "required tool missing: $t (auth-swap needs the tools that ship with macOS)"
  done
}

as_valid_name() { [[ $1 =~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$' ]] }

as_now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ }

as_rand_hex() { head -c ${1:-6} /dev/urandom | /usr/bin/xxd -p | tr -d '\n' }

as_sha8() { print -rn -- "$1" | /usr/bin/shasum -a 256 | cut -c1-8 }

as_to_hex() { /usr/bin/xxd -p | tr -d '\n' }

# Decode the payload of a JWT (base64url) to JSON on stdout.
as_jwt_payload() {
  local p=${${1#*.}%%.*}
  p=${p//-/+}; p=${p//_//}
  while (( ${#p} % 4 )); do p+='='; done
  print -rn -- "$p" | /usr/bin/base64 -d 2>/dev/null
}

as_mktemp_dir() { local base=${TMPDIR:-/tmp}; /usr/bin/mktemp -d "${base:A}/auth-swap.XXXXXX" }

# Write stdin to $1 atomically: temp file next to the target, chmod $2, rename.
as_write_atomic() {
  local target=$1 mode=${2:-600} tmp
  tmp="$target.tmp.$$.$(as_rand_hex 6)"
  ( umask 077; cat >| $tmp ) || { rm -f -- $tmp; return 1 }
  chmod $mode $tmp && mv -f -- $tmp $target || { rm -f -- $tmp; return 1 }
}

# ---- mkdir locks, compatible with proper-lockfile (what Claude Code uses) ----
# A lock is the directory <path>. It is stale when its mtime is older than the
# stale time; a stale lock is removed and the acquire retried. Holders refresh
# the mtime (as_locks_touch) so others don't treat them as stale.

as_lock_acquire() { # <lockdir> <stale-seconds> <timeout-seconds>
  local dir=$1 stale=$2 timeout=$3 start=$SECONDS mtime
  while true; do
    if mkdir -- $dir 2>/dev/null; then
      AS_HELD_LOCKS+=($dir)
      return 0
    fi
    mtime=$(/usr/bin/stat -f %m -- $dir 2>/dev/null) || mtime=
    if [[ -n $mtime ]] && (( $(date +%s) - mtime > stale )); then
      rmdir -- $dir 2>/dev/null
      continue
    fi
    (( SECONDS - start >= timeout )) && return 1
    sleep 0.2
  done
}

as_lock_release() { # <lockdir>
  rmdir -- $1 2>/dev/null
  AS_HELD_LOCKS=(${AS_HELD_LOCKS:#$1})
}

as_locks_touch() { local d; for d in $AS_HELD_LOCKS; do touch -- $d 2>/dev/null; done }

as_release_all_locks() {
  local i
  for (( i = ${#AS_HELD_LOCKS}; i > 0; i-- )); do rmdir -- ${AS_HELD_LOCKS[i]} 2>/dev/null; done
  AS_HELD_LOCKS=()
}

as_run_cleanup() {
  local c
  for c in $AS_CLEANUP; do eval "$c" 2>/dev/null; done
  AS_CLEANUP=()
  as_release_all_locks
}

# ---- keychain (generic passwords), written the way Claude Code writes them ----
# Values go through `security -i` on stdin when the whole command is <= 4032
# chars (longer lines get split and store a truncated value; seen on macOS 26.5),
# otherwise through argv.

as_kc_read() { # <service> <account>  -> secret on stdout; returns security's exit code (44 = not found)
  # `security -w` prints a value holding non-ASCII bytes as hex (seen on macOS 26.5); our
  # values are JSON objects, which never look like hex, so decode that form back.
  local out rc
  out=$($AS_SECURITY find-generic-password -a $2 -s $1 -w 2>/dev/null) || { rc=$?; return $rc }
  if [[ $out =~ '^([0-9a-f][0-9a-f])+$' ]]; then
    print -rn -- $out | /usr/bin/xxd -r -p
    print
  else
    print -r -- $out
  fi
}

as_kc_write() { # <service> <account> <value>
  local svc=$1 acct=$2 hex cmd
  [[ $svc != *'"'* && $acct != *'"'* ]] || as_die "keychain name contains a quote: $svc / $acct"
  hex=$(print -rn -- "$3" | as_to_hex)
  cmd="add-generic-password -U -a \"$acct\" -s \"$svc\" -X \"$hex\""
  if (( ${#cmd} <= 4032 )); then
    print -r -- "$cmd" | $AS_SECURITY -i >/dev/null 2>&1
  else
    $AS_SECURITY add-generic-password -U -a $acct -s $svc -X $hex >/dev/null 2>&1
  fi
}

as_kc_delete() { # <service> <account>; succeeds if the item is gone afterwards
  $AS_SECURITY delete-generic-password -a $2 -s $1 >/dev/null 2>&1
  local rc=$?
  (( rc == 0 || rc == 44 ))
}
