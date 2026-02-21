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
# Annotations:  #@public  #@protected  #@flag  #@description  #@module  #@version
# Flag syntax:  #@flag -e|--env VARNAME "default" [file|dir|boolean|number|enum(...)|array|array(enum(...))] [~ description]
#
# Usage:
#   source oo.sh
#   #@flag -e|--environment ENVIRONMENT "production" ~ target environment
#   #@public ~ run the script
#   function run() { ... }
#   main $0 "$@"
#

OO_VERSION="0.3.0"

GLOBAL_SCRIPT=""
GLOBAL_METHODS=""
GLOBAL_FLAGS=""
GLOBAL_PREFIX=""
GLOBAL_VERSION=""
_SL_FILE_FLAGS=""
_SL_DIR_FLAGS=""
_SL_ENUM=""

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

_resolve_enum() {
  local _el=" ${_SL_ENUM}" _key="$1"
  local _re_dyn='^\$\{([^}]+)\}$'
  if [[ "$_el" == *" ${_key}="* ]]; then
    local _tmp="${_el#* ${_key}=}"; _tmp="${_tmp%% *}"
    if [[ "$_tmp" =~ $_re_dyn ]]; then
      "${BASH_REMATCH[1]}" 2>/dev/null
    else
      echo "${_tmp}" | tr ',' ' '
    fi
  fi
}

_default_shortlist() {
  if [[ -n "$1" ]] && printf '%b\n' "$GLOBAL_METHODS" | grep -q "^${1} "; then
    if [[ -n "$2" && "$2" =~ ^- ]]; then
      if [[ " ${_SL_FILE_FLAGS}" == *" ${2} "* || " ${_SL_FILE_FLAGS}" == *" ${1}:${2} "* ]]; then
        echo __file__
      elif [[ " ${_SL_DIR_FLAGS}" == *" ${2} "* || " ${_SL_DIR_FLAGS}" == *" ${1}:${2} "* ]]; then
        echo __dir__
      else
        local _r=$(_resolve_enum "${2}"); [[ -z "$_r" ]] && _r=$(_resolve_enum "${1}:${2}")
        [[ -n "$_r" ]] && echo "$_r"
      fi
      return 0
    fi
    printf '%b\n' "$GLOBAL_FLAGS" | grep -v ':' | cut -f 1 -d " " | tr "|" " "
    printf '%b\n' "$GLOBAL_FLAGS" | grep "^${1}:" | sed "s/^${1}://" | cut -f 1 -d " " | tr "|" " "
  elif [[ -n "$1" && "$1" =~ ^- ]]; then
    if [[ " ${_SL_FILE_FLAGS}" == *" ${1} "* ]]; then
      echo __file__
    elif [[ " ${_SL_DIR_FLAGS}" == *" ${1} "* ]]; then
      echo __dir__
    else
      local _r=$(_resolve_enum "${1}"); [[ -n "$_r" ]] && echo "$_r"
    fi
    return 0
  else
    printf '%b\n' "$GLOBAL_METHODS" | cut -f 1 -d " "
    echo help
  fi
}

_default_help() {
  local name="${_B}${GLOBAL_PREFIX}$(basename "${GLOBAL_SCRIPT//.sh/}")${_RST}"
  local methods=$(printf '%b\n' "$GLOBAL_METHODS" | cut -f 1 -d " " | tr '\n' ' ')
  local flags=$(printf '%b\n' "$GLOBAL_FLAGS" | grep -v ':' | cut -f 1 -d " " | sed -E 's/\|[^[:space:]]+//g' | tr '\n' ' ')

  printf "\n  ${_DIM}Usage:${_RST} ${name} ${_CY}[ ${methods}help ]${_RST}"
  if [[ -n "$GLOBAL_FLAGS" ]]; then
    [[ -n "$flags" ]] && printf " ${_YL}[ ${flags}]${_RST}\n" || printf "\n"
    local module_flags=$(printf '%b\n' "$GLOBAL_FLAGS" | grep -v ':')
    if [[ -n "$module_flags" ]]; then
      printf "\n  ${_B}Flags:${_RST}\n"
      printf '%s\n' "$module_flags" | while IFS= read -r line; do
        local flag="${line%% *}"
        local rest="${line#* }"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        printf "  ${_YL}%-20s${_RST} ${_DIM}%s${_RST}\n" "$flag" "$rest"
      done
      echo ""
    else
      printf "\n"
    fi
  else
    printf "\n\n"
  fi
  printf "  ${_B}Commands:${_RST}\n"
  printf '%b\n' "$GLOBAL_METHODS" | while IFS= read -r line; do
    local cmd="${line%% *}"
    local rest="${line#* }"
    rest="${rest#"${rest%%[![:space:]]*}"}"
    printf "  ${_CY}%-20s${_RST} ${_DIM}%s${_RST}\n" "$cmd" "$rest"
    printf '%b\n' "$GLOBAL_FLAGS" | grep "^${cmd}:" | sed "s/^${cmd}://" | while IFS= read -r fline; do
      local ff="${fline%% *}" fr="${fline#* }"; fr="${fr#"${fr%%[![:space:]]*}"}"
      printf "    ${_YL}%-18s${_RST} ${_DIM}%s${_RST}\n" "$ff" "$fr"
    done
  done
  printf "  ${_CY}%-20s${_RST} ${_DIM}%s${_RST}\n" "help" "show options and flags available"
  echo ""
}

_default_version() {
  local name="$(basename "${GLOBAL_SCRIPT//.sh/}")"
  [[ -n "$GLOBAL_VERSION" ]] && printf "%s %s " "$name" "$GLOBAL_VERSION"
  printf "(oosh %s)\n" "$OO_VERSION"
}

_default_call() {
  local first="$1"; shift
  if printf '%b\n' "$GLOBAL_METHODS" | grep -q "^${first} "; then
    "$first" "$@"; exit 0
  fi
  case "$first" in
    shortlist)            _shortlist "$@" ;;
    help|--help|-h)       _help ;;
    version|--version|-V) _version ;;
    *)                    _help ;;
  esac
}

# Override stubs — modules redefine these to customise behaviour
_shortlist() { _default_shortlist "$@"; }
_help()      { _default_help "$@"; }
_call()      { _default_call "$@"; }
_version()   { _default_version "$@"; }

main() {
  local script="$1"; shift
  local s=$'\x1F' str=""
  (( $# )) && printf -v str "${s}%s" "$@"
  local flags="" methods="" file_flags="" dir_flags="" enum_flags="" version=""
  local p_vis="" p_desc="" p_flag="" p_var="" p_def="" p_fdesc="" p_ftype=""
  local mf_help="" mf_file="" mf_dir="" mf_enum=""
  local _oo_array_vars=""

  # Regex patterns stored in variables for bash 3.2 compatibility
  local _re_enum_dyn='^enum\(\$\{([^}]+)\}\)$'
  local _re_enum_static='^enum\(([^)]+)\)$'
  local _re_array_typed='^array\((.+)\)$'
  local _re_array_plain='^array$'

  # Flush pending flag: build help string + extract value from args
  _flush_flag() {
    [[ -z "$p_flag" ]] && return
    # Detect array wrapper, then extract inner type
    local _is_array=false _effective_type="$p_ftype"
    if [[ "$p_ftype" =~ $_re_array_typed ]]; then
      _is_array=true; _effective_type="${BASH_REMATCH[1]}"
    elif [[ "$p_ftype" =~ $_re_array_plain ]]; then
      _is_array=true; _effective_type=""
    fi
    # Parse enum — static enum(a,b,c) or dynamic enum(${funcname})
    local _enum_vals="" _enum_dynamic="" _enum_store=""
    if [[ "$_effective_type" =~ $_re_enum_dyn ]]; then
      _enum_dynamic="${BASH_REMATCH[1]}"
      _enum_store='${'"${_enum_dynamic}"'}'
    elif [[ "$_effective_type" =~ $_re_enum_static ]]; then
      _enum_vals="${BASH_REMATCH[1]}"
      _enum_store="$_enum_vals"
    fi
    # Build help line (append enum values to description for static enums)
    local help_desc="$p_fdesc"
    [[ -n "$_enum_vals" ]] && help_desc+=" [${_enum_vals//,/, }]"
    [[ "$_is_array" == true ]] && help_desc+=" (multiple)"
    local help_line=$(printf "%-20s %s" "$p_flag" "$help_desc")
    local _short="${p_flag%%|*}" _long="${p_flag#*|}"

    # --- Value extraction ---
    local _was_set=false
    if [[ "$p_ftype" == "boolean" ]]; then
      if [[ "$str" =~ ${s}($p_flag)([$s=])([^$s]*) ]]; then
        local val="${BASH_REMATCH[3]}"; val="${val#\"}"; val="${val%\"}"; val="${val#\'}"; val="${val%\'}"
        local _consume=false
        [[ "${BASH_REMATCH[2]}" == "=" ]] && _consume=true
        case "$val" in true|false|1|0|yes|no) _consume=true ;; esac
        if [[ "$_consume" == true ]]; then
          [[ -z "$val" ]] && val=true
          printf -v "$p_var" '%s' "$val"; str="${str/${BASH_REMATCH[0]}/}"
        else
          printf -v "$p_var" '%s' "true"; str="${str/${s}${BASH_REMATCH[1]}/}"
        fi
        _was_set=true
      elif [[ "$str" == *"${s}${_short}" || "$str" == *"${s}${_long}" ]]; then
        printf -v "$p_var" '%s' "true"; str="${str/${s}${_short}/}"; str="${str/${s}${_long}/}"
        _was_set=true
      else
        [[ -z "${!p_var}" ]] && printf -v "$p_var" '%s' "$p_def"
      fi
    elif [[ "$_is_array" == true ]]; then
      local _arr_vals="" _arr_sep=$'\x1E'
      while [[ "$str" =~ ${s}($p_flag)([$s=])([^$s]*) ]]; do
        local val="${BASH_REMATCH[3]}"; val="${val#\"}"; val="${val%\"}"; val="${val#\'}"; val="${val%\'}"
        str="${str/${BASH_REMATCH[0]}/}"
        val="${val//,/$_arr_sep}"
        [[ -z "$val" ]] && { _was_set=true; continue; }
        [[ -n "$_arr_vals" ]] && _arr_vals+="$_arr_sep"
        _arr_vals+="$val"
        _was_set=true
      done
      if [[ "$_was_set" == true ]]; then
        printf -v "$p_var" '%s' "$_arr_vals"
      elif [[ -z "${!p_var}" ]]; then
        if [[ -n "$p_def" ]]; then
          printf -v "$p_var" '%s' "${p_def//,/$_arr_sep}"
        else
          printf -v "$p_var" '%s' ""
        fi
      fi
      _oo_array_vars+="$p_var "
    elif [[ "$str" =~ ${s}($p_flag)([$s=])([^$s]*) ]]; then
      local val="${BASH_REMATCH[3]}"; val="${val#\"}"; val="${val%\"}"; val="${val#\'}"; val="${val%\'}"
      printf -v "$p_var" '%s' "$val"; str="${str/${BASH_REMATCH[0]}/}"
      _was_set=true
    else
      [[ -z "${!p_var}" ]] && printf -v "$p_var" '%s' "$p_def"
    fi

    # --- Validation (dynamic enums resolved lazily, only when flag was set) ---
    local _val="${!p_var}"
    if [[ "$_is_array" == true ]]; then
      if [[ -n "$_enum_dynamic" && "$_was_set" == true && -n "$_val" ]]; then
        _enum_vals=$("$_enum_dynamic" 2>/dev/null | tr '\n' ' ')
        _enum_vals="${_enum_vals% }"; _enum_vals="${_enum_vals// /,}"
      fi
      if [[ -n "$_enum_vals" && -n "$_val" ]]; then
        local _old_ifs="$IFS"; IFS=$'\x1E'; local _elems=($_val); IFS="$_old_ifs"
        local _elem; for _elem in "${_elems[@]}"; do
          [[ ",${_enum_vals}," == *",${_elem},"* ]] || _die "invalid value '${_elem}' for $p_flag (expected: ${_enum_vals//,/, })"
        done
      fi
    else
      if [[ -n "$_enum_dynamic" && "$_was_set" == true && -n "$_val" ]]; then
        _enum_vals=$("$_enum_dynamic" 2>/dev/null | tr '\n' ' ')
        _enum_vals="${_enum_vals% }"; _enum_vals="${_enum_vals// /,}"
      fi
      if [[ -n "$_enum_vals" && -n "$_val" ]]; then
        [[ ",${_enum_vals}," == *",${_val},"* ]] || _die "invalid value '${_val}' for $p_flag (expected: ${_enum_vals//,/, })"
      fi
      if [[ "$p_ftype" == "number" && -n "$_val" ]]; then
        [[ "$_val" =~ ^-?[0-9]+\.?[0-9]*$ ]] || _die "invalid value '${_val}' for $p_flag (expected: number)"
      fi
    fi

    # --- Store help + completion info ---
    local _ftype="$p_ftype"
    if [[ "$_ftype" =~ ^array\( ]]; then
      local _inner="${_ftype#array(}"; _inner="${_inner%)}"
      [[ "$_inner" == enum* ]] && _ftype=enum || _ftype=""
    elif [[ "$_ftype" == array ]]; then
      _ftype=""
    elif [[ "$_ftype" == enum* ]]; then
      _ftype=enum
    fi
    if [[ -n "$p_vis" ]]; then
      [[ -n "$mf_help" ]] && mf_help+=$'\n'; mf_help+="$help_line"
      case "$_ftype" in
        file) mf_file+="${_short} ${_long} " ;;
        dir)  mf_dir+="${_short} ${_long} " ;;
        enum) mf_enum+="${_short}=${_enum_store} ${_long}=${_enum_store} " ;;
      esac
    else
      [[ -n "$flags" ]] && flags+=$'\n'; flags+="$help_line"
      case "$_ftype" in
        file) file_flags+="${_short} ${_long} " ;;
        dir)  dir_flags+="${_short} ${_long} " ;;
        enum) enum_flags+="${_short}=${_enum_store} ${_long}=${_enum_store} " ;;
      esac
    fi
    p_flag="" p_var="" p_def="" p_fdesc="" p_ftype=""
  }

  while IFS= read -r line; do
    local t="${line#"${line%%[![:space:]]*}"}"
    # Normalize function declarations: name() { → function name()
    if [[ ! "$t" == '#'* && "$t" =~ ^([a-zA-Z_][a-zA-Z0-9_-]*)[[:space:]]*\(\)[[:space:]]*\{?[[:space:]]*$ ]]; then
      t="function ${BASH_REMATCH[1]}()"
    elif [[ "$t" =~ ^function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_-]*)[[:space:]]*\(\)[[:space:]]*\{? ]]; then
      t="function ${BASH_REMATCH[1]}()"
    fi
    case "$t" in
      '#@public'*|'#@protected'*)
        _flush_flag
        [[ "$t" == '#@public'* ]] && p_vis=public || p_vis=protected
        [[ "$t" =~ ~[[:space:]]+(.*) ]] && p_desc="${BASH_REMATCH[1]}" ;;
      '#@flag '*)
        _flush_flag
        [[ "$t" =~ ^#@flag[[:space:]]+([^[:space:]]+)[[:space:]]+([A-Z_][A-Z0-9_]*)[[:space:]]+\"([^\"]*)\"[[:space:]]*([^[:space:]~]*)[[:space:]]*(~[[:space:]]+(.*))? ]]
        p_flag="${BASH_REMATCH[1]}"; p_var="${BASH_REMATCH[2]}"; p_def="${BASH_REMATCH[3]}"; p_ftype="${BASH_REMATCH[4]}"; p_fdesc="${BASH_REMATCH[6]}" ;;
      '#@description '*)
        [[ -n "$p_flag" ]] && p_fdesc="${t#'#@description '}" || p_desc="${t#'#@description '}" ;;
      '#@version '*)
        version="${t#'#@version '}" ;;
      '#@'*|'#'*|'') ;;
      'function '*)
        _flush_flag
        if [[ "$t" =~ ^function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_-]*)[[:space:]]*\(\) && -n "$p_vis" ]]; then
          local fname="${BASH_REMATCH[1]}"
          [[ "$p_vis" == public ]] && \
            methods+=$(printf "$([[ -n "$methods" ]] && echo '\\n')%-20s %s" "$fname" "$p_desc")
          if [[ -n "$mf_help" ]]; then
            while IFS= read -r _ml; do
              [[ -n "$flags" ]] && flags+=$'\n'; flags+="${fname}:${_ml}"
            done <<< "$mf_help"
          fi
          if [[ -n "$mf_file" ]]; then
            for _t in $mf_file; do file_flags+="${fname}:${_t} "; done
          fi
          if [[ -n "$mf_dir" ]]; then
            for _t in $mf_dir; do dir_flags+="${fname}:${_t} "; done
          fi
          if [[ -n "$mf_enum" ]]; then
            for _t in $mf_enum; do enum_flags+="${fname}:${_t} "; done
          fi
        fi
        p_vis="" p_desc="" mf_help="" mf_file="" mf_dir="" mf_enum="" ;;
      *) _flush_flag; p_vis="" p_desc="" mf_help="" mf_file="" mf_dir="" mf_enum="" ;;
    esac
  done < "$script"
  _flush_flag; unset -f _flush_flag

  GLOBAL_SCRIPT="$script"
  GLOBAL_FLAGS="$flags"
  GLOBAL_METHODS="$methods"
  GLOBAL_VERSION="$version"
  _SL_FILE_FLAGS="$file_flags"
  _SL_DIR_FLAGS="$dir_flags"
  _SL_ENUM="$enum_flags"

  str="${str#${s}}"

  local _av; for _av in $_oo_array_vars; do
    local _raw="${!_av}"
    if [[ -n "$_raw" ]]; then
      local _old_ifs="$IFS"; IFS=$'\x1E'; eval "$_av=(\$_raw)"; IFS="$_old_ifs"
    else
      eval "$_av=()"
    fi
  done

  local old_ifs="$IFS"; IFS="$s"; local all=($str); IFS="$old_ifs"
  _call "${all[@]}"
}
