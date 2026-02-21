#!/bin/bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/helpers.sh"

# --- fixtures ---

# Valid clean script
cat > /tmp/_oosh_test_validate_clean.sh << SCRIPT
#!/bin/bash
. ${OOSH_DIR}/oo.sh

#@flag -v|--verbose VERBOSE "false" boolean ~ enable verbose output
#@flag -p|--port PORT "8080" number ~ server port

#@public ~ run the app
#@flag -d|--dry-run DRY_RUN "false" boolean ~ dry run mode
function run() { echo "ok"; }

#@public ~ deploy the app
#@flag -e|--env ENVIRONMENT "prod" enum(dev,staging,prod) ~ target environment
function deploy() { echo "ok"; }

main \$0 "\$@"
SCRIPT

# Malformed flag
cat > /tmp/_oosh_test_validate_malformed.sh << SCRIPT
#!/bin/bash
#@flag broken flag line
#@public ~ test
function test-it() { echo "ok"; }
SCRIPT

# Invalid type
cat > /tmp/_oosh_test_validate_badtype.sh << SCRIPT
#!/bin/bash
#@flag -x|--item ITEM "" string ~ bad type
#@public ~ test
function test-it() { echo "ok"; }
SCRIPT

# Another invalid type (bool instead of boolean)
cat > /tmp/_oosh_test_validate_badtype2.sh << SCRIPT
#!/bin/bash
#@flag -v|--verbose VERBOSE "false" bool ~ bad type
#@public ~ test
function test-it() { echo "ok"; }
SCRIPT

# Orphaned visibility
cat > /tmp/_oosh_test_validate_orphan.sh << SCRIPT
#!/bin/bash
#@public ~ this goes nowhere
echo "not a function"
#@public ~ test
function test-it() { echo "ok"; }
SCRIPT

# Orphaned at EOF
cat > /tmp/_oosh_test_validate_orphan_eof.sh << SCRIPT
#!/bin/bash
#@public ~ dangling at end of file
SCRIPT

# Duplicate flags in same scope
cat > /tmp/_oosh_test_validate_dupflag.sh << SCRIPT
#!/bin/bash
#@flag -v|--verbose VERBOSE "false" boolean ~ verbose
#@flag -v|--verbose DUP "false" boolean ~ duplicate
#@public ~ test
function test-it() { echo "ok"; }
SCRIPT

# Duplicate flags in command scope
cat > /tmp/_oosh_test_validate_dupflag_cmd.sh << SCRIPT
#!/bin/bash
#@public ~ test
#@flag -v|--verbose VERBOSE "false" boolean ~ verbose
#@flag -v|--verbose DUP "false" boolean ~ duplicate
function test-it() { echo "ok"; }
SCRIPT

# Variable collision (same var, different scopes)
cat > /tmp/_oosh_test_validate_varcol.sh << SCRIPT
#!/bin/bash
#@flag -v|--verbose VERBOSE "false" boolean ~ verbose global
#@public ~ test
#@flag -d|--debug VERBOSE "false" boolean ~ reuses VERBOSE
function test-it() { echo "ok"; }
SCRIPT

# Env var shadow
cat > /tmp/_oosh_test_validate_envshadow.sh << SCRIPT
#!/bin/bash
#@flag -p|--path PATH "" ~ shadows PATH
#@flag -h|--home HOME "" ~ shadows HOME
#@public ~ test
function test-it() { echo "ok"; }
SCRIPT

# oosh internal shadow
cat > /tmp/_oosh_test_validate_intshadow.sh << SCRIPT
#!/bin/bash
#@flag -m|--modules MODULES_DIR "" ~ shadows internal
#@public ~ test
function test-it() { echo "ok"; }
SCRIPT

# Missing description
cat > /tmp/_oosh_test_validate_nodesc.sh << SCRIPT
#!/bin/bash
#@flag -v|--verbose VERBOSE "false" boolean
#@public ~ test
function test-it() { echo "ok"; }
SCRIPT

# Legacy #@description suppresses warning
cat > /tmp/_oosh_test_validate_legacydesc.sh << SCRIPT
#!/bin/bash
#@flag -v|--verbose VERBOSE "false" boolean
#@description enable verbose output
#@public ~ test
function test-it() { echo "ok"; }
SCRIPT

# Valid enum types
cat > /tmp/_oosh_test_validate_types.sh << SCRIPT
#!/bin/bash
#@flag -e|--env ENVIRONMENT "prod" enum(dev,staging,prod) ~ environment
#@flag -f|--file CONFIG "" file ~ config file
#@flag -d|--dir OUTPUT "" dir ~ output dir
#@flag -n|--count COUNT "1" number ~ count
#@flag -v|--verbose VERBOSE "false" boolean ~ verbose
#@flag -t|--tags TAGS "" array ~ tags
#@flag -r|--regions REGIONS "" array(enum(us,eu,ap)) ~ regions
#@public ~ test
function test-it() { echo "ok"; }
SCRIPT

# Generator fixture for multi-module tests
_GEN_DIR="/tmp/_oosh_gen_test_validate"
printf "yn" | bash "${OOSH_DIR}/generate.sh" --no-color _testcli_v "${_GEN_DIR}" >/dev/null 2>&1
_GEN_CLI="${_GEN_DIR}/_testcli_v"

cleanup() {
  rm -f /tmp/_oosh_test_validate_*.sh
  rm -rf /tmp/_oosh_gen_test_validate
}
trap cleanup EXIT

# ============================================================
printf "\n\033[1m Validate \033[0m\n\n"

# --- clean script ---
_out=$(bash "${OOSH_DIR}/validate.sh" --no-color /tmp/_oosh_test_validate_clean.sh 2>&1) && _rc=$? || _rc=$?
_assert "validate: clean script exits 0" "0" "$_rc"
_assert_contains "validate: clean script shows command count" "2 command(s)" "$_out"
_assert_contains "validate: clean script shows flag count" "4 flag(s)" "$_out"
_assert_contains "validate: clean script shows 0 errors" "0 errors, 0 warnings" "$_out"

# --- malformed flag ---
_out=$(bash "${OOSH_DIR}/validate.sh" --no-color /tmp/_oosh_test_validate_malformed.sh 2>&1) && _rc=$? || _rc=$?
_assert "validate: malformed flag exits 1" "1" "$_rc"
_assert_contains "validate: malformed flag detected" "malformed" "$_out"

# --- invalid type ---
_out=$(bash "${OOSH_DIR}/validate.sh" --no-color /tmp/_oosh_test_validate_badtype.sh 2>&1) && _rc=$? || _rc=$?
_assert "validate: invalid type exits 1" "1" "$_rc"
_assert_contains "validate: invalid type 'string' detected" "invalid type" "$_out"

_out=$(bash "${OOSH_DIR}/validate.sh" --no-color /tmp/_oosh_test_validate_badtype2.sh 2>&1) && _rc=$? || _rc=$?
_assert "validate: invalid type 'bool' exits 1" "1" "$_rc"
_assert_contains "validate: invalid type 'bool' detected" "invalid type" "$_out"

# --- orphaned visibility ---
_out=$(bash "${OOSH_DIR}/validate.sh" --no-color /tmp/_oosh_test_validate_orphan.sh 2>&1) && _rc=$? || _rc=$?
_assert "validate: orphaned visibility exits 1" "1" "$_rc"
_assert_contains "validate: orphaned detected" "orphaned" "$_out"

_out=$(bash "${OOSH_DIR}/validate.sh" --no-color /tmp/_oosh_test_validate_orphan_eof.sh 2>&1) && _rc=$? || _rc=$?
_assert "validate: orphaned at EOF exits 1" "1" "$_rc"
_assert_contains "validate: orphaned at EOF detected" "orphaned" "$_out"

# --- duplicate flags ---
_out=$(bash "${OOSH_DIR}/validate.sh" --no-color /tmp/_oosh_test_validate_dupflag.sh 2>&1) && _rc=$? || _rc=$?
_assert "validate: duplicate flag in global exits 1" "1" "$_rc"
_assert_contains "validate: duplicate flag detected" "duplicate flag" "$_out"

_out=$(bash "${OOSH_DIR}/validate.sh" --no-color /tmp/_oosh_test_validate_dupflag_cmd.sh 2>&1) && _rc=$? || _rc=$?
_assert "validate: duplicate flag in command exits 1" "1" "$_rc"
_assert_contains "validate: duplicate flag in command detected" "duplicate flag" "$_out"

# --- variable collision ---
_out=$(bash "${OOSH_DIR}/validate.sh" --no-color /tmp/_oosh_test_validate_varcol.sh 2>&1) && _rc=$? || _rc=$?
_assert "validate: variable collision exits 0" "0" "$_rc"
_assert_contains "validate: variable collision warns" "used by multiple flags" "$_out"

# --- env var shadow ---
_out=$(bash "${OOSH_DIR}/validate.sh" --no-color /tmp/_oosh_test_validate_envshadow.sh 2>&1) && _rc=$? || _rc=$?
_assert "validate: env shadow exits 0" "0" "$_rc"
_assert_contains "validate: PATH shadow warned" "PATH shadows environment" "$_out"
_assert_contains "validate: HOME shadow warned" "HOME shadows environment" "$_out"

# --- oosh internal shadow ---
_out=$(bash "${OOSH_DIR}/validate.sh" --no-color /tmp/_oosh_test_validate_intshadow.sh 2>&1) && _rc=$? || _rc=$?
_assert "validate: internal shadow exits 0" "0" "$_rc"
_assert_contains "validate: MODULES_DIR shadow warned" "MODULES_DIR shadows oosh internal" "$_out"

# --- missing description ---
_out=$(bash "${OOSH_DIR}/validate.sh" --no-color /tmp/_oosh_test_validate_nodesc.sh 2>&1) && _rc=$? || _rc=$?
_assert "validate: missing description exits 0" "0" "$_rc"
_assert_contains "validate: missing description warns" "has no description" "$_out"

# --- legacy #@description suppresses warning ---
_out=$(bash "${OOSH_DIR}/validate.sh" --no-color /tmp/_oosh_test_validate_legacydesc.sh 2>&1) && _rc=$? || _rc=$?
_assert "validate: legacy description exits 0" "0" "$_rc"
_assert_contains "validate: legacy description no warnings" "0 errors, 0 warnings" "$_out"

# --- valid types all pass ---
_out=$(bash "${OOSH_DIR}/validate.sh" --no-color /tmp/_oosh_test_validate_types.sh 2>&1) && _rc=$? || _rc=$?
_assert "validate: all valid types exit 0" "0" "$_rc"
_assert_contains "validate: all valid types clean" "0 errors, 0 warnings" "$_out"

# --- multi-module generated CLI ---
_out=$(env _TESTCLI_V_DIR="${_GEN_CLI}" bash "${OOSH_DIR}/validate.sh" --no-color "${_GEN_CLI}/_testcli_v.sh" 2>&1) && _rc=$? || _rc=$?
_assert "validate: generated multi-module CLI exits 0" "0" "$_rc"
_assert_contains "validate: multi-module shows multiple files" "file(s)" "$_out"

# --- module-scoped validation ---
_out=$(env _TESTCLI_V_DIR="${_GEN_CLI}" bash "${OOSH_DIR}/validate.sh" --no-color "${_GEN_CLI}/_testcli_v.sh" hello 2>&1) && _rc=$? || _rc=$?
_assert "validate: module-scoped exits 0" "0" "$_rc"
_assert_contains "validate: module-scoped shows scope" "scope: hello" "$_out"
_assert_contains "validate: module-scoped shows 1 file" "1 file(s)" "$_out"

# --- --no-color strips ANSI ---
_out=$(bash "${OOSH_DIR}/validate.sh" --no-color /tmp/_oosh_test_validate_clean.sh 2>&1)
_has_ansi=0
printf '%s' "$_out" | grep -q $'\033\[' && _has_ansi=1
_assert "validate: --no-color strips ANSI" "0" "$_has_ansi"

# --- performance ---
_assert_perf "validate: single file <200ms" 200 bash "${OOSH_DIR}/validate.sh" --no-color /tmp/_oosh_test_validate_clean.sh
_assert_perf "validate: multi-module <500ms" 500 env "_TESTCLI_V_DIR=${_GEN_CLI}" bash "${OOSH_DIR}/validate.sh" --no-color "${_GEN_CLI}/_testcli_v.sh"

_print_results
