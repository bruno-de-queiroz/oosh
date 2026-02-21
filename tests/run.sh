#!/bin/bash
set -euo pipefail

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

# --- fixtures ---

cat > /tmp/_oosh_test_flags.sh << SCRIPT
#!/bin/bash
. ${OOSH_DIR}/oo.sh

#@flag -v|--verbose VERBOSE "false" boolean ~ enable verbose output
#@flag -p|--port PORT "8080" number ~ server port
#@flag -e|--env ENVIRONMENT "prod" enum(dev,staging,prod) ~ target environment

#@public ~ test boolean flags
#@flag -d|--dry-run DRY_RUN "false" boolean ~ dry run mode
function test-bool() { echo "VERBOSE=\$VERBOSE DRY_RUN=\$DRY_RUN"; }

#@public ~ test enum flags
function test-enum() { echo "ENVIRONMENT=\$ENVIRONMENT"; }

#@public ~ test number flags
function test-number() { echo "PORT=\$PORT"; }

main \$0 "\$@"
SCRIPT

cat > /tmp/_oosh_test_normalize.sh << SCRIPT
#!/bin/bash
. ${OOSH_DIR}/oo.sh

#@public ~ style 1
deploy() {
  echo "deploy"
}

#@public ~ style 2
build(){
  echo "build"
}

#@public ~ style 3
function test-it(){
  echo "test-it"
}

#@public ~ style 4
function release() {
  echo "release"
}

main \$0 "\$@"
SCRIPT

cat > /tmp/_oosh_test_dynamic_enum.sh << SCRIPT
#!/bin/bash
. ${OOSH_DIR}/oo.sh

function _get_envs() { echo "alpha"; echo "beta"; echo "gamma"; }

#@flag -e|--env ENVIRONMENT "" enum(\${_get_envs}) ~ dynamic env

#@public ~ test dynamic enum
function test-it() { echo "ENVIRONMENT=\$ENVIRONMENT"; }

main \$0 "\$@"
SCRIPT

cat > /tmp/_oosh_test_compat.sh << SCRIPT
#!/bin/bash
. ${OOSH_DIR}/oo.sh

#@flag -f|--file FILEPATH "" file
#@description config file path
#@flag -d|--dir DIRPATH "" dir
#@description output directory
#@flag -n|--name NAME "world"
#@description who to greet

#@public
#@description say hello
function greet() { echo "Hello, \${NAME}! file=\${FILEPATH} dir=\${DIRPATH}"; }

main \$0 "\$@"
SCRIPT

cat > /tmp/_oosh_test_versioned.sh << SCRIPT
#!/bin/bash
#@version 2.5.0
. ${OOSH_DIR}/oo.sh

#@public ~ say hi
function greet() { echo "hi"; }

main \$0 "\$@"
SCRIPT

cat > /tmp/_oosh_test_unversioned.sh << SCRIPT
#!/bin/bash
. ${OOSH_DIR}/oo.sh

#@public ~ say hi
function greet() { echo "hi"; }

main \$0 "\$@"
SCRIPT

# Fixture: slow dynamic enum (simulates expensive resolver like kubectl)
cat > /tmp/_oosh_test_slow_enum.sh << SCRIPT
#!/bin/bash
. ${OOSH_DIR}/oo.sh

function _slow_resolver() { sleep 2; echo "a"; echo "b"; }

#@flag -x|--item ITEM "" enum(\${_slow_resolver}) ~ slow resolved enum

#@public ~ test
function test-it() { echo "ITEM=\$ITEM"; }

main \$0 "\$@"
SCRIPT

# Fixture: pure bash baseline (no oosh, just a case statement)
cat > /tmp/_oosh_test_baseline.sh << 'SCRIPT'
#!/bin/bash
case "$1" in
  greet) echo "hello" ;;
  help)  echo "usage: test greet|help" ;;
  *)     echo "usage: test greet|help" ;;
esac
SCRIPT

# Fixture: trace-specific slow module (sleep 0.2 for faster test runs)
cat > /tmp/_oosh_test_trace_slow.sh << SCRIPT
#!/bin/bash
. ${OOSH_DIR}/oo.sh

function _slow_resolver() { sleep 0.2; echo "a"; echo "b"; }

#@flag -x|--item ITEM "" enum(\${_slow_resolver}) ~ slow resolved enum

#@public ~ test
function test-it() { echo "ITEM=\$ITEM"; }

main \$0 "\$@"
SCRIPT

cleanup() {
  rm -f /tmp/_oosh_test_flags.sh /tmp/_oosh_test_normalize.sh /tmp/_oosh_test_dynamic_enum.sh /tmp/_oosh_test_compat.sh /tmp/_oosh_test_versioned.sh /tmp/_oosh_test_unversioned.sh /tmp/_oosh_test_slow_enum.sh /tmp/_oosh_test_baseline.sh /tmp/_oosh_test_trace_slow.sh
  rm -rf /tmp/_oosh_gen_test
}
trap cleanup EXIT

# --- generator fixture ---
_GEN_DIR="/tmp/_oosh_gen_test"
printf "yn" | bash "${OOSH_DIR}/generate.sh" --no-color _testcli "${_GEN_DIR}" >/dev/null 2>&1
_GEN_CLI="${_GEN_DIR}/_testcli"
_run_gen() { env _TESTCLI_DIR="${_GEN_CLI}" MODULES_DIR="${_GEN_CLI}/modules" bash "$@"; }

# ============================================================
printf "\n\033[1m Boolean flags \033[0m\n\n"

_assert "--verbose (no value) sets true" \
  "VERBOSE=true DRY_RUN=false" \
  "$(bash /tmp/_oosh_test_flags.sh --verbose test-bool)"

_assert "--verbose false sets false" \
  "VERBOSE=false DRY_RUN=false" \
  "$(bash /tmp/_oosh_test_flags.sh --verbose false test-bool)"

_assert "--verbose before method sets true without consuming method" \
  "VERBOSE=true DRY_RUN=true" \
  "$(bash /tmp/_oosh_test_flags.sh --verbose test-bool --dry-run)"

_assert "boolean at end of args" \
  "VERBOSE=false DRY_RUN=true" \
  "$(bash /tmp/_oosh_test_flags.sh test-bool --dry-run)"

_assert "boolean default when not provided" \
  "VERBOSE=false DRY_RUN=false" \
  "$(bash /tmp/_oosh_test_flags.sh test-bool)"

_assert "--verbose yes sets yes" \
  "VERBOSE=yes DRY_RUN=false" \
  "$(bash /tmp/_oosh_test_flags.sh --verbose yes test-bool)"

_assert "--verbose 1 sets 1" \
  "VERBOSE=1 DRY_RUN=false" \
  "$(bash /tmp/_oosh_test_flags.sh --verbose 1 test-bool)"

# ============================================================
printf "\n\033[1m Enum flags (static) \033[0m\n\n"

_assert "enum --env staging accepted" \
  "ENVIRONMENT=staging" \
  "$(bash /tmp/_oosh_test_flags.sh --env staging test-enum)"

_assert "enum --env dev accepted" \
  "ENVIRONMENT=dev" \
  "$(bash /tmp/_oosh_test_flags.sh --env dev test-enum)"

_assert_exit "enum --env invalid rejected" 1 \
  bash /tmp/_oosh_test_flags.sh --env invalid test-enum

_assert "enum default value" \
  "ENVIRONMENT=prod" \
  "$(bash /tmp/_oosh_test_flags.sh test-enum)"

# ============================================================
printf "\n\033[1m Enum flags (dynamic) \033[0m\n\n"

_assert "dynamic enum --env beta accepted" \
  "ENVIRONMENT=beta" \
  "$(bash /tmp/_oosh_test_dynamic_enum.sh --env beta test-it)"

_assert_exit "dynamic enum --env invalid rejected" 1 \
  bash /tmp/_oosh_test_dynamic_enum.sh --env invalid test-it

# ============================================================
printf "\n\033[1m Number flags \033[0m\n\n"

_assert "number --port 3000 accepted" \
  "PORT=3000" \
  "$(bash /tmp/_oosh_test_flags.sh --port 3000 test-number)"

_assert "number --port -42 accepted" \
  "PORT=-42" \
  "$(bash /tmp/_oosh_test_flags.sh --port -42 test-number)"

_assert "number --port 3.14 accepted" \
  "PORT=3.14" \
  "$(bash /tmp/_oosh_test_flags.sh --port 3.14 test-number)"

_assert_exit "number --port abc rejected" 1 \
  bash /tmp/_oosh_test_flags.sh --port abc test-number

_assert "number default value" \
  "PORT=8080" \
  "$(bash /tmp/_oosh_test_flags.sh test-number)"

# ============================================================
printf "\n\033[1m Tab completion \033[0m\n\n"

_assert "enum completion returns values" \
  "dev staging prod" \
  "$(bash /tmp/_oosh_test_flags.sh shortlist test-enum --env)"

_assert "dynamic enum completion returns values" \
  "$(printf 'alpha\nbeta\ngamma')" \
  "$(bash /tmp/_oosh_test_dynamic_enum.sh shortlist test-it --env)"

_assert "top-level enum completion returns values" \
  "dev staging prod" \
  "$(bash /tmp/_oosh_test_flags.sh shortlist --env)"

# ============================================================
printf "\n\033[1m Help output \033[0m\n\n"

_assert_contains "help shows enum values in brackets" \
  "[dev, staging, prod]" \
  "$(bash /tmp/_oosh_test_flags.sh help 2>&1)"

_assert_contains "dynamic enum help does not eagerly resolve" \
  "dynamic env" \
  "$(bash /tmp/_oosh_test_dynamic_enum.sh help 2>&1)"

# ============================================================
printf "\n\033[1m Function normalization \033[0m\n\n"

_assert "name() { discovered" \
  "deploy" \
  "$(bash /tmp/_oosh_test_normalize.sh deploy)"

_assert "name(){ discovered" \
  "build" \
  "$(bash /tmp/_oosh_test_normalize.sh build)"

_assert "function name(){ discovered" \
  "test-it" \
  "$(bash /tmp/_oosh_test_normalize.sh test-it)"

_assert "function name() { discovered" \
  "release" \
  "$(bash /tmp/_oosh_test_normalize.sh release)"

_assert_contains "shortlist lists all normalized functions" \
  "deploy" \
  "$(bash /tmp/_oosh_test_normalize.sh shortlist)"

_assert_contains "shortlist lists build" \
  "build" \
  "$(bash /tmp/_oosh_test_normalize.sh shortlist)"

# ============================================================
printf "\n\033[1m Backward compatibility \033[0m\n\n"

_assert "old-style file/dir/#@description flags work" \
  "Hello, Test! file=/etc/hosts dir=/tmp" \
  "$(bash /tmp/_oosh_test_compat.sh --name Test --file /etc/hosts --dir /tmp greet)"

_assert "file completion returns __file__" \
  "__file__" \
  "$(bash /tmp/_oosh_test_compat.sh shortlist greet --file)"

_assert "dir completion returns __dir__" \
  "__dir__" \
  "$(bash /tmp/_oosh_test_compat.sh shortlist greet --dir)"

# ============================================================
printf "\n\033[1m --help / -h \033[0m\n\n"

_assert_contains "--help shows usage" \
  "Usage:" \
  "$(bash /tmp/_oosh_test_flags.sh --help 2>&1)"

_assert_contains "-h shows usage" \
  "Usage:" \
  "$(bash /tmp/_oosh_test_flags.sh -h 2>&1)"

# ============================================================
printf "\n\033[1m --version / -V \033[0m\n\n"

_assert_contains "--version with #@version shows CLI and oosh version" \
  "2.5.0" \
  "$(bash /tmp/_oosh_test_versioned.sh --version)"

_assert_contains "--version shows oosh version" \
  "oosh" \
  "$(bash /tmp/_oosh_test_versioned.sh --version)"

_assert_contains "-V works" \
  "oosh" \
  "$(bash /tmp/_oosh_test_versioned.sh -V)"

_assert_contains "version subcommand works" \
  "2.5.0" \
  "$(bash /tmp/_oosh_test_versioned.sh version)"

_assert_contains "--version without #@version shows only oosh" \
  "(oosh" \
  "$(bash /tmp/_oosh_test_unversioned.sh --version)"

# ============================================================
printf "\n\033[1m Generator: scaffolding \033[0m\n\n"

_assert "creates entry point" "true" \
  "$([[ -f "${_GEN_CLI}/_testcli.sh" ]] && echo true || echo false)"

_assert "creates completion script" "true" \
  "$([[ -f "${_GEN_CLI}/_testcli.comp.sh" ]] && echo true || echo false)"

_assert "copies oo.sh" "true" \
  "$([[ -f "${_GEN_CLI}/oo.sh" ]] && echo true || echo false)"

_assert "creates modules directory" "true" \
  "$([[ -d "${_GEN_CLI}/modules" ]] && echo true || echo false)"

_assert "creates hello.sh module" "true" \
  "$([[ -f "${_GEN_CLI}/modules/hello.sh" ]] && echo true || echo false)"

_assert "creates install.sh module" "true" \
  "$([[ -f "${_GEN_CLI}/modules/install.sh" ]] && echo true || echo false)"

_assert "creates uninstall.sh module" "true" \
  "$([[ -f "${_GEN_CLI}/modules/uninstall.sh" ]] && echo true || echo false)"

_assert "entry point is executable" "true" \
  "$([[ -x "${_GEN_CLI}/_testcli.sh" ]] && echo true || echo false)"

# ============================================================
printf "\n\033[1m Generator: hello module \033[0m\n\n"

_assert "greet with default name" \
  "Hello, world!" \
  "$(_run_gen "${_GEN_CLI}/modules/hello.sh" greet)"

_assert "greet with --name" \
  "Hello, oosh!" \
  "$(_run_gen "${_GEN_CLI}/modules/hello.sh" --name oosh greet)"

_assert "greet with --uppercase" \
  "HELLO, WORLD!" \
  "$(_run_gen "${_GEN_CLI}/modules/hello.sh" --uppercase greet)"

_assert "farewell" \
  "Goodbye, world!" \
  "$(_run_gen "${_GEN_CLI}/modules/hello.sh" farewell)"

_assert_contains "hello help lists greet" \
  "greet" \
  "$(_run_gen "${_GEN_CLI}/modules/hello.sh" help 2>&1)"

_assert_contains "hello help lists farewell" \
  "farewell" \
  "$(_run_gen "${_GEN_CLI}/modules/hello.sh" help 2>&1)"

_assert_contains "hello shortlist returns commands" \
  "greet" \
  "$(_run_gen "${_GEN_CLI}/modules/hello.sh" shortlist)"

# ============================================================
printf "\n\033[1m Generator: update flow \033[0m\n\n"

# Tamper with oo.sh to verify update replaces it
echo "# tampered" >> "${_GEN_CLI}/oo.sh"
printf "y" | bash "${OOSH_DIR}/generate.sh" --no-color _testcli "${_GEN_DIR}" >/dev/null 2>&1

_assert "update restores oo.sh" "false" \
  "$(grep -q '# tampered' "${_GEN_CLI}/oo.sh" 2>/dev/null && echo true || echo false)"

_assert "modules untouched after update" "true" \
  "$([[ -f "${_GEN_CLI}/modules/hello.sh" ]] && echo true || echo false)"

# ============================================================
printf "\n\033[1m Performance \033[0m\n\n"

# Baseline: pure bash, no framework
_assert_perf "baseline: pure bash case dispatch" 150 \
  bash /tmp/_oosh_test_baseline.sh greet

# Core operations
_assert_perf "shortlist (command listing)" 150 \
  bash /tmp/_oosh_test_flags.sh shortlist

_assert_perf "help output" 150 \
  bash /tmp/_oosh_test_flags.sh help

_assert_perf "flag parsing: boolean" 150 \
  bash /tmp/_oosh_test_flags.sh --verbose test-bool

_assert_perf "flag parsing: enum + number" 150 \
  bash /tmp/_oosh_test_flags.sh --env dev --port 3000 test-number

_assert_perf "flag parsing: all types combined" 150 \
  bash /tmp/_oosh_test_flags.sh --verbose --env staging --port 9090 test-bool

_assert_perf "shortlist: enum flag completion" 150 \
  bash /tmp/_oosh_test_flags.sh shortlist test-enum --env

_assert_perf "shortlist: file flag completion" 150 \
  bash /tmp/_oosh_test_compat.sh shortlist greet --file

# Dynamic enum: lazy resolution must NOT call the slow resolver
_assert_perf "dynamic enum: shortlist (no flag)" 150 \
  bash /tmp/_oosh_test_slow_enum.sh shortlist

_assert_perf "dynamic enum: help (no eager resolve)" 150 \
  bash /tmp/_oosh_test_slow_enum.sh help

_assert_perf "dynamic enum: dispatch without flag" 150 \
  bash /tmp/_oosh_test_slow_enum.sh test-it

# Function normalization overhead
_assert_perf "normalized functions: shortlist" 150 \
  bash /tmp/_oosh_test_normalize.sh shortlist

_assert_perf "normalized functions: dispatch" 150 \
  bash /tmp/_oosh_test_normalize.sh deploy

# Generated module
_assert_perf "generated module: greet" 150 \
  env _TESTCLI_DIR="${_GEN_CLI}" MODULES_DIR="${_GEN_CLI}/modules" bash "${_GEN_CLI}/modules/hello.sh" greet

_assert_perf "generated module: shortlist" 150 \
  env _TESTCLI_DIR="${_GEN_CLI}" MODULES_DIR="${_GEN_CLI}/modules" bash "${_GEN_CLI}/modules/hello.sh" shortlist

_assert_perf "generated module: help" 150 \
  env _TESTCLI_DIR="${_GEN_CLI}" MODULES_DIR="${_GEN_CLI}/modules" bash "${_GEN_CLI}/modules/hello.sh" help

# ============================================================
printf "\n\033[1m Trace \033[0m\n\n"

_trace_out=$(bash "${OOSH_DIR}/trace.sh" --no-color /tmp/_oosh_test_flags.sh -r 1 -t 200 2>&1) && _trace_rc=$? || _trace_rc=$?
_assert "trace: fast module exits 0" "0" "$_trace_rc"
_assert_contains "trace: output contains Shortlist header" "Shortlist" "$_trace_out"
_assert_contains "trace: output contains Help header" "Help" "$_trace_out"
_assert_contains "trace: output shows shortlist lines" "shortlist" "$_trace_out"

_trace_out=$(bash "${OOSH_DIR}/trace.sh" --no-color /tmp/_oosh_test_trace_slow.sh -t 50 -r 1 2>&1) && _trace_rc=$? || _trace_rc=$?
_assert "trace: slow enum exits 1 when exceeding threshold" "1" "$_trace_rc"
_assert_contains "trace: output shows warning count" "warning" "$_trace_out"

_trace_out=$(env _TESTCLI_DIR="${_GEN_CLI}" bash "${OOSH_DIR}/trace.sh" --no-color "${_GEN_CLI}/_testcli.sh" -r 1 -t 200 2>&1) && _trace_rc=$? || _trace_rc=$?
_assert "trace: generated multi-module CLI exits 0" "0" "$_trace_rc"

_trace_out=$(env _TESTCLI_DIR="${_GEN_CLI}" bash "${OOSH_DIR}/trace.sh" --no-color "${_GEN_CLI}/_testcli.sh" hello -r 1 2>&1) && _trace_rc=$? || _trace_rc=$?
_assert_contains "trace: scoped to hello shows hello commands" "shortlist hello" "$_trace_out"
_assert_not_contains "trace: scoped to hello excludes install" "shortlist install" "$_trace_out"

_trace_out=$(env _TESTCLI_DIR="${_GEN_CLI}" bash "${OOSH_DIR}/trace.sh" --no-color "${_GEN_CLI}/_testcli.sh" hello greet -r 1 2>&1) && _trace_rc=$? || _trace_rc=$?
_assert_contains "trace: scoped to greet shows greet" "shortlist hello greet" "$_trace_out"
_assert_not_contains "trace: scoped to greet excludes farewell" "shortlist hello farewell" "$_trace_out"

# ============================================================
printf "\n\033[1m Results \033[0m\n\n"

if [[ $FAIL -eq 0 ]]; then
  printf "  \033[32m%d passed, 0 failed\033[0m\n\n" "$PASS"
else
  printf "  \033[32m%d passed\033[0m, \033[31m%d failed:\033[0m\n" "$PASS" "$FAIL"
  printf "%s\n" "$ERRORS"
  exit 1
fi
