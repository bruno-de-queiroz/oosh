#!/bin/bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/helpers.sh"

# --- fixtures ---

# Fast module fixture (duplicated from oo.sh suite — tiny, needed here)
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

# Fixture: trace async module (sleep 2 simulating a network call like kubectl)
cat > /tmp/_oosh_test_trace_async.sh << SCRIPT
#!/bin/bash
. ${OOSH_DIR}/oo.sh

function _slow_network_call() { sleep 2; echo "ns-default"; echo "ns-kube-system"; }

#@public ~ use a namespace
#@flag -n|--namespace NS "" enum(\${_slow_network_call}) ~ namespace from slow resolver
function use() { echo "NS=\$NS"; }

main \$0 "\$@"
SCRIPT

# Fixture: trace slow empty resolver (simulates kubectl returning nothing)
cat > /tmp/_oosh_test_trace_empty.sh << SCRIPT
#!/bin/bash
. ${OOSH_DIR}/oo.sh

function _slow_empty_resolver() { sleep 0.3; }

#@public ~ do something
#@flag -n|--name NAME "" enum(\${_slow_empty_resolver}) ~ name from slow empty resolver
function test-it() { echo "NAME=\$NAME"; }

main \$0 "\$@"
SCRIPT

# Generator fixture for multi-module + scoped trace tests
_GEN_DIR="/tmp/_oosh_gen_test_trace"
printf "yn" | bash "${OOSH_DIR}/generate.sh" --no-color _testcli "${_GEN_DIR}" >/dev/null 2>&1
_GEN_CLI="${_GEN_DIR}/_testcli"

cleanup() {
  rm -f /tmp/_oosh_test_flags.sh /tmp/_oosh_test_trace_slow.sh \
       /tmp/_oosh_test_trace_async.sh /tmp/_oosh_test_trace_empty.sh
  rm -rf /tmp/_oosh_gen_test_trace
}
trap cleanup EXIT

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

_trace_out=$(env _TESTCLI_DIR="${_GEN_CLI}" bash "${OOSH_DIR}/trace.sh" --no-color "${_GEN_CLI}/_testcli.sh" -r 1 -t 2000 2>&1) && _trace_rc=$? || _trace_rc=$?
_assert "trace: generated multi-module CLI exits 0" "0" "$_trace_rc"

_trace_out=$(env _TESTCLI_DIR="${_GEN_CLI}" bash "${OOSH_DIR}/trace.sh" --no-color "${_GEN_CLI}/_testcli.sh" hello -r 1 2>&1) && _trace_rc=$? || _trace_rc=$?
_assert_contains "trace: scoped to hello shows hello commands" "shortlist hello" "$_trace_out"
_assert_not_contains "trace: scoped to hello excludes install" "shortlist install" "$_trace_out"

_trace_out=$(env _TESTCLI_DIR="${_GEN_CLI}" bash "${OOSH_DIR}/trace.sh" --no-color "${_GEN_CLI}/_testcli.sh" hello greet -r 1 2>&1) && _trace_rc=$? || _trace_rc=$?
_assert_contains "trace: scoped to greet shows greet" "shortlist hello greet" "$_trace_out"
_assert_not_contains "trace: scoped to greet excludes farewell" "shortlist hello farewell" "$_trace_out"

# Async resolver: sleep 2 simulates a slow network call (e.g. kubectl get namespaces)
# The trace must report >2000ms for the flag that triggers it, proving cold timing is captured
_trace_out=$(bash "${OOSH_DIR}/trace.sh" --no-color /tmp/_oosh_test_trace_async.sh -t 50 -r 1 2>&1) && _trace_rc=$? || _trace_rc=$?
_assert "trace: async 2s resolver exits 1" "1" "$_trace_rc"
# Extract the ms value for --namespace line (first match only, first ms number)
_ns_ms=$(echo "$_trace_out" | grep -- '--namespace' | head -1 | sed 's/.*[[:space:]]\([0-9][0-9]*\)ms.*/\1/')
_ns_ok=0; [[ -n "$_ns_ms" && "$_ns_ms" -ge 1500 ]] && _ns_ok=1
_assert "trace: async 2s resolver reports >=1500ms (got ${_ns_ms:-?}ms)" "1" "$_ns_ok"

# Command-scoped trace on async module: "use" scope should trace --namespace flag completion
_trace_out=$(bash "${OOSH_DIR}/trace.sh" --no-color /tmp/_oosh_test_trace_async.sh use -t 50 -r 1 2>&1) && _trace_rc=$? || _trace_rc=$?
_assert_contains "trace: command-scoped shows --namespace flag" "shortlist use --namespace" "$_trace_out"
_ns_scoped_ms=$(echo "$_trace_out" | grep -- '--namespace' | head -1 | sed 's/.*[[:space:]]\([0-9][0-9]*\)ms.*/\1/')
_ns_scoped_ok=0; [[ -n "$_ns_scoped_ms" && "$_ns_scoped_ms" -ge 1500 ]] && _ns_scoped_ok=1
_assert "trace: command-scoped async reports >=1500ms (got ${_ns_scoped_ms:-?}ms)" "1" "$_ns_scoped_ok"

# Slow resolver returning empty output: trace must still surface the timing
_trace_out=$(bash "${OOSH_DIR}/trace.sh" --no-color /tmp/_oosh_test_trace_empty.sh -t 50 -r 1 2>&1) && _trace_rc=$? || _trace_rc=$?
_assert "trace: slow empty resolver exits 1" "1" "$_trace_rc"
_assert_contains "trace: slow empty resolver shows no completions" "no completions" "$_trace_out"
_empty_ms=$(echo "$_trace_out" | grep -- '--name' | head -1 | sed 's/.*[[:space:]]\([0-9][0-9]*\)ms.*/\1/')
_empty_ok=0; [[ -n "$_empty_ms" && "$_empty_ms" -ge 200 ]] && _empty_ok=1
_assert "trace: slow empty resolver reports >=200ms (got ${_empty_ms:-?}ms)" "1" "$_empty_ok"

_print_results
