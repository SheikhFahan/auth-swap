#!/bin/zsh -f
# Plain zsh test runner (no frameworks: only what macOS ships).
# Usage: zsh tests/run.zsh [pattern]
emulate -R zsh
setopt extended_glob

typeset -g ROOT=${0:A:h:h}
local pattern=${1:-}
local -i pass=0 fail=0
local f t out
local -a failed=()

for f in $ROOT/tests/*.test.zsh; do
  for t in $(zsh -f -c "source ${(q)f}; print -l \${(ok)functions[(I)test_*]}"); do
    [[ -n $pattern && $t != *$pattern* ]] && continue
    out=$(zsh -f -c "source ${(q)ROOT}/tests/lib.zsh; t_setup; source ${(q)f}; $t; t_teardown" 2>&1)
    if (( $? == 0 )); then
      pass+=1; print -r -- "ok    ${f:t:r}::$t"
    else
      fail+=1; failed+=("${f:t:r}::$t"); print -r -- "FAIL  ${f:t:r}::$t"; print -r -- "$out" | sed 's/^/      /'
    fi
  done
done

print -r -- "
$pass passed, $fail failed"
(( fail == 0 ))
