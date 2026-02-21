#!/usr/bin/env bash
#
# oosh installer
#
# Usage: curl -fsSL https://raw.githubusercontent.com/bruno-de-queiroz/oosh/main/install.sh | bash
#

set -euo pipefail

OOSH_REPO="${OOSH_REPO:-https://raw.githubusercontent.com/bruno-de-queiroz/oosh/main}"
OOSH_HOME="${HOME}/.oosh"

# --- colors (respect NO_COLOR) ---
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$'\033[1m' DIM=$'\033[2m' RST=$'\033[0m'
  CY=$'\033[36m' GR=$'\033[32m' MG=$'\033[35m' RD=$'\033[31m'
else
  B="" DIM="" RST="" CY="" GR="" MG="" RD=""
fi
OK="${GR}✔${RST}" ERR="${RD}✘${RST}" DOT="${MG}◆${RST}"

# --- banner ---
printf "\n${MG}"
printf '    ___    ___    ___   _     \n'
printf '   / _ \  / _ \  / __| | |__ \n'
printf '  | (_) || (_) | \__ \ |  _ \\\n'
printf '   \___/  \___/  |___/ |_| |_|\n'
printf "${RST}\n"

printf "  ${DOT}  ${B}Installing oosh...${RST}\n\n"

# --- sanity check ---
if ! command -v curl >/dev/null 2>&1; then
  printf "  ${ERR}  curl is required but not found\n" >&2
  exit 1
fi

# --- download core files ---
mkdir -p "${OOSH_HOME}"

printf "  ${CY}↓${RST}  oo.sh\n"
curl -fsSL "${OOSH_REPO}/oo.sh" -o "${OOSH_HOME}/oo.sh"

printf "  ${CY}↓${RST}  generate.sh\n"
curl -fsSL "${OOSH_REPO}/generate.sh" -o "${OOSH_HOME}/generate.sh"
chmod +x "${OOSH_HOME}/generate.sh"

printf "  ${CY}↓${RST}  trace.sh\n"
curl -fsSL "${OOSH_REPO}/trace.sh" -o "${OOSH_HOME}/trace.sh"
chmod +x "${OOSH_HOME}/trace.sh"

printf "  ${CY}↓${RST}  validate.sh\n"
curl -fsSL "${OOSH_REPO}/validate.sh" -o "${OOSH_HOME}/validate.sh"
chmod +x "${OOSH_HOME}/validate.sh"

# --- find a writable bin directory ---
_find_bin_dir() {
  local d
  for d in /opt/homebrew/bin /usr/local/bin; do
    [ -d "$d" ] && [ -w "$d" ] && { echo "$d"; return; }
  done
  echo "${HOME}/.local/bin"
}

BIN_DIR=$(_find_bin_dir)
mkdir -p "${BIN_DIR}"

cat > "${OOSH_HOME}/oosh" << EOF
#!/bin/bash
case "\${1:-}" in
  trace)    shift; exec bash "${OOSH_HOME}/trace.sh" "\$@" ;;
  validate) shift; exec bash "${OOSH_HOME}/validate.sh" "\$@" ;;
  *)        exec bash "${OOSH_HOME}/generate.sh" "\$@" ;;
esac
EOF
chmod +x "${OOSH_HOME}/oosh"
ln -sf "${OOSH_HOME}/oosh" "${BIN_DIR}/oosh"
printf "  ${OK}  ${B}oosh${RST} ${DIM}→ ${BIN_DIR}/oosh${RST}\n"

# --- update shell profiles if using ~/.local/bin ---
NEEDS_PATH_UPDATE=0
if [[ "${BIN_DIR}" == "${HOME}/.local/bin" ]]; then
  NEEDS_PATH_UPDATE=1
  _add_to_profile() {
    local file="$1" line='export PATH="${HOME}/.local/bin:${PATH}"'
    [ -f "$file" ] || return 0
    grep -qF '.local/bin' "$file" || printf '\n# oosh\n%s\n' "$line" >> "$file"
  }
  _add_to_profile "${HOME}/.bashrc"
  _add_to_profile "${HOME}/.bash_profile"
  _add_to_profile "${HOME}/.zshrc"
  printf "  ${OK}  PATH updated in shell profiles\n"
fi

# --- done ---
printf "\n  ${GR}${B}Done!${RST} ${DIM}Generate your first CLI:${RST}\n\n"

if [[ "${NEEDS_PATH_UPDATE}" == "1" ]]; then
  printf "  Reload your shell first:\n"
  printf "    ${B}source ~/.zshrc${RST}  ${DIM}(or ~/.bashrc)${RST}\n\n"
fi

printf "    ${B}oosh${RST} ${CY}<name>${RST}\n\n"
