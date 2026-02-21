#!/bin/bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/helpers.sh"

# --- fixtures ---

# Temp dir for fixtures that need realistic filenames (prefix check)
_FIX_DIR="/tmp/_oosh_test_lint_fix"
mkdir -p "$_FIX_DIR"

# Valid clean script (filename: deploy.sh → prefix DEPLOY_)
cat > "${_FIX_DIR}/deploy.sh" << SCRIPT
#!/bin/bash
. ${OOSH_DIR}/oo.sh

#@flag -v|--verbose DEPLOY_VERBOSE "false" boolean ~ enable verbose output
#@flag -p|--port DEPLOY_PORT "8080" number ~ server port

#@public ~ run the app
#@flag -d|--dry-run DEPLOY_DRY_RUN "false" boolean ~ dry run mode
function run() { echo "ok"; }

#@public ~ deploy the app
#@flag -e|--env DEPLOY_ENVIRONMENT "prod" enum(dev,staging,prod) ~ target environment
function deploy() { echo "ok"; }

main \$0 "\$@"
SCRIPT

# Malformed flag
cat > /tmp/_oosh_test_lint_malformed.sh << SCRIPT
#!/bin/bash
#@flag broken flag line
#@public ~ test
function test-it() { echo "ok"; }
SCRIPT

# Invalid type
cat > /tmp/_oosh_test_lint_badtype.sh << SCRIPT
#!/bin/bash
#@flag -x|--item ITEM "" string ~ bad type
#@public ~ test
function test-it() { echo "ok"; }
SCRIPT

# Another invalid type (bool instead of boolean)
cat > /tmp/_oosh_test_lint_badtype2.sh << SCRIPT
#!/bin/bash
#@flag -v|--verbose VERBOSE "false" bool ~ bad type
#@public ~ test
function test-it() { echo "ok"; }
SCRIPT

# Orphaned visibility
cat > /tmp/_oosh_test_lint_orphan.sh << SCRIPT
#!/bin/bash
#@public ~ this goes nowhere
echo "not a function"
#@public ~ test
function test-it() { echo "ok"; }
SCRIPT

# Orphaned at EOF
cat > /tmp/_oosh_test_lint_orphan_eof.sh << SCRIPT
#!/bin/bash
#@public ~ dangling at end of file
SCRIPT

# Duplicate flags in same scope
cat > /tmp/_oosh_test_lint_dupflag.sh << SCRIPT
#!/bin/bash
#@flag -v|--verbose VERBOSE "false" boolean ~ verbose
#@flag -v|--verbose DUP "false" boolean ~ duplicate
#@public ~ test
function test-it() { echo "ok"; }
SCRIPT

# Duplicate flags in command scope
cat > /tmp/_oosh_test_lint_dupflag_cmd.sh << SCRIPT
#!/bin/bash
#@public ~ test
#@flag -v|--verbose VERBOSE "false" boolean ~ verbose
#@flag -v|--verbose DUP "false" boolean ~ duplicate
function test-it() { echo "ok"; }
SCRIPT

# Variable collision (same var, different scopes)
cat > /tmp/_oosh_test_lint_varcol.sh << SCRIPT
#!/bin/bash
#@flag -v|--verbose VERBOSE "false" boolean ~ verbose global
#@public ~ test
#@flag -d|--debug VERBOSE "false" boolean ~ reuses VERBOSE
function test-it() { echo "ok"; }
SCRIPT

# Env var shadow
cat > /tmp/_oosh_test_lint_envshadow.sh << SCRIPT
#!/bin/bash
#@flag -p|--path PATH "" ~ shadows PATH
#@flag -h|--home HOME "" ~ shadows HOME
#@public ~ test
function test-it() { echo "ok"; }
SCRIPT

# oosh internal shadow
cat > /tmp/_oosh_test_lint_intshadow.sh << SCRIPT
#!/bin/bash
#@flag -m|--modules MODULES_DIR "" ~ shadows internal
#@public ~ test
function test-it() { echo "ok"; }
SCRIPT

# Missing description (filename: nodesc.sh → prefix NODESC_)
cat > "${_FIX_DIR}/nodesc.sh" << SCRIPT
#!/bin/bash
#@flag -v|--verbose NODESC_VERBOSE "false" boolean
#@public ~ test
function test-it() { echo "ok"; }
SCRIPT

# Legacy #@description suppresses warning (filename: legacydesc.sh → prefix LEGACYDESC_)
cat > "${_FIX_DIR}/legacydesc.sh" << SCRIPT
#!/bin/bash
#@flag -v|--verbose LEGACYDESC_VERBOSE "false" boolean
#@description enable verbose output
#@public ~ test
function test-it() { echo "ok"; }
SCRIPT

# Valid enum types (filename: types.sh → prefix TYPES_)
cat > "${_FIX_DIR}/types.sh" << SCRIPT
#!/bin/bash
#@flag -e|--env TYPES_ENVIRONMENT "prod" enum(dev,staging,prod) ~ environment
#@flag -f|--file TYPES_CONFIG "" file ~ config file
#@flag -d|--dir TYPES_OUTPUT "" dir ~ output dir
#@flag -n|--count TYPES_COUNT "1" number ~ count
#@flag -v|--verbose TYPES_VERBOSE "false" boolean ~ verbose
#@flag -t|--tags TYPES_TAGS "" array ~ tags
#@flag -r|--regions TYPES_REGIONS "" array(enum(us,eu,ap)) ~ regions
#@public ~ test
function test-it() { echo "ok"; }
SCRIPT

# Missing prefix (filename: hello.sh → prefix HELLO_, but uses bare VERBOSE)
cat > "${_FIX_DIR}/hello.sh" << SCRIPT
#!/bin/bash
#@flag -v|--verbose VERBOSE "false" boolean ~ unprefixed var
#@flag -n|--name HELLO_NAME "world" ~ correctly prefixed
#@public ~ test
function test-it() { echo "ok"; }
SCRIPT

# Generator fixture for multi-module tests
_GEN_DIR="/tmp/_oosh_gen_test_lint"
printf "yn" | bash "${OOSH_DIR}/generate.sh" --no-color _testcli_v "${_GEN_DIR}" >/dev/null 2>&1
_GEN_CLI="${_GEN_DIR}/_testcli_v"

cleanup() {
  rm -f /tmp/_oosh_test_lint_*.sh
  rm -rf /tmp/_oosh_gen_test_lint
  rm -rf "$_FIX_DIR"
}
trap cleanup EXIT

# ============================================================
printf "\n\033[1m Lint \033[0m\n\n"

# --- clean script ---
_out=$(bash "${OOSH_DIR}/lint.sh" --no-color "${_FIX_DIR}/deploy.sh" 2>&1) && _rc=$? || _rc=$?
_assert "lint: clean script exits 0" "0" "$_rc"
_assert_contains "lint: clean script shows command count" "2 command(s)" "$_out"
_assert_contains "lint: clean script shows flag count" "4 flag(s)" "$_out"
_assert_contains "lint: clean script shows 0 errors" "0 errors, 0 warnings" "$_out"

# --- malformed flag ---
_out=$(bash "${OOSH_DIR}/lint.sh" --no-color /tmp/_oosh_test_lint_malformed.sh 2>&1) && _rc=$? || _rc=$?
_assert "lint: malformed flag exits 1" "1" "$_rc"
_assert_contains "lint: malformed flag detected" "malformed" "$_out"

# --- invalid type ---
_out=$(bash "${OOSH_DIR}/lint.sh" --no-color /tmp/_oosh_test_lint_badtype.sh 2>&1) && _rc=$? || _rc=$?
_assert "lint: invalid type exits 1" "1" "$_rc"
_assert_contains "lint: invalid type 'string' detected" "invalid type" "$_out"

_out=$(bash "${OOSH_DIR}/lint.sh" --no-color /tmp/_oosh_test_lint_badtype2.sh 2>&1) && _rc=$? || _rc=$?
_assert "lint: invalid type 'bool' exits 1" "1" "$_rc"
_assert_contains "lint: invalid type 'bool' detected" "invalid type" "$_out"

# --- orphaned visibility ---
_out=$(bash "${OOSH_DIR}/lint.sh" --no-color /tmp/_oosh_test_lint_orphan.sh 2>&1) && _rc=$? || _rc=$?
_assert "lint: orphaned visibility exits 1" "1" "$_rc"
_assert_contains "lint: orphaned detected" "orphaned" "$_out"

_out=$(bash "${OOSH_DIR}/lint.sh" --no-color /tmp/_oosh_test_lint_orphan_eof.sh 2>&1) && _rc=$? || _rc=$?
_assert "lint: orphaned at EOF exits 1" "1" "$_rc"
_assert_contains "lint: orphaned at EOF detected" "orphaned" "$_out"

# --- duplicate flags ---
_out=$(bash "${OOSH_DIR}/lint.sh" --no-color /tmp/_oosh_test_lint_dupflag.sh 2>&1) && _rc=$? || _rc=$?
_assert "lint: duplicate flag in global exits 1" "1" "$_rc"
_assert_contains "lint: duplicate flag detected" "duplicate flag" "$_out"

_out=$(bash "${OOSH_DIR}/lint.sh" --no-color /tmp/_oosh_test_lint_dupflag_cmd.sh 2>&1) && _rc=$? || _rc=$?
_assert "lint: duplicate flag in command exits 1" "1" "$_rc"
_assert_contains "lint: duplicate flag in command detected" "duplicate flag" "$_out"

# --- variable collision ---
_out=$(bash "${OOSH_DIR}/lint.sh" --no-color /tmp/_oosh_test_lint_varcol.sh 2>&1) && _rc=$? || _rc=$?
_assert "lint: variable collision exits 0" "0" "$_rc"
_assert_contains "lint: variable collision warns" "used by multiple flags" "$_out"

# --- env var shadow ---
_out=$(bash "${OOSH_DIR}/lint.sh" --no-color /tmp/_oosh_test_lint_envshadow.sh 2>&1) && _rc=$? || _rc=$?
_assert "lint: env shadow exits 0" "0" "$_rc"
_assert_contains "lint: PATH shadow warned" "PATH shadows environment" "$_out"
_assert_contains "lint: HOME shadow warned" "HOME shadows environment" "$_out"

# --- oosh internal shadow ---
_out=$(bash "${OOSH_DIR}/lint.sh" --no-color /tmp/_oosh_test_lint_intshadow.sh 2>&1) && _rc=$? || _rc=$?
_assert "lint: internal shadow exits 0" "0" "$_rc"
_assert_contains "lint: MODULES_DIR shadow warned" "MODULES_DIR shadows oosh internal" "$_out"

# --- missing description ---
_out=$(bash "${OOSH_DIR}/lint.sh" --no-color "${_FIX_DIR}/nodesc.sh" 2>&1) && _rc=$? || _rc=$?
_assert "lint: missing description exits 0" "0" "$_rc"
_assert_contains "lint: missing description warns" "has no description" "$_out"

# --- legacy #@description suppresses warning ---
_out=$(bash "${OOSH_DIR}/lint.sh" --no-color "${_FIX_DIR}/legacydesc.sh" 2>&1) && _rc=$? || _rc=$?
_assert "lint: legacy description exits 0" "0" "$_rc"
_assert_contains "lint: legacy description no warnings" "0 errors, 0 warnings" "$_out"

# --- valid types all pass ---
_out=$(bash "${OOSH_DIR}/lint.sh" --no-color "${_FIX_DIR}/types.sh" 2>&1) && _rc=$? || _rc=$?
_assert "lint: all valid types exit 0" "0" "$_rc"
_assert_contains "lint: all valid types clean" "0 errors, 0 warnings" "$_out"

# --- missing prefix warning ---
_out=$(bash "${OOSH_DIR}/lint.sh" --no-color "${_FIX_DIR}/hello.sh" 2>&1) && _rc=$? || _rc=$?
_assert "lint: missing prefix exits 0" "0" "$_rc"
_assert_contains "lint: missing prefix warns" "VERBOSE should be prefixed as HELLO_VERBOSE" "$_out"
_assert_not_contains "lint: correctly prefixed var has no warning" "HELLO_NAME should be prefixed" "$_out"

# --- multi-module generated CLI ---
_out=$(env _TESTCLI_V_DIR="${_GEN_CLI}" bash "${OOSH_DIR}/lint.sh" --no-color "${_GEN_CLI}/_testcli_v.sh" 2>&1) && _rc=$? || _rc=$?
_assert "lint: generated multi-module CLI exits 0" "0" "$_rc"
_assert_contains "lint: multi-module shows multiple files" "file(s)" "$_out"

# --- module-scoped validation ---
_out=$(env _TESTCLI_V_DIR="${_GEN_CLI}" bash "${OOSH_DIR}/lint.sh" --no-color "${_GEN_CLI}/_testcli_v.sh" hello 2>&1) && _rc=$? || _rc=$?
_assert "lint: module-scoped exits 0" "0" "$_rc"
_assert_contains "lint: module-scoped shows scope" "scope: hello" "$_out"
_assert_contains "lint: module-scoped shows 1 file" "1 file(s)" "$_out"

# --- --no-color strips ANSI ---
_out=$(bash "${OOSH_DIR}/lint.sh" --no-color "${_FIX_DIR}/deploy.sh" 2>&1)
_has_ansi=0
printf '%s' "$_out" | grep -q $'\033\[' && _has_ansi=1
_assert "lint: --no-color strips ANSI" "0" "$_has_ansi"

# --- --fix: prefix rename ---
cat > "${_FIX_DIR}/fixme.sh" << SCRIPT
#!/bin/bash
#@flag -v|--verbose VERBOSE "false" boolean ~ unprefixed var
#@flag -n|--name NAME "world"
#@public ~ say hello
function greet() {
  echo "Hello, \${NAME}! verbose=\$VERBOSE"
}
SCRIPT
_out=$(bash "${OOSH_DIR}/lint.sh" --fix --no-color "${_FIX_DIR}/fixme.sh" 2>&1) && _rc=$? || _rc=$?
_assert_contains "lint: --fix renames vars" "VERBOSE → FIXME_VERBOSE" "$_out"
_assert_contains "lint: --fix renames NAME" "NAME → FIXME_NAME" "$_out"
_assert_contains "lint: --fix adds description" "added placeholder description" "$_out"
# Verify the file was actually modified
_fixed_content=$(cat "${_FIX_DIR}/fixme.sh")
_assert_contains "lint: --fix annotation updated" "FIXME_VERBOSE" "$_fixed_content"
_assert_contains "lint: --fix usage \${} updated" '${FIXME_NAME}' "$_fixed_content"
_assert_contains "lint: --fix usage \$ updated" '$FIXME_VERBOSE' "$_fixed_content"
_assert_contains "lint: --fix added TODO desc" "~ TODO" "$_fixed_content"
# Re-lint should be clean
_out2=$(bash "${OOSH_DIR}/lint.sh" --no-color "${_FIX_DIR}/fixme.sh" 2>&1) && _rc2=$? || _rc2=$?
_assert "lint: --fix re-lint exits 0" "0" "$_rc2"
_assert_contains "lint: --fix re-lint clean" "0 errors, 0 warnings" "$_out2"

# --- performance ---
_assert_perf "lint: single file <200ms" 200 bash "${OOSH_DIR}/lint.sh" --no-color "${_FIX_DIR}/deploy.sh"
_assert_perf "lint: multi-module <500ms" 500 env "_TESTCLI_V_DIR=${_GEN_CLI}" bash "${OOSH_DIR}/lint.sh" --no-color "${_GEN_CLI}/_testcli_v.sh"

_print_results
