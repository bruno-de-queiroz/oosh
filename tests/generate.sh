#!/bin/bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd)/helpers.sh"

# --- generator fixture ---
_GEN_DIR="/tmp/_oosh_gen_test"
printf "yn" | bash "${OOSH_DIR}/generate.sh" --no-color _testcli "${_GEN_DIR}" >/dev/null 2>&1
_GEN_CLI="${_GEN_DIR}/_testcli"
_run_gen() { env _TESTCLI_DIR="${_GEN_CLI}" MODULES_DIR="${_GEN_CLI}/modules" bash "$@"; }

cleanup() {
  rm -rf /tmp/_oosh_gen_test
}
trap cleanup EXIT

# ============================================================
printf "\n\033[1m Generator: scaffolding \033[0m\n\n"

_assert "creates entry point" "true" \
  "$([[ -f "${_GEN_CLI}/_testcli.sh" ]] && echo true || echo false)"

_assert "creates bash completion script" "true" \
  "$([[ -f "${_GEN_CLI}/_testcli.comp.sh" ]] && echo true || echo false)"

_assert "creates zsh completion script" "true" \
  "$([[ -f "${_GEN_CLI}/_testcli.zcomp.sh" ]] && echo true || echo false)"

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

# Tamper with all framework files to verify update replaces them
echo "# tampered" >> "${_GEN_CLI}/oo.sh"
echo "# tampered" >> "${_GEN_CLI}/_testcli.sh"
echo "# tampered" >> "${_GEN_CLI}/_testcli.comp.sh"
echo "# tampered" >> "${_GEN_CLI}/_testcli.zcomp.sh"
printf "y" | bash "${OOSH_DIR}/generate.sh" --no-color _testcli "${_GEN_DIR}" >/dev/null 2>&1

_assert "update restores oo.sh" "false" \
  "$(grep -q '# tampered' "${_GEN_CLI}/oo.sh" 2>/dev/null && echo true || echo false)"

_assert "update restores entry point" "false" \
  "$(grep -q '# tampered' "${_GEN_CLI}/_testcli.sh" 2>/dev/null && echo true || echo false)"

_assert "update restores bash completion script" "false" \
  "$(grep -q '# tampered' "${_GEN_CLI}/_testcli.comp.sh" 2>/dev/null && echo true || echo false)"

_assert "update restores zsh completion script" "false" \
  "$(grep -q '# tampered' "${_GEN_CLI}/_testcli.zcomp.sh" 2>/dev/null && echo true || echo false)"

_assert "modules untouched after update" "true" \
  "$([[ -f "${_GEN_CLI}/modules/hello.sh" ]] && echo true || echo false)"

# ============================================================
printf "\n\033[1m Performance \033[0m\n\n"

# Generated module
_assert_perf "generated module: greet" 150 \
  env _TESTCLI_DIR="${_GEN_CLI}" MODULES_DIR="${_GEN_CLI}/modules" bash "${_GEN_CLI}/modules/hello.sh" greet

_assert_perf "generated module: shortlist" 150 \
  env _TESTCLI_DIR="${_GEN_CLI}" MODULES_DIR="${_GEN_CLI}/modules" bash "${_GEN_CLI}/modules/hello.sh" shortlist

_assert_perf "generated module: help" 150 \
  env _TESTCLI_DIR="${_GEN_CLI}" MODULES_DIR="${_GEN_CLI}/modules" bash "${_GEN_CLI}/modules/hello.sh" help

_print_results
