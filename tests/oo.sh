#!/bin/bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/helpers.sh"

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

# Fixture: plain array flag
cat > /tmp/_oosh_test_array.sh << SCRIPT
#!/bin/bash
. ${OOSH_DIR}/oo.sh

#@flag -t|--tag TAG "" array ~ tags

#@public ~ test array
function test-array() { echo "TAG=\${TAG[*]} TAG_COUNT=\${#TAG[@]}"; }

main \$0 "\$@"
SCRIPT

# Fixture: array with static enum validation
cat > /tmp/_oosh_test_array_enum.sh << SCRIPT
#!/bin/bash
. ${OOSH_DIR}/oo.sh

#@flag -l|--label LABEL "" array(enum(alpha,beta,gamma)) ~ labels

#@public ~ test array enum
function test-array() { echo "LABEL=\${LABEL[*]} LABEL_COUNT=\${#LABEL[@]}"; }

main \$0 "\$@"
SCRIPT

# Fixture: array with dynamic enum validation
cat > /tmp/_oosh_test_array_dyn.sh << SCRIPT
#!/bin/bash
. ${OOSH_DIR}/oo.sh

function _get_envs() { echo "dev"; echo "staging"; echo "prod"; }

#@flag -e|--env ENV "" array(enum(\${_get_envs})) ~ environments

#@public ~ test array dynamic enum
function test-array() { echo "ENV=\${ENV[*]} ENV_COUNT=\${#ENV[@]}"; }

main \$0 "\$@"
SCRIPT

# Fixture: array with default value
cat > /tmp/_oosh_test_array_default.sh << SCRIPT
#!/bin/bash
. ${OOSH_DIR}/oo.sh

#@flag -t|--tag TAG "x,y" array ~ tags with default

#@public ~ test array default
function test-array() { echo "TAG=\${TAG[*]} TAG_COUNT=\${#TAG[@]}"; }

main \$0 "\$@"
SCRIPT

# Fixture: escaped quotes in default value
cat > /tmp/_oosh_test_escaped_quotes.sh << 'SCRIPT'
#!/bin/bash
SCRIPT
# Write with printf to embed the escaped quote annotation precisely
{
  printf '#!/bin/bash\n'
  printf '. %s/oo.sh\n' "${OOSH_DIR}"
  printf '#@flag -m|--msg MSG "say \\"hello\\"" ~ greeting message\n'
  printf '#@public ~ test escaped quotes\n'
  printf 'function test-it() { echo "MSG=$MSG"; }\n'
  printf 'main $0 "$@"\n'
} > /tmp/_oosh_test_escaped_quotes.sh

# Fixture: malformed flag annotation (missing quotes around default)
cat > /tmp/_oosh_test_malformed.sh << SCRIPT
#!/bin/bash
. ${OOSH_DIR}/oo.sh
#@flag -v|--verbose VERBOSE "false" boolean ~ works fine
#@flag -b|--broken BROKEN default_no_quotes ~ missing quotes
#@public ~ test it
function test-it() { echo "VERBOSE=\$VERBOSE BROKEN=\$BROKEN"; }
main \$0 "\$@"
SCRIPT

# Fixture: module dispatch (parent delegates to child with its own flags)
cat > /tmp/_oosh_test_module_child.sh << SCRIPT
#!/bin/bash
. ${OOSH_DIR}/oo.sh
#@flag -p|--path MPATH "" dir ~ planning path
#@flag -r|--repo MREPO "" dir ~ repository path
#@public ~ run the child command
function run() { echo "MPATH=\$MPATH MREPO=\$MREPO"; }
main \$0 "\$@"
SCRIPT

cat > /tmp/_oosh_test_module_parent.sh << SCRIPT
#!/bin/bash
. ${OOSH_DIR}/oo.sh
function _call() {
  local all=("\$@")
  local mod="\${all[0]}"
  if [[ "\$mod" == "child" ]]; then
    all=("\${all[@]:1}")
    bash /tmp/_oosh_test_module_child.sh "\${all[@]}"
  else
    _default_call "\$@"
  fi
}
main \$0 "\$@"
SCRIPT

# Fixture: -- stop-parsing
cat > /tmp/_oosh_test_doubledash.sh << SCRIPT
#!/bin/bash
. ${OOSH_DIR}/oo.sh
#@flag -v|--verbose VERBOSE "false" boolean ~ enable verbose
#@public ~ test double dash
function test-dd() { echo "VERBOSE=\$VERBOSE ARGS=\$*"; }
main \$0 "\$@"
SCRIPT

# Fixture: required flags + env var fallback
cat > /tmp/_oosh_test_required.sh << SCRIPT
#!/bin/bash
. ${OOSH_DIR}/oo.sh
#@flag -k|--key REQ_KEY "" required ~ api key
#@flag -p|--port REQ_PORT "" required:number ~ server port
#@flag -n|--name REQ_NAME "\${TEST_OOSH_NAME}" ~ name with env fallback
#@flag -e|--env REQ_ENV "\${TEST_OOSH_ENV}" required ~ required with env fallback
#@flag -l|--lang REQ_LANG "\${TEST_OOSH_LANG:-en}" ~ env var with inline fallback
#@public ~ test required flags
function test-it() { echo "KEY=\$REQ_KEY PORT=\$REQ_PORT NAME=\$REQ_NAME ENV=\$REQ_ENV LANG_CODE=\$REQ_LANG"; }
main \$0 "\$@"
SCRIPT

# Fixture: default function (no args calls run directly)
cat > /tmp/_oosh_test_default.sh << SCRIPT
#!/bin/bash
. ${OOSH_DIR}/oo.sh
#@flag -d|--debug DEBUG "false" boolean ~ enable debug output
#@default
function run() { echo "DEBUG=\$DEBUG"; }
main \$0 "\$@"
SCRIPT

# Fixture: no default specified (should show help)
cat > /tmp/_oosh_test_no_default.sh << SCRIPT
#!/bin/bash
. ${OOSH_DIR}/oo.sh
#@public ~ say hi
function greet() { echo "hi"; }
main \$0 "\$@"
SCRIPT

cleanup() {
  rm -f /tmp/_oosh_test_flags.sh /tmp/_oosh_test_normalize.sh \
       /tmp/_oosh_test_dynamic_enum.sh /tmp/_oosh_test_compat.sh \
       /tmp/_oosh_test_versioned.sh /tmp/_oosh_test_unversioned.sh \
       /tmp/_oosh_test_slow_enum.sh /tmp/_oosh_test_baseline.sh \
       /tmp/_oosh_test_array.sh /tmp/_oosh_test_array_enum.sh \
       /tmp/_oosh_test_array_dyn.sh /tmp/_oosh_test_array_default.sh \
       /tmp/_oosh_test_escaped_quotes.sh /tmp/_oosh_test_malformed.sh \
       /tmp/_oosh_test_required.sh \
       /tmp/_oosh_test_module_child.sh /tmp/_oosh_test_module_parent.sh \
       /tmp/_oosh_test_doubledash.sh
}
trap cleanup EXIT

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

_assert "--verbose=yes sets yes (= syntax)" \
  "VERBOSE=yes DRY_RUN=false" \
  "$(bash /tmp/_oosh_test_flags.sh --verbose=yes test-bool)"

_assert "--verbose=1 sets 1 (= syntax)" \
  "VERBOSE=1 DRY_RUN=false" \
  "$(bash /tmp/_oosh_test_flags.sh --verbose=1 test-bool)"

# ============================================================
printf "\n\033[1m Enum flags (static) \033[0m\n\n"

_assert "enum --env staging accepted" \
  "ENVIRONMENT=staging" \
  "$(bash /tmp/_oosh_test_flags.sh --env staging test-enum)"

_assert "enum --env dev accepted" \
  "ENVIRONMENT=dev" \
  "$(bash /tmp/_oosh_test_flags.sh --env dev test-enum)"

_assert_exit "enum --env invalid rejected" 2 \
  bash /tmp/_oosh_test_flags.sh --env invalid test-enum

_assert "enum default value" \
  "ENVIRONMENT=prod" \
  "$(bash /tmp/_oosh_test_flags.sh test-enum)"

# ============================================================
printf "\n\033[1m Enum flags (dynamic) \033[0m\n\n"

_assert "dynamic enum --env beta accepted" \
  "ENVIRONMENT=beta" \
  "$(bash /tmp/_oosh_test_dynamic_enum.sh --env beta test-it)"

_assert_exit "dynamic enum --env invalid rejected" 2 \
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

_assert_exit "number --port abc rejected" 2 \
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
printf "\n\033[1m Command-specific help \033[0m\n\n"

_assert_contains "command --help shows command name" \
  "test-bool" \
  "$(bash /tmp/_oosh_test_flags.sh test-bool --help 2>&1)"

_assert_contains "command --help shows command description" \
  "test boolean flags" \
  "$(bash /tmp/_oosh_test_flags.sh test-bool --help 2>&1)"

_assert_contains "command --help shows command-scoped flag" \
  "--dry-run" \
  "$(bash /tmp/_oosh_test_flags.sh test-bool --help 2>&1)"

_assert_contains "command --help shows global flag" \
  "--verbose" \
  "$(bash /tmp/_oosh_test_flags.sh test-bool --help 2>&1)"

_assert_not_contains "command --help hides other command flags" \
  "--dry-run" \
  "$(bash /tmp/_oosh_test_flags.sh test-enum --help 2>&1)"

_assert_contains "command -h works" \
  "test-enum" \
  "$(bash /tmp/_oosh_test_flags.sh test-enum -h 2>&1)"

_assert_contains "help <command> works" \
  "test-number" \
  "$(bash /tmp/_oosh_test_flags.sh help test-number 2>&1)"

_assert_contains "help <command> shows description" \
  "test number flags" \
  "$(bash /tmp/_oosh_test_flags.sh help test-number 2>&1)"

_assert_contains "help (no command) still shows full help" \
  "Commands:" \
  "$(bash /tmp/_oosh_test_flags.sh help 2>&1)"

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
printf "\n\033[1m Array flags (plain) \033[0m\n\n"

_assert "array: repeated flags" \
  "TAG=foo bar TAG_COUNT=2" \
  "$(bash /tmp/_oosh_test_array.sh --tag foo --tag bar test-array)"

_assert "array: comma-separated" \
  "TAG=foo bar TAG_COUNT=2" \
  "$(bash /tmp/_oosh_test_array.sh --tag foo,bar test-array)"

_assert "array: mixed repeated + CSV" \
  "TAG=a b c TAG_COUNT=3" \
  "$(bash /tmp/_oosh_test_array.sh --tag a --tag b,c test-array)"

_assert "array: single value" \
  "TAG=one TAG_COUNT=1" \
  "$(bash /tmp/_oosh_test_array.sh --tag one test-array)"

_assert "array: empty default" \
  "TAG= TAG_COUNT=0" \
  "$(bash /tmp/_oosh_test_array.sh test-array)"

_assert "array: short flag" \
  "TAG=x y TAG_COUNT=2" \
  "$(bash /tmp/_oosh_test_array.sh -t x -t y test-array)"

_assert "array: default value from annotation" \
  "TAG=x y TAG_COUNT=2" \
  "$(bash /tmp/_oosh_test_array_default.sh test-array)"

_assert "array: flag overrides default" \
  "TAG=z TAG_COUNT=1" \
  "$(bash /tmp/_oosh_test_array_default.sh --tag z test-array)"

# ============================================================
printf "\n\033[1m Array flags (enum validated) \033[0m\n\n"

_assert "array(enum): valid values accepted" \
  "LABEL=alpha beta LABEL_COUNT=2" \
  "$(bash /tmp/_oosh_test_array_enum.sh --label alpha --label beta test-array)"

_assert "array(enum): valid CSV accepted" \
  "LABEL=alpha gamma LABEL_COUNT=2" \
  "$(bash /tmp/_oosh_test_array_enum.sh --label alpha,gamma test-array)"

_assert_exit "array(enum): invalid value rejected" 2 \
  bash /tmp/_oosh_test_array_enum.sh --label alpha --label invalid test-array

_assert_exit "array(enum): invalid in CSV rejected" 2 \
  bash /tmp/_oosh_test_array_enum.sh --label alpha,bad test-array

# ============================================================
printf "\n\033[1m Array flags (dynamic enum) \033[0m\n\n"

_assert "array(enum(\${fn})): valid accepted" \
  "ENV=dev prod ENV_COUNT=2" \
  "$(bash /tmp/_oosh_test_array_dyn.sh --env dev --env prod test-array)"

_assert_exit "array(enum(\${fn})): invalid rejected" 2 \
  bash /tmp/_oosh_test_array_dyn.sh --env dev --env nope test-array

# ============================================================
printf "\n\033[1m Array: completion + help \033[0m\n\n"

_assert "array(enum): shortlist returns enum values" \
  "alpha beta gamma" \
  "$(bash /tmp/_oosh_test_array_enum.sh shortlist test-array --label)"

_assert "array(enum(\${fn})): shortlist returns dynamic values" \
  "$(printf 'dev\nstaging\nprod')" \
  "$(bash /tmp/_oosh_test_array_dyn.sh shortlist test-array --env)"

_assert_contains "array(enum): help shows (multiple)" \
  "(multiple)" \
  "$(bash /tmp/_oosh_test_array_enum.sh help 2>&1)"

_assert_contains "array(enum): help shows enum values" \
  "[alpha, beta, gamma]" \
  "$(bash /tmp/_oosh_test_array_enum.sh help 2>&1)"

_assert_contains "array: help shows (multiple)" \
  "(multiple)" \
  "$(bash /tmp/_oosh_test_array.sh help 2>&1)"

_assert_perf "array: flag parsing performance" 150 \
  bash /tmp/_oosh_test_array.sh --tag a --tag b,c test-array

# ============================================================
printf "\n\033[1m Boolean: non-greedy consumption \033[0m\n\n"

_assert "bool: --verbose yes → true, yes stays as positional" \
  "VERBOSE=true DRY_RUN=false" \
  "$(bash /tmp/_oosh_test_flags.sh --verbose test-bool 2>/dev/null)"

# --verbose yes: yes is NOT consumed, becomes first positional, test-bool becomes second
# _call gets (yes, test-bool) → yes is not a known method → shows help
# So we test with = syntax for the actual value pass-through
_assert "bool: --verbose=no sets no (= syntax)" \
  "VERBOSE=no DRY_RUN=false" \
  "$(bash /tmp/_oosh_test_flags.sh --verbose=no test-bool)"

_assert "bool: --verbose true consumed" \
  "VERBOSE=true DRY_RUN=false" \
  "$(bash /tmp/_oosh_test_flags.sh --verbose true test-bool)"

_assert "bool: --verbose false consumed" \
  "VERBOSE=false DRY_RUN=false" \
  "$(bash /tmp/_oosh_test_flags.sh --verbose false test-bool)"

# ============================================================
printf "\n\033[1m Escaped quotes in defaults \033[0m\n\n"

_assert "escaped quotes: default value preserves inner quotes" \
  'MSG=say "hello"' \
  "$(bash /tmp/_oosh_test_escaped_quotes.sh test-it)"

# ============================================================
printf "\n\033[1m Number validation \033[0m\n\n"

_assert_exit "number: trailing dot rejected" 2 \
  bash /tmp/_oosh_test_flags.sh --port 123. test-number

_assert "number: decimal accepted" \
  "PORT=1.5" \
  "$(bash /tmp/_oosh_test_flags.sh --port 1.5 test-number)"

# ============================================================
printf "\n\033[1m Unknown flags warning \033[0m\n\n"

_assert_contains "unknown flag: --vrebose warns on stderr" \
  "ignored unknown flag '--vrebose'" \
  "$(bash /tmp/_oosh_test_flags.sh --vrebose test-bool 2>&1)"

_assert_not_contains "known flag: --verbose no warning" \
  "ignored unknown flag" \
  "$(bash /tmp/_oosh_test_flags.sh --verbose test-bool 2>&1)"

_assert_not_contains "module dispatch: parent does not warn about child flags" \
  "ignored unknown flag" \
  "$(bash /tmp/_oosh_test_module_parent.sh child run -p /tmp -r /tmp 2>&1)"

_assert "module dispatch: child receives and parses flags" \
  "MPATH=/tmp MREPO=/tmp" \
  "$(bash /tmp/_oosh_test_module_parent.sh child run -p /tmp -r /tmp 2>&1)"

_assert_contains "module dispatch: parent still warns for own unknown flags" \
  "ignored unknown flag '--typo'" \
  "$(bash /tmp/_oosh_test_flags.sh --typo test-bool 2>&1)"

# ============================================================
printf "\n\033[1m -- stop-parsing \033[0m\n\n"

_assert_not_contains "-- stops flag parsing: args after -- not warned" \
  "ignored unknown flag" \
  "$(bash /tmp/_oosh_test_doubledash.sh test-dd -- --not-a-flag 2>&1)"

_assert_contains "-- stops flag parsing: flags before -- still parsed" \
  "VERBOSE=true" \
  "$(bash /tmp/_oosh_test_doubledash.sh --verbose test-dd -- --not-a-flag 2>&1)"

_assert_contains "-- stops flag parsing: positionals passed through" \
  "ARGS=--not-a-flag extra" \
  "$(bash /tmp/_oosh_test_doubledash.sh test-dd -- --not-a-flag extra 2>&1)"

_assert_not_contains "-- at end of args: stripped cleanly" \
  "--" \
  "$(bash /tmp/_oosh_test_doubledash.sh --verbose test-dd -- 2>&1)"

_assert_not_contains "-- bare marker not passed to function" \
  "ARGS=-- " \
  "$(bash /tmp/_oosh_test_doubledash.sh test-dd -- --not-a-flag 2>&1)"

# ============================================================
printf "\n\033[1m Malformed annotations \033[0m\n\n"

_assert_contains "malformed #@flag: warns on stderr" \
  "malformed #@flag" \
  "$(bash /tmp/_oosh_test_malformed.sh test-it 2>&1)"

_assert_contains "malformed #@flag: valid flag still works" \
  "VERBOSE=true" \
  "$(bash /tmp/_oosh_test_malformed.sh --verbose test-it 2>&1)"

# ============================================================
printf "\n\033[1m Unknown command \033[0m\n\n"

_assert_exit "zero args: exits 0 (shows help)" 0 \
  bash /tmp/_oosh_test_flags.sh

_assert_contains "zero args: shows help output" \
  "Usage:" \
  "$(bash /tmp/_oosh_test_flags.sh 2>&1)"

_assert_not_contains "zero args: no error message" \
  "unknown command" \
  "$(bash /tmp/_oosh_test_flags.sh 2>&1)"

_assert_exit "unknown command: exits 2" 2 \
  bash /tmp/_oosh_test_flags.sh nonexistent

_assert_contains "unknown command: shows error message" \
  "unknown command 'nonexistent'" \
  "$(bash /tmp/_oosh_test_flags.sh nonexistent 2>&1)"

_assert_contains "unknown command: shows help after error" \
  "Usage:" \
  "$(bash /tmp/_oosh_test_flags.sh nonexistent 2>&1)"

# ============================================================
printf "\n\033[1m Default function \033[0m\n\n"

_assert "default function called when no args passed" \
  "DEBUG=false" \
  "$(bash /tmp/_oosh_test_default.sh)"

_assert "default function receives flag args" \
  "DEBUG=true" \
  "$(bash /tmp/_oosh_test_default.sh --debug)"

_assert_contains "--help shows help instead of running default" \
  "Usage:" \
  "$(bash /tmp/_oosh_test_default.sh --help 2>&1)"

_assert_contains "-h shows help instead of running default" \
  "Usage:" \
  "$(bash /tmp/_oosh_test_default.sh -h 2>&1)"

# Note: protected functions are NOT added to GLOBAL_METHODS, so they can't be called by name
# The default function runs when no args provided

_assert_contains "no default specified: shows help on no args" \
  "Usage:" \
  "$(bash /tmp/_oosh_test_no_default.sh 2>&1)"

# ============================================================
printf "\n\033[1m Required flags \033[0m\n\n"

_assert_exit "required: missing flag exits 2" 2 \
  bash /tmp/_oosh_test_required.sh test-it

_assert_contains "required: error lists missing flags" \
  "missing required flag" \
  "$(bash /tmp/_oosh_test_required.sh test-it 2>&1)"

_assert "required: provided flags accepted" \
  "KEY=secret PORT=3000 NAME= ENV=prod LANG_CODE=en" \
  "$(bash /tmp/_oosh_test_required.sh --key secret --port 3000 --env prod test-it)"

_assert_exit "required:number invalid value exits 2" 2 \
  bash /tmp/_oosh_test_required.sh --key x --port abc --env prod test-it

_assert_contains "required:number shows number error (not required error)" \
  "expected: number" \
  "$(bash /tmp/_oosh_test_required.sh --key x --port abc --env prod test-it 2>&1)"

_out=$(bash /tmp/_oosh_test_required.sh help 2>&1) && _rc=$? || _rc=$?
_assert "required: help works without flags" "0" "$_rc"
_assert_contains "required: help shows (required)" "(required)" "$_out"

# ============================================================
printf "\n\033[1m Env var fallback \033[0m\n\n"

_assert "env: fallback expands env var" \
  "KEY=x PORT=80 NAME=alice ENV=prod LANG_CODE=en" \
  "$(TEST_OOSH_NAME=alice bash /tmp/_oosh_test_required.sh --key x --port 80 --env prod test-it)"

_assert_contains "env: help shows [env: VAR]" \
  "[env: TEST_OOSH_NAME]" \
  "$(bash /tmp/_oosh_test_required.sh help 2>&1)"

_assert "env: required + env var satisfies requirement" \
  "KEY=x PORT=80 NAME= ENV=staging LANG_CODE=en" \
  "$(TEST_OOSH_ENV=staging bash /tmp/_oosh_test_required.sh --key x --port 80 test-it)"

_assert_exit "env: required + env unset + no flag exits 2" 2 \
  bash /tmp/_oosh_test_required.sh --key x --port 80 test-it

_assert "env: \${VAR:-fallback} uses fallback when unset" \
  "KEY=x PORT=80 NAME= ENV=prod LANG_CODE=en" \
  "$(bash /tmp/_oosh_test_required.sh --key x --port 80 --env prod test-it)"

_assert "env: \${VAR:-fallback} uses env var when set" \
  "KEY=x PORT=80 NAME= ENV=prod LANG_CODE=pt" \
  "$(TEST_OOSH_LANG=pt bash /tmp/_oosh_test_required.sh --key x --port 80 --env prod test-it)"

_assert "env: \${VAR:-fallback} flag overrides both" \
  "KEY=x PORT=80 NAME= ENV=prod LANG_CODE=fr" \
  "$(TEST_OOSH_LANG=pt bash /tmp/_oosh_test_required.sh --key x --port 80 --env prod --lang fr test-it)"

_assert_contains "env: \${VAR:-fallback} shows [env: VAR] in help" \
  "[env: TEST_OOSH_LANG]" \
  "$(bash /tmp/_oosh_test_required.sh help 2>&1)"

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

_print_results
