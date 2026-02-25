#!/bin/bash
#
# oosh — CLI generator
#
# Usage: ./generate.sh <name> [output-dir]
#
#   <name>       CLI tool name (e.g., sc, devops, mytool)
#   [output-dir] Where to create it (defaults to ~/.<name>)
#

set -euo pipefail

# --- colors & symbols (respect --no-color flag and NO_COLOR env) ---
_USE_COLOR=1
[[ -n "${NO_COLOR:-}" ]] && _USE_COLOR=0
# parse --no-color before positional args
_ARGS=()
for _a in "$@"; do
  [[ "$_a" == "--no-color" ]] && _USE_COLOR=0 || _ARGS+=("$_a")
done
set -- "${_ARGS[@]+"${_ARGS[@]}"}"

if [[ "$_USE_COLOR" == "1" ]]; then
  B=$'\033[1m'  DIM=$'\033[2m'  RST=$'\033[0m'
  CY=$'\033[36m'  GR=$'\033[32m'  MG=$'\033[35m'  YL=$'\033[33m'  RD=$'\033[31m'
else
  B=""  DIM=""  RST=""  CY=""  GR=""  MG=""  YL=""  RD=""
fi
OK="${GR}✔${RST}"  ERR="${RD}✘${RST}"  DOT="${MG}◆${RST}"  ARROW="${CY}▸${RST}"

_step() { printf "  ${OK}  ${B}%-22s${RST} ${DIM}%s${RST}\n" "$1" "$2"; }
_head() { printf "\n  ${DOT}  ${B}%s${RST}\n\n" "$*"; }
_fail() { printf "\n  ${ERR}  ${RD}%s${RST}\n\n" "$*" >&2; exit 1; }

# --- args ---
_resolve() { local s="$1"; while [ -L "$s" ]; do local d="$(cd "$(dirname "$s")" && pwd)"; s="$(readlink "$s")"; [[ "$s" != /* ]] && s="$d/$s"; done; echo "$s"; }
OOSH_DIR="$(cd "$(dirname "$(_resolve "$0")")" && pwd)"

[[ $# -lt 1 ]] && { printf "\n  ${B}Usage:${RST} $0 ${CY}<name>${RST} ${DIM}[--no-color] [output-dir]${RST}\n\n"; exit 1; }

NAME="$1"
NAME_UPPER="$(echo "$NAME" | tr '[:lower:]' '[:upper:]')"
[[ -n "${2:-}" ]] && OUT_DIR="${2}/${NAME}" || OUT_DIR="${HOME}/.${NAME}"

# --- banner ---
printf "\n${MG}"
printf '    ___    ___    ___   _\n'
printf '   / _ \\  / _ \\  / __| | |__\n'
printf '  | (_) || (_) | \\__ \\ | '"'"'_ \\\n'
printf '   \\___/  \\___/  |___/ |_| |_|\n'
printf "${RST}\n"
_head "${NAME} ${DIM}→${RST} ${B}${OUT_DIR}"

if [[ -d "$OUT_DIR" ]]; then
  if [[ -f "${OUT_DIR}/oo.sh" ]]; then
    printf "  ${DOT}  ${B}${OUT_DIR} already exists.${RST} ${DIM}Update oo.sh? (Y/n)${RST} "
    read -n 1 -r REPLY; echo ""
    if [[ "${REPLY:-y}" =~ ^[Yy]$ ]]; then
      cp "${OOSH_DIR}/oo.sh" "${OUT_DIR}/oo.sh"
      _step "oo.sh" "framework updated"
      printf "\n  ${GR}${B}Done!${RST}\n\n"
    else
      printf "  ${DIM}   Skipped${RST}\n\n"
    fi
    exit 0
  else
    _fail "${OUT_DIR} already exists (not an oosh project)"
  fi
fi

mkdir -p "${OUT_DIR}/modules"

# --- oo.sh (copy from oosh) ---
cp "${OOSH_DIR}/oo.sh" "${OUT_DIR}/oo.sh"
_step "oo.sh" "framework engine"

# --- entry point (<name>.sh) ---
cat > "${OUT_DIR}/${NAME}.sh" <<ENTRY
#!/bin/bash
export ${NAME_UPPER}_DIR="\${${NAME_UPPER}_DIR:-\$HOME/.${NAME}}"
export MODULES_DIR="\${${NAME_UPPER}_DIR}/modules"

#import oo.sh
. "\${${NAME_UPPER}_DIR}/oo.sh"

MODULES=""
for _f in "\${MODULES_DIR}"/*.sh; do
  [[ -f "\$_f" ]] && MODULES="\${MODULES:+\${MODULES} }\$(basename "\${_f%.sh}")"
done
unset _f

function _shortlist() {
  local all=("\$@")
  local module="\${all[0]}"

  if [[ -f "\${MODULES_DIR}/\${module}.sh" ]]; then
    all=("\${all[@]:1}")
    "\${MODULES_DIR}/\${module}.sh" shortlist "\${all[@]}"
  else
    _default_shortlist "\$@"
    echo "\$MODULES"
  fi
}

function _help() {
  printf "\n  \${_DIM}Usage:\${_RST} \${_B}${NAME}\${_RST} \${_CY}[ \${MODULES} help ]\${_RST}\n"
  printf "\n  \${_B}Commands:\${_RST}\n"
  printf "  \${_CY}%-20s\${_RST} \${_DIM}%s\${_RST}\n" "help" "show options and flags available"
  printf "\n  \${_B}Modules:\${_RST}\n"
  for module in \$MODULES; do
    if [[ -f "\${MODULES_DIR}/\${module}.sh" ]]; then
      local description
      description="\$(grep -E '^#@module' "\${MODULES_DIR}/\${module}.sh" | sed -E 's/#@module[[:space:]]*(.*)/\1/')"
      printf "  \${_MG}%-20s\${_RST} \${_DIM}%s\${_RST}\n" "\$module" "\$description"
    fi
  done
  echo ""
}

function _call() {
  local all=("\$@")
  local module="\${all[0]}"

  if [[ -f "\${MODULES_DIR}/\${module}.sh" ]]; then
    all=("\${all[@]:1}")
    "\${MODULES_DIR}/\${module}.sh" "\${all[@]}"
  else
    _default_call "\$@"
  fi
}

main "\$0" "\$@"
ENTRY
_step "${NAME}.sh" "entry point"

# --- completion script (<name>.comp.sh) ---
cat > "${OUT_DIR}/${NAME}.comp.sh" <<COMP
#!/bin/bash
_${NAME}() {
  local cur opts src
  COMPREPLY=()

  src="\${${NAME_UPPER}_PATH}/${NAME}"
  cur="\${COMP_WORDS[COMP_CWORD]}"

  opts=\$("\$src" shortlist "\${COMP_WORDS[@]:1:COMP_CWORD-1}")
  case "\$opts" in
    __file__)
      compopt -o filenames 2>/dev/null
      COMPREPLY=(\$(compgen -f -- "\${cur}")) ;;
    __dir__)
      compopt -o filenames 2>/dev/null
      COMPREPLY=(\$(compgen -d -- "\${cur}")) ;;
    *)
      compopt +o filenames 2>/dev/null
      COMPREPLY=(\$(compgen -W "\${opts}" -- "\${cur}")) ;;
  esac
  return 0
}
complete -o filenames -F _${NAME} ${NAME}
COMP
_step "${NAME}.comp.sh" "bash completion"

# --- sample module (hello.sh) ---
cat > "${OUT_DIR}/modules/hello.sh" <<'MODULE'
#!/bin/bash
#@module Hello - sample module demonstrating oosh annotations

#import oo.sh
. ${MODULES_DIR}/../oo.sh

#@flag -n|--name HELLO_NAME "world" ~ who to greet
#@flag -u|--uppercase HELLO_UPPERCASE "false" boolean ~ uppercase the greeting

#@public ~ say hello
function greet() {
  local msg="Hello, ${HELLO_NAME}!"
  [[ "$HELLO_UPPERCASE" == true ]] && msg="$(echo "$msg" | tr '[:lower:]' '[:upper:]')"
  echo "$msg"
}

#@public ~ say goodbye
function farewell() {
  echo "Goodbye, ${HELLO_NAME}!"
}

#@protected ~ internal helper
function _format() {
  echo "(this is a protected method)"
}

# Bootstraps the parser
main $0 "$@"
MODULE
_step "modules/hello.sh" "sample module"

# --- install module (install.sh) ---
cat > "${OUT_DIR}/modules/install.sh" <<INSTALL
#!/bin/bash
#@module Install - install and configure the ${NAME} CLI

#import oo.sh
. \${MODULES_DIR}/../oo.sh

PROFILES=(\${HOME}/.bashrc \${HOME}/.zshrc)

function _call() {
  [[ \$# -eq 0 ]] && { cli; return; }
  _default_call "\$@"
}

#@protected ~ find a writable bin directory
function _find_bin_dir() {
  local d
  for d in /opt/homebrew/bin /usr/local/bin \${HOME}/.local/bin; do
    [[ -d "\$d" && -w "\$d" ]] && { echo "\$d"; return; }
  done
  # last resort: create ~/.local/bin
  mkdir -p "\${HOME}/.local/bin"
  for i in \${PROFILES[@]}; do
    _write_to_profile \$i 'export PATH="\$HOME/.local/bin:\$PATH"'
  done
  echo "\${HOME}/.local/bin"
}

#@protected ~ find bash completion directory
function _find_comp_dir() {
  local d
  for d in /opt/homebrew/etc/bash_completion.d \
           /usr/local/etc/bash_completion.d \
           /opt/local/etc/bash_completion.d \
           /etc/bash_completion.d \
           /usr/share/bash-completion/completions; do
    [[ -d "\$d" && -w "\$d" ]] && { echo "\$d"; return; }
  done
  # fallback: user-level dir
  d="\${HOME}/.bash_completion.d"
  mkdir -p "\$d"
  local entry='for f in ~/".bash_completion.d/"*; do [[ -f "\$f" ]] && . "\$f"; done'
  for i in \${PROFILES[@]}; do
    _write_to_profile \$i "\$entry"
  done
  echo "\$d"
}

#@public ~ install the ${NAME} cli
function cli() {
  if [[ -n \$(command -v ${NAME}) ]]; then
    _info "${NAME} is already installed"
    return 0
  fi

  local binDir=\$(_find_bin_dir)
  local compDir=\$(_find_comp_dir)

  ln -s ${OUT_DIR}/${NAME}.sh \$binDir/${NAME}
  ln -s ${OUT_DIR}/${NAME}.comp.sh \$compDir/${NAME}

  for i in \${PROFILES[@]}; do
    _write_to_profile \$i "export ${NAME_UPPER}_DIR=${OUT_DIR}"
    _write_to_profile \$i "export ${NAME_UPPER}_PATH=\$binDir"
    if [[ "\$i" == *".zshrc" ]]; then
      _write_to_profile \$i "autoload -Uz compinit && compinit"
      _write_to_profile \$i "autoload -Uz bashcompinit && bashcompinit"
    fi
    _write_to_profile \$i "[[ -f ${OUT_DIR}/${NAME}.comp.sh ]] && . ${OUT_DIR}/${NAME}.comp.sh"
  done

  _info "${NAME} installed successfully"
}

# Bootstraps the parser
main \$0 "\$@"
INSTALL
_step "modules/install.sh" "CLI installer"

# --- uninstall module (uninstall.sh) ---
cat > "${OUT_DIR}/modules/uninstall.sh" <<UNINSTALL
#!/bin/bash
#@module Uninstall - remove ${NAME} from the system

#import oo.sh
. \${MODULES_DIR}/../oo.sh

PROFILES=(\${HOME}/.bashrc \${HOME}/.zshrc)

function _call() {
  [[ \$# -eq 0 ]] && { cli; return; }
  _default_call "\$@"
}

#@public ~ uninstall ${NAME} and remove all files
function cli() {
  read -p "Remove ${NAME} and delete ${OUT_DIR}? (y/N) " -n 1 -r
  echo ""
  [[ ! "\$REPLY" =~ ^[Yy]\$ ]] && { _info "aborted"; return 0; }

  # remove symlinks
  local bin=\$(command -v ${NAME} 2>/dev/null)
  [[ -L "\$bin" ]] && rm -f "\$bin"

  local d
  for d in /opt/homebrew/etc/bash_completion.d \
           /usr/local/etc/bash_completion.d \
           /opt/local/etc/bash_completion.d \
           /etc/bash_completion.d \
           /usr/share/bash-completion/completions \
           \${HOME}/.bash_completion.d; do
    [[ -L "\$d/${NAME}" ]] && rm -f "\$d/${NAME}"
  done

  # clean profiles
  for i in \${PROFILES[@]}; do
    _remove_from_profile \$i "export ${NAME_UPPER}_DIR="
    _remove_from_profile \$i "export ${NAME_UPPER}_PATH="
    _remove_from_profile \$i "${OUT_DIR}/${NAME}.comp.sh"
  done

  # remove tool directory
  rm -rf "${OUT_DIR}"

  _info "${NAME} uninstalled"
}

# Bootstraps the parser
main \$0 "\$@"
UNINSTALL
_step "modules/uninstall.sh" "CLI uninstaller"

chmod +x "${OUT_DIR}/${NAME}.sh" "${OUT_DIR}/modules/hello.sh" "${OUT_DIR}/modules/install.sh" "${OUT_DIR}/modules/uninstall.sh"

# --- color prompt ---
printf "\n  ${DOT}  ${B}Enable colored output?${RST} ${DIM}(Y/n)${RST} "
read -n 1 -r REPLY
echo ""
if [[ ! "${REPLY:-y}" =~ ^[Yy]$ ]]; then
  sed 's/OO_COLOR="${OO_COLOR:-1}"/OO_COLOR="${OO_COLOR:-0}"/' "${OUT_DIR}/oo.sh" > "${OUT_DIR}/oo.sh.tmp" && mv "${OUT_DIR}/oo.sh.tmp" "${OUT_DIR}/oo.sh"
  printf "  ${DIM}   Colors disabled — edit OO_COLOR in oo.sh to re-enable${RST}\n"
fi

# --- install prompt ---
printf "\n  ${DOT}  ${B}Install ${NAME} to PATH?${RST} ${DIM}(Y/n)${RST} "
read -n 1 -r REPLY
echo ""

_CLR=$'\r\033[2K'
[[ "$_USE_COLOR" == "0" ]] && _CLR=$'\n'

if [[ "${REPLY:-y}" =~ ^[Yy]$ ]]; then
  printf "  ${ARROW}  Installing..."
  if env "${NAME_UPPER}_DIR=${OUT_DIR}" bash "${OUT_DIR}/${NAME}.sh" install >/dev/null 2>&1; then
    printf "${_CLR}  ${OK}  ${B}Installed${RST}\n"
  else
    printf "${_CLR}  ${ERR}  ${RD}Installation failed${RST} ${DIM}— run '${NAME} install' later${RST}\n"
  fi
else
  printf "  ${DIM}   Skipped — run '${NAME} install' later${RST}\n"
fi

# --- next steps ---
printf "\n  ${GR}${B}Done!${RST} ${DIM}Get started:${RST}\n"
printf "\n    ${ARROW}  ${B}${NAME} help${RST}"
printf "\n    ${ARROW}  ${B}${NAME} hello greet${RST}"
printf "\n    ${ARROW}  ${B}${NAME} hello greet --name ${YL}World${RST}"
printf "\n\n  ${DIM}Open a new shell or run:${RST}"
printf "\n    ${B}source ${OUT_DIR}/${NAME}.comp.sh${RST}"
printf "\n\n"
