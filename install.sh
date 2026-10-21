#!/bin/zsh -f
# auth-swap installer — run from the auth-swap folder:
#   zsh install.sh              install or update
#   zsh install.sh --uninstall  remove the CLI and plugins (keeps your saved logins)
# Uses only tools that ship with macOS.
emulate -R zsh
setopt no_unset pipe_fail

SRC=${0:A:h}
APP=${AUTH_SWAP_HOME:-$HOME/.auth-swap}/app
BIN=$HOME/.local/bin

die() { print -ru2 -- "install: $*"; exit 1 }
say() { print -r -- "$*" }

for t in /usr/bin/jq /usr/bin/security /usr/bin/shasum /usr/bin/xxd /usr/bin/base64 /usr/bin/perl /usr/bin/awk /usr/bin/stat; do
  [[ -x $t ]] || die "$t is missing. auth-swap needs the tools that ship with macOS (verified on macOS 26.5)."
done
[[ -f $SRC/bin/auth-swap && -d $SRC/plugins ]] || die "run this from the auth-swap folder"

if [[ ${1:-} == --uninstall ]]; then
  if command -v claude >/dev/null; then
    claude plugin uninstall auth-swap@auth-swap >/dev/null 2>&1 && say "Removed the Claude Code plugin."
    claude plugin marketplace remove auth-swap >/dev/null 2>&1
  fi
  if command -v codex >/dev/null; then
    codex plugin remove auth-swap@auth-swap >/dev/null 2>&1 && say "Removed the Codex plugin."
    codex plugin marketplace remove auth-swap >/dev/null 2>&1
  fi
  [[ -L $BIN/auth-swap ]] && rm -f -- $BIN/auth-swap
  rm -rf -- $APP
  say "auth-swap removed. Your saved logins were kept (~/.auth-swap and keychain entries named \"auth-swap\")."
  exit 0
fi

# 1. Copy the app next to the vault, so moving or deleting this folder can't break the plugins.
mkdir -p -m 700 ${APP:h}
rm -rf -- $APP.new && mkdir -p $APP.new || die "cannot write $APP"
cp -R $SRC/bin $SRC/lib $SRC/plugins $APP.new/ || die "copy failed"
rm -rf -- $APP && mv $APP.new $APP || die "cannot move $APP into place"
chmod 755 $APP/bin/auth-swap
mkdir -p $BIN && ln -sf $APP/bin/auth-swap $BIN/auth-swap || die "cannot link $BIN/auth-swap"
say "Installed the auth-swap command: $BIN/auth-swap"
[[ :$PATH: == *:$BIN:* ]] || say "Note: $BIN is not on your PATH. Add it to use 'auth-swap' in a terminal."

# 2. Claude Code plugin (/auth-swap).
if command -v claude >/dev/null; then
  claude plugin marketplace add $APP/plugins/claude >/dev/null 2>&1 \
    || claude plugin marketplace update auth-swap >/dev/null 2>&1
  if claude plugin install auth-swap@auth-swap >/dev/null 2>&1 || claude plugin update auth-swap@auth-swap >/dev/null 2>&1; then
    say "Installed the Claude Code plugin. In open sessions run /reload-plugins; new sessions have /auth-swap."
  else
    say "Could not install the Claude Code plugin automatically. Run:
  claude plugin marketplace add $APP/plugins/claude
  claude plugin install auth-swap@auth-swap"
  fi
else
  say "Claude Code not found; skipped its plugin."
fi

# 3. Codex plugin (skill $auth-swap:auth-swap).
if command -v codex >/dev/null; then
  codex plugin marketplace add $APP/plugins/codex >/dev/null 2>&1
  if codex plugin add auth-swap@auth-swap >/dev/null 2>&1; then
    say "Installed the Codex plugin. In Codex, type \$auth-swap:auth-swap (or pick it from /skills)."
  else
    say "Could not install the Codex plugin automatically. Run:
  codex plugin marketplace add $APP/plugins/codex
  codex plugin add auth-swap@auth-swap"
  fi
else
  say "Codex not found; skipped its plugin."
fi

say "
Next: save the login you're using now, then add others:
  auth-swap save claude <name>      auth-swap login claude <name>
  auth-swap save codex <name>       auth-swap login codex <name>
Never use /logout in Claude Code or Codex: it cancels that login on the server."
