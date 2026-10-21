#!/bin/zsh -f
# auth-swap installer — run from the auth-swap folder:
#   zsh install.sh              install or update
#   zsh install.sh --uninstall  remove the command (keeps your saved logins)
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
[[ -f $SRC/bin/auth-swap && -d $SRC/lib ]] || die "run this from the auth-swap folder"

# auth-swap 0.1.0 installed a Claude Code plugin and a Codex plugin; remove them if present.
remove_old_plugins() {
  if command -v claude >/dev/null \
    && /usr/bin/jq -e '.plugins | keys | any(startswith("auth-swap@"))' $HOME/.claude/plugins/installed_plugins.json >/dev/null 2>&1; then
    claude plugin uninstall auth-swap@auth-swap >/dev/null 2>&1 && say "Removed the old auth-swap Claude Code plugin."
    claude plugin marketplace remove auth-swap >/dev/null 2>&1
  fi
  if command -v codex >/dev/null && grep -q '^\[plugins\."auth-swap@' $HOME/.codex/config.toml 2>/dev/null; then
    codex plugin remove auth-swap@auth-swap >/dev/null 2>&1 && say "Removed the old auth-swap Codex plugin."
    codex plugin marketplace remove auth-swap >/dev/null 2>&1
  fi
  return 0
}

if [[ ${1:-} == --uninstall ]]; then
  remove_old_plugins
  [[ -L $BIN/auth-swap ]] && rm -f -- $BIN/auth-swap
  rm -rf -- $APP
  say "auth-swap removed. Your saved logins were kept (~/.auth-swap and keychain entries named \"auth-swap\")."
  exit 0
fi

# Copy the app next to the vault, so moving or deleting this folder can't break the command.
mkdir -p -m 700 ${APP:h}
rm -rf -- $APP.new && mkdir -p $APP.new || die "cannot write $APP"
cp -R $SRC/bin $SRC/lib $APP.new/ || die "copy failed"
rm -rf -- $APP && mv $APP.new $APP || die "cannot move $APP into place"
chmod 755 $APP/bin/auth-swap
mkdir -p $BIN && ln -sf $APP/bin/auth-swap $BIN/auth-swap || die "cannot link $BIN/auth-swap"
say "Installed the auth-swap command: $BIN/auth-swap"
[[ :$PATH: == *:$BIN:* ]] || say "Note: $BIN is not on your PATH. Add it to use 'auth-swap' in a terminal."

remove_old_plugins

say "
Next: save the login you're using now, then add others:
  auth-swap save claude <name>      auth-swap login claude <name>
  auth-swap save codex <name>       auth-swap login codex <name>
Never use /logout in Claude Code or Codex: it cancels that login on the server."
