#!/usr/bin/env zsh
# tests/zsh.sh — zsh native completion integration tests
# Run via: docker run --rm -v "$(pwd):/oosh" ohmyzsh/ohmyzsh zsh /oosh/tests/zsh.sh

set -euo pipefail

OOSH_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0 FAIL=0 ERRORS=""

# ---- helpers ----

_assert() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    print "  \033[32m✔\033[0m  $name"
    PASS=$(( PASS + 1 ))
  else
    print "  \033[31m✘\033[0m  $name"
    print "      expected: $expected"
    print "      actual:   $actual"
    FAIL=$(( FAIL + 1 ))
    ERRORS+="  - $name\n"
  fi
}

_assert_contains() {
  local name="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    print "  \033[32m✔\033[0m  $name"
    PASS=$(( PASS + 1 ))
  else
    print "  \033[31m✘\033[0m  $name"
    print "      expected to contain: $needle"
    print "      actual: $haystack"
    FAIL=$(( FAIL + 1 ))
    ERRORS+="  - $name\n"
  fi
}

_print_results() {
  print ""
  print "\033[1m Results \033[0m"
  print ""
  if [[ $FAIL -eq 0 ]]; then
    print "  \033[32m${PASS} passed, 0 failed\033[0m"
    print ""
  else
    print "  \033[32m${PASS} passed\033[0m, \033[31m${FAIL} failed:\033[0m"
    printf "$ERRORS"
    print ""
    exit 1
  fi
}

# ---- setup ----

# compinit is required for compdef to register completions.
# No bashcompinit needed — the native .zcomp.sh uses zsh directly.
autoload -Uz compinit && compinit -u 2>/dev/null

# Generate a test CLI
GEN_DIR="/tmp/_oosh_zsh_test"
rm -rf "$GEN_DIR"
printf "yn" | bash "${OOSH_DIR}/generate.sh" --no-color testcli "${GEN_DIR}" >/dev/null 2>&1
CLI_DIR="${GEN_DIR}/testcli"

export TESTCLI_DIR="${CLI_DIR}"
export TESTCLI_PATH="${CLI_DIR}"
export MODULES_DIR="${CLI_DIR}/modules"

ln -sf "${CLI_DIR}/testcli.sh" "${CLI_DIR}/testcli"
export PATH="${CLI_DIR}:${PATH}"

# Add a module with file and dir flags to test those completion paths
cat > "${CLI_DIR}/modules/files.sh" << 'MODULE'
#!/bin/bash
#@module Files - file, dir and enum completion test
. ${MODULES_DIR}/../oo.sh
#@flag -f|--file FILES_FILE "" file ~ path to a file
#@flag -d|--dir  FILES_DIR  "" dir  ~ path to a directory
#@flag -e|--env  FILES_ENV  "" enum(dev,staging,prod) ~ target environment
#@public ~ test file, dir and enum flags
function test-it() { echo "FILE=${FILES_FILE} DIR=${FILES_DIR} ENV=${FILES_ENV}"; }
main $0 "$@"
MODULE
chmod +x "${CLI_DIR}/modules/files.sh"

cleanup() { rm -rf "$GEN_DIR"; }
trap cleanup EXIT

# ---- 1. completion script loading ----

print ""
print "\033[1m zsh: native completion script loading \033[0m"
print ""

source_ok=false
source "${CLI_DIR}/testcli.zcomp.sh" 2>/dev/null && source_ok=true || true
_assert "zcomp.sh sources without error (no bashcompinit needed)" "true" "$source_ok"

fn_ok=false
( type _testcli >/dev/null 2>&1 ) && fn_ok=true || true
_assert "_testcli completion function is defined" "true" "$fn_ok"

# ---- 2. shortlist — the backbone of tab-completion ----

print ""
print "\033[1m zsh: shortlist (bash subprocess called by completion function) \033[0m"
print ""

_assert_contains "top-level shortlist: lists hello module" "hello" \
  "$(testcli shortlist)"
_assert_contains "top-level shortlist: lists help" "help" \
  "$(testcli shortlist)"
_assert_contains "top-level shortlist: lists install module" "install" \
  "$(testcli shortlist)"
_assert_contains "top-level shortlist: lists files module" "files" \
  "$(testcli shortlist)"

_assert_contains "module shortlist: hello → greet" "greet" \
  "$(testcli shortlist hello)"
_assert_contains "module shortlist: hello → farewell" "farewell" \
  "$(testcli shortlist hello)"

_assert_contains "flag shortlist: greet → --name" "--name" \
  "$(testcli shortlist hello greet)"
_assert_contains "flag shortlist: greet → --uppercase" "--uppercase" \
  "$(testcli shortlist hello greet)"

_assert "file flag shortlist: returns __file__" "__file__" \
  "$(testcli shortlist files test-it --file)"
_assert "dir flag shortlist: returns __dir__" "__dir__" \
  "$(testcli shortlist files test-it --dir)"
_assert_contains "enum flag shortlist: returns dev" "dev" \
  "$(testcli shortlist files test-it --env)"
_assert_contains "enum flag shortlist: returns staging" "staging" \
  "$(testcli shortlist files test-it --env)"
_assert_contains "enum flag shortlist: returns prod" "prod" \
  "$(testcli shortlist files test-it --env)"

# ---- 3. CLI invocations from zsh ----

print ""
print "\033[1m zsh: CLI invocations \033[0m"
print ""

_assert "greet with default name" "Hello, world!" \
  "$(MODULES_DIR="${CLI_DIR}/modules" testcli hello greet)"
_assert "greet with --name" "Hello, oosh!" \
  "$(MODULES_DIR="${CLI_DIR}/modules" testcli hello --name oosh greet)"
_assert "greet with --uppercase" "HELLO, WORLD!" \
  "$(MODULES_DIR="${CLI_DIR}/modules" testcli hello --uppercase greet)"
_assert "farewell" "Goodbye, world!" \
  "$(MODULES_DIR="${CLI_DIR}/modules" testcli hello farewell)"
_assert_contains "help: shows Modules section" "Modules:" \
  "$(MODULES_DIR="${CLI_DIR}/modules" testcli help)"
_assert_contains "module help: shows greet command" "greet" \
  "$(MODULES_DIR="${CLI_DIR}/modules" testcli hello help)"

# ---- 4. native zsh completion simulation ----
#
# We stub compadd and _files so we can call _testcli directly and inspect
# what it would add to the completion list — no interactive terminal needed.
#
# In real interactive zsh:
#   words  = all words typed on the line (1-indexed)
#   CURRENT = index of the word being completed (1-indexed)
#
# ${words[2,$((CURRENT-1))]} correctly gives all fully-typed args after the
# command name — no off-by-one issues since we're native zsh throughout.

print ""
print "\033[1m zsh: native completion simulation (compadd stub) \033[0m"
print ""

# Capture what compadd would add (words passed after --)
typeset -a _compadd_result
compadd() {
  local found=0
  for a in "$@"; do
    [[ "$a" == "--" ]] && { found=1; continue; }
    (( found )) && _compadd_result+=("$a")
  done
  return 0
}

# Capture whether _files or _files -/ was invoked
typeset _files_result=""
_files() {
  [[ "${1:-}" == "-/" ]] && _files_result="__dir__" || _files_result="__file__"
}

_run_native_completion() {
  _compadd_result=()
  _files_result=""
  words=("$@")
  CURRENT=${#words[@]}
  _testcli
}

# Top-level: testcli <TAB>
_run_native_completion "testcli" ""
_assert_contains "top-level: compadd receives hello" "hello" "${_compadd_result[*]:-}"
_assert_contains "top-level: compadd receives help" "help" "${_compadd_result[*]:-}"
_assert_contains "top-level: compadd receives install" "install" "${_compadd_result[*]:-}"

# Module level: testcli hello <TAB>
_run_native_completion "testcli" "hello" ""
_assert_contains "module level: compadd receives greet" "greet" "${_compadd_result[*]:-}"
_assert_contains "module level: compadd receives farewell" "farewell" "${_compadd_result[*]:-}"
_assert_contains "module level: compadd receives help" "help" "${_compadd_result[*]:-}"

# Flag level: testcli hello greet <TAB>
_run_native_completion "testcli" "hello" "greet" ""
_assert_contains "flag level: compadd receives --name" "--name" "${_compadd_result[*]:-}"
_assert_contains "flag level: compadd receives --uppercase" "--uppercase" "${_compadd_result[*]:-}"

# File flag: testcli files test-it --file <TAB>  →  _files called (not compadd)
_run_native_completion "testcli" "files" "test-it" "--file" ""
_assert "file flag: _files is called for file completion" "__file__" "$_files_result"
_assert "file flag: compadd not called" "" "${_compadd_result[*]:-}"

# Dir flag: testcli files test-it --dir <TAB>  →  _files -/ called
_run_native_completion "testcli" "files" "test-it" "--dir" ""
_assert "dir flag: _files -/ is called for dir completion" "__dir__" "$_files_result"
_assert "dir flag: compadd not called" "" "${_compadd_result[*]:-}"

# Enum flag: testcli files test-it --env <TAB>  →  compadd receives enum values
_run_native_completion "testcli" "files" "test-it" "--env" ""
_assert_contains "enum flag: compadd receives dev" "dev" "${_compadd_result[*]:-}"
_assert_contains "enum flag: compadd receives staging" "staging" "${_compadd_result[*]:-}"
_assert_contains "enum flag: compadd receives prod" "prod" "${_compadd_result[*]:-}"
_assert "enum flag: _files not called" "" "$_files_result"

_print_results
