# install.sh and `auth-swap uninstall`, under the fake HOME.

test_uninstall_from_any_folder_keeps_saved_logins() {
  claude_live_setup a
  zsh -f $ROOT/install.sh >/dev/null || fail "install failed"
  [[ -L $HOME/.local/bin/auth-swap ]] || fail "install did not link the command"
  $HOME/.local/bin/auth-swap save claude work >/dev/null || fail "save failed"
  out=$(cd / && $HOME/.local/bin/auth-swap uninstall) || fail "uninstall failed: $out"
  assert_contains "$out" "saved logins were kept"
  [[ ! -e $HOME/.local/bin/auth-swap && ! -L $HOME/.local/bin/auth-swap ]] || fail "command link still there"
  [[ ! -e $HOME/.auth-swap/app ]] || fail "app folder still there"
  [[ -f $HOME/.auth-swap/accounts.json ]] || fail "accounts.json was removed"
  kc_has auth-swap claude:work || fail "saved login was removed from the keychain"
  kc_has "Claude Code-credentials" || fail "live login was touched"
  [[ -f $ROOT/install.sh ]] || fail "repo was touched"
}

test_uninstall_leaves_a_foreign_command_link() {
  mkdir -p $HOME/.local/bin $HOME/elsewhere
  print '#!/bin/sh' > $HOME/elsewhere/auth-swap
  ln -s $HOME/elsewhere/auth-swap $HOME/.local/bin/auth-swap
  as uninstall >/dev/null || fail "uninstall failed"
  [[ -L $HOME/.local/bin/auth-swap ]] || fail "removed a link auth-swap did not create"
}
