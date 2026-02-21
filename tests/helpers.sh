# tests/helpers.sh — shared assert functions, sourced by each suite

OOSH_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0 FAIL=0 ERRORS=""

_assert() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf "  \033[32m✔\033[0m  %s\n" "$name"
    PASS=$((PASS + 1))
  else
    printf "  \033[31m✘\033[0m  %s\n" "$name"
    printf "      expected: %s\n" "$expected"
    printf "      actual:   %s\n" "$actual"
    FAIL=$((FAIL + 1))
    ERRORS+="  - $name"$'\n'
  fi
}

_assert_contains() {
  local name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    printf "  \033[32m✔\033[0m  %s\n" "$name"
    PASS=$((PASS + 1))
  else
    printf "  \033[31m✘\033[0m  %s\n" "$name"
    printf "      expected to contain: %s\n" "$needle"
    printf "      actual:              %s\n" "$haystack"
    FAIL=$((FAIL + 1))
    ERRORS+="  - $name"$'\n'
  fi
}

_assert_not_contains() {
  local name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf "  \033[32m✔\033[0m  %s\n" "$name"
    PASS=$((PASS + 1))
  else
    printf "  \033[31m✘\033[0m  %s\n" "$name"
    printf "      expected NOT to contain: %s\n" "$needle"
    FAIL=$((FAIL + 1))
    ERRORS+="  - $name"$'\n'
  fi
}

_assert_exit() {
  local name="$1" expected_exit="$2"; shift 2
  local out
  out=$("$@" 2>&1) && local rc=$? || local rc=$?
  if [[ "$rc" -eq "$expected_exit" ]]; then
    printf "  \033[32m✔\033[0m  %s\n" "$name"
    PASS=$((PASS + 1))
  else
    printf "  \033[31m✘\033[0m  %s\n" "$name"
    printf "      expected exit: %s\n" "$expected_exit"
    printf "      actual exit:   %s\n" "$rc"
    printf "      output:        %s\n" "$out"
    FAIL=$((FAIL + 1))
    ERRORS+="  - $name"$'\n'
  fi
}

# Millisecond timestamp (portable: macOS bash 3.2 + Linux)
_ms() { perl -MTime::HiRes=time -e 'printf "%.0f\n", time * 1000' 2>/dev/null \
     || python3 -c 'import time; print(int(time.time()*1000))'; }

_assert_perf() {
  local name="$1" max_ms="$2"; shift 2
  local t0 t1 elapsed
  t0=$(_ms)
  "$@" >/dev/null 2>&1
  t1=$(_ms)
  elapsed=$((t1 - t0))
  if [[ "$elapsed" -le "$max_ms" ]]; then
    printf "  \033[32m✔\033[0m  %-52s \033[2m%4dms\033[0m\n" "$name" "$elapsed"
    PASS=$((PASS + 1))
  else
    printf "  \033[31m✘\033[0m  %-52s \033[31m%4dms (max: %dms)\033[0m\n" "$name" "$elapsed" "$max_ms"
    FAIL=$((FAIL + 1))
    ERRORS+="  - $name (${elapsed}ms > ${max_ms}ms)"$'\n'
  fi
}

_print_results() {
  printf "\n\033[1m Results \033[0m\n\n"
  if [[ $FAIL -eq 0 ]]; then
    printf "  \033[32m%d passed, 0 failed\033[0m\n\n" "$PASS"
  else
    printf "  \033[32m%d passed\033[0m, \033[31m%d failed:\033[0m\n" "$PASS" "$FAIL"
    printf "%s\n" "$ERRORS"
    exit 1
  fi
}
