#!/usr/bin/env bash
#
# oosh installer
#
# Usage: curl -fsSL https://raw.githubusercontent.com/bruno-de-queiroz/oosh/main/install.sh | bash
#

set -euo pipefail

OOSH_REPO="${OOSH_REPO:-https://raw.githubusercontent.com/bruno-de-queiroz/oosh/main}"
[[ "$OOSH_REPO" =~ ^https:// ]] || { printf "error: OOSH_REPO must use https://\n" >&2; exit 1; }
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

printf "  ${CY}↓${RST}  lint.sh\n"
curl -fsSL "${OOSH_REPO}/lint.sh" -o "${OOSH_HOME}/lint.sh"
chmod +x "${OOSH_HOME}/lint.sh"

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
  lint) shift; exec bash "${OOSH_HOME}/lint.sh" "\$@" ;;
  *)        exec bash "${OOSH_HOME}/generate.sh" "\$@" ;;
esac
EOF
chmod +x "${OOSH_HOME}/oosh"
ln -sf "${OOSH_HOME}/oosh" "${BIN_DIR}/oosh"
printf "  ${OK}  ${B}oosh${RST} ${DIM}→ ${BIN_DIR}/oosh${RST}\n"

# --- oosh tab completion ---
cat > "${OOSH_HOME}/oosh.comp.sh" << 'COMP'
_oosh_complete() {
  local cur="${COMP_WORDS[COMP_CWORD]}"
  case "${COMP_CWORD}" in
    1) COMPREPLY=($(compgen -W "trace lint" -- "$cur")) ;;
    *) COMPREPLY=($(compgen -f -- "$cur")) ;;
  esac
}
complete -F _oosh_complete oosh
COMP

cat > "${OOSH_HOME}/oosh.zcomp.sh" << 'ZCOMP'
_oosh_complete() {
  case "$CURRENT" in
    2) compadd -- trace lint ;;
    *) _files ;;
  esac
}
compdef _oosh_complete oosh
ZCOMP

_add_comp_to_profile() {
  local f="$1"
  [ -f "$f" ] || return 0
  if [[ "$f" == *".zshrc" ]]; then
    grep -qF "oosh.zcomp.sh" "$f" || printf '\n# oosh completion\n[[ -f "%s" ]] && source "%s"\n' "${OOSH_HOME}/oosh.zcomp.sh" "${OOSH_HOME}/oosh.zcomp.sh" >> "$f"
  else
    grep -qF "oosh.comp.sh" "$f" || printf '\n# oosh completion\n[[ -f "%s" ]] && . "%s"\n' "${OOSH_HOME}/oosh.comp.sh" "${OOSH_HOME}/oosh.comp.sh" >> "$f"
  fi
}
_add_comp_to_profile "${HOME}/.bashrc"
_add_comp_to_profile "${HOME}/.bash_profile"
_add_comp_to_profile "${HOME}/.zshrc"
printf "  ${OK}  oosh tab completion configured\n"

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

# --- Claude Code skill (optional) ---
if [[ -d "${HOME}/.claude" ]]; then
  printf "  ${DOT}  ${B}Claude Code detected.${RST} ${DIM}Install /oosh skill? (Y/n)${RST} "
  read -n 1 -r REPLY; echo ""
  if [[ "${REPLY:-y}" =~ ^[Yy]$ ]]; then
    local _skill _skills="oosh oosh-module oosh-lint oosh-trace"
    mkdir -p "${HOME}/.claude/skills/oosh/references"
    for _skill in $_skills; do
      mkdir -p "${HOME}/.claude/skills/${_skill}"
      curl -fsSL "${OOSH_REPO}/skill/${_skill}/SKILL.md" -o "${HOME}/.claude/skills/${_skill}/SKILL.md"
    done
    curl -fsSL "${OOSH_REPO}/skill/references/annotations.md" -o "${HOME}/.claude/skills/oosh/references/annotations.md"
    printf "  ${OK}  ${B}/oosh /oosh-module /oosh-lint /oosh-trace${RST} ${DIM}skills installed${RST}\n"
  fi
fi

# --- done ---
printf "\n  ${GR}${B}Done!${RST} ${DIM}Get started:${RST}\n\n"

if [[ "${NEEDS_PATH_UPDATE}" == "1" ]]; then
  printf "  Reload your shell first:\n"
  printf "    ${B}source ~/.zshrc${RST}  ${DIM}(or ~/.bashrc)${RST}\n\n"
fi

printf "    ${B}oosh${RST} ${CY}<name>${RST}           ${DIM}generate a new CLI${RST}\n"
printf "    ${B}oosh trace${RST} ${CY}<name>${RST}     ${DIM}profile tab-completion performance${RST}\n"
printf "    ${B}oosh lint${RST} ${CY}<name>${RST}      ${DIM}lint annotations and auto-fix with --fix${RST}\n\n"
