#!/bin/bash
#
#     ___    ___    ___   _
#    / _ \  / _ \  / __| | |__
#   | (_) || (_) | \__ \ | '_ \
#    \___/  \___/  |___/ |_| |_|
#
# Annotation-driven bash CLI framework.
# Function discovery, flag parsing, help and autocompletion.
#
# Annotations:  #@public  #@protected  #@flag  #@description  #@module
# Flag syntax:  #@flag -e|--env VARNAME "default" [file|dir]
#
# Usage:
#   source oo.sh
#   #@flag -e|--environment ENVIRONMENT "production"
#   #@description target environment
#   #@public
#   #@description run the script
#   function run() { ... }
#   main $0 "$@"
#

GLOBAL_SCRIPT=""
GLOBAL_METHODS=""
GLOBAL_FLAGS=""
GLOBAL_PREFIX=""
_SL_FILE_FLAGS=""
_SL_DIR_FLAGS=""

# --- colors (set OO_COLOR=0 to disable, or export NO_COLOR) ---
OO_COLOR="${OO_COLOR:-1}"
[[ -n "${NO_COLOR:-}" ]] && OO_COLOR=0
if [[ "$OO_COLOR" == "1" ]]; then
  _B=$'\033[1m'  _DIM=$'\033[2m'  _RST=$'\033[0m'
  _CY=$'\033[36m'  _GR=$'\033[32m'  _YL=$'\033[33m'  _RD=$'\033[31m'  _MG=$'\033[35m'
else
  _B=""  _DIM=""  _RST=""  _CY=""  _GR=""  _YL=""  _RD=""  _MG=""
fi

# --- utilities ---
_requires()            { [[ -n "$(command -v "$1")" ]] || { _error "$1 is not installed, please install $1 first"; exit 1; }; }
_write_to_profile()    { local f="$1"; shift; [[ -f "$f" ]] && ! grep -qF "$*" "$f" && echo "$*" >> "$f"; }
_remove_from_profile() { local f="$1"; shift; [[ -f "$f" ]] && grep -vF "$*" "$f" > "$f.tmp" && mv "$f.tmp" "$f"; }
_info()  { printf "  ${_GR}✔${_RST}  %s\n" "$*"; }
_error() { printf "  ${_RD}✘${_RST}  %s\n" "$*" >&2; }
_die()   { _error "$*"; exit 1; }

_default_shortlist() {
  if [[ -n "$1" ]] && printf '%b\n' "$GLOBAL_METHODS" | grep -q "^${1} "; then
    if [[ -n "$2" && "$2" =~ ^- ]]; then
      [[ " ${_SL_FILE_FLAGS}" == *" ${2} "* ]] && echo __file__
      [[ " ${_SL_DIR_FLAGS}" == *" ${2} "* ]] && echo __dir__
      return 0
    fi
    printf '%b\n' "$GLOBAL_FLAGS" | cut -f 1 -d " " | tr "|" " "
  elif [[ -n "$1" && "$1" =~ ^- ]]; then
    [[ " ${_SL_FILE_FLAGS}" == *" ${1} "* ]] && echo __file__
    [[ " ${_SL_DIR_FLAGS}" == *" ${1} "* ]] && echo __dir__
    return 0
  else
    printf '%b\n' "$GLOBAL_METHODS" | cut -f 1 -d " "
    echo help
  fi
}

_default_help() {
  local name="${_B}${GLOBAL_PREFIX}$(basename "${GLOBAL_SCRIPT//.sh/}")${_RST}"
  local methods=$(printf '%b\n' "$GLOBAL_METHODS" | cut -f 1 -d " " | tr '\n' ' ')
  local flags=$(printf '%b\n' "$GLOBAL_FLAGS" | cut -f 1 -d " " | sed -E 's/\|[^[:space:]]+//g' | tr '\n' ' ')

  printf "\n  ${_DIM}Usage:${_RST} ${name} ${_CY}[ ${methods}help ]${_RST}"
  if [[ -n "$GLOBAL_FLAGS" ]]; then
    printf " ${_YL}[ ${flags}]${_RST}\n"
    printf "\n  ${_B}Flags:${_RST}\n"
    printf '%b\n' "$GLOBAL_FLAGS" | while IFS= read -r line; do
      local flag="${line%% *}"
      local rest="${line#* }"
      rest="${rest#"${rest%%[![:space:]]*}"}"
      printf "  ${_YL}%-20s${_RST} ${_DIM}%s${_RST}\n" "$flag" "$rest"
    done
    echo ""
  else
    printf "\n\n"
  fi
  printf "  ${_B}Commands:${_RST}\n"
  printf '%b\n' "$GLOBAL_METHODS" | while IFS= read -r line; do
    local cmd="${line%% *}"
    local rest="${line#* }"
    rest="${rest#"${rest%%[![:space:]]*}"}"
    printf "  ${_CY}%-20s${_RST} ${_DIM}%s${_RST}\n" "$cmd" "$rest"
  done
  printf "  ${_CY}%-20s${_RST} ${_DIM}%s${_RST}\n" "help" "show options and flags available"
  echo ""
}

_default_call() {
  local first="$1"; shift
  if printf '%b\n' "$GLOBAL_METHODS" | grep -q "^${first} "; then
    "$first" "$@"; exit 0
  fi
  case "$first" in
    shortlist) _shortlist "$@" ;;
    *)         _help ;;
  esac
}

# Override stubs — modules redefine these to customise behaviour
_shortlist() { _default_shortlist "$@"; }
_help()      { _default_help "$@"; }
_call()      { _default_call "$@"; }

main() {
  local script="$1"; shift
  local s=$'\x1F' str=""
  (( $# )) && printf -v str "${s}%s" "$@"
  local flags="" methods="" file_flags="" dir_flags=""
  local p_vis="" p_desc="" p_flag="" p_var="" p_def="" p_fdesc="" p_ftype=""

  # Flush pending flag: build help string + extract value from args
  _flush_flag() {
    [[ -z "$p_flag" ]] && return
    flags+=$(printf "$([[ -n "$flags" ]] && echo '\\n')%-20s %s" "$p_flag" "$p_fdesc")

    if [[ "$str" =~ ${s}($p_flag)([$s=])([^$s]*) ]]; then
      local val="${BASH_REMATCH[3]}"; val="${val#\"}"; val="${val%\"}"; val="${val#\'}"; val="${val%\'}"
      export "$p_var=$val"; str="${str/${BASH_REMATCH[0]}/}"
    else
      [[ -z "${!p_var}" ]] && export "$p_var=$p_def"
    fi
    case "$p_ftype" in
      file) file_flags+="${p_flag//|/ } " ;;
      dir)  dir_flags+="${p_flag//|/ } " ;;
    esac
    p_flag="" p_var="" p_def="" p_fdesc="" p_ftype=""
  }

  while IFS= read -r line; do
    local t="${line#"${line%%[![:space:]]*}"}"
    case "$t" in
      '#@public'*|'#@protected'*)
        _flush_flag
        [[ "$t" == '#@public'* ]] && p_vis=public || p_vis=protected ;;
      '#@flag '*)
        _flush_flag
        [[ "$t" =~ ^#@flag[[:space:]]+([^[:space:]]+)[[:space:]]+([A-Z_][A-Z0-9_]*)[[:space:]]+\"([^\"]*)\"[[:space:]]*([a-z]*) ]]
        p_flag="${BASH_REMATCH[1]}"; p_var="${BASH_REMATCH[2]}"; p_def="${BASH_REMATCH[3]}"; p_ftype="${BASH_REMATCH[4]}" ;;
      '#@description '*)
        [[ -n "$p_flag" ]] && p_fdesc="${t#'#@description '}" || p_desc="${t#'#@description '}" ;;
      '#@'*|'#'*|'') ;;
      'function '*)
        _flush_flag
        if [[ "$t" =~ ^function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_-]*)[[:space:]]*\(\) && -n "$p_vis" ]]; then
          local fname="${BASH_REMATCH[1]}"
          [[ "$p_vis" == public ]] && \
            methods+=$(printf "$([[ -n "$methods" ]] && echo '\\n')%-20s %s" "$fname" "$p_desc")
        fi
        p_vis="" p_desc="" ;;
      *) _flush_flag; p_vis="" p_desc="" ;;
    esac
  done < "$script"
  _flush_flag; unset -f _flush_flag

  GLOBAL_SCRIPT="$script"
  GLOBAL_FLAGS="$flags"
  GLOBAL_METHODS="$methods"
  _SL_FILE_FLAGS="$file_flags"
  _SL_DIR_FLAGS="$dir_flags"

  str="${str#${s}}"
  local old_ifs="$IFS"; IFS="$s"; local all=($str); IFS="$old_ifs"
  _call "${all[@]}"
}
