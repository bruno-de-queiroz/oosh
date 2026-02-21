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
_die()   { _error "$*"; exit 2; }

_resolve_enum() {
  local _el=" ${_SL_ENUM}" _key="$1"
  local _re_dyn='^\$\{([^}]+)\}$'
  if [[ "$_el" == *" ${_key}="* ]]; then
    local _tmp="${_el#* ${_key}=}"; _tmp="${_tmp%% *}"
    if [[ "$_tmp" =~ $_re_dyn ]]; then
      "${BASH_REMATCH[1]}" 2>/dev/null
    else
      echo "${_tmp//,/ }"
    fi
  fi
}

_default_shortlist() {
  local _nl=$'\n'
  if [[ -n "$1" ]] && [[ "${_nl}${GLOBAL_METHODS}" == *"${_nl}${1} "* ]]; then
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
    if [[ -n "$GLOBAL_FLAGS" ]]; then
      while IFS= read -r _fl; do
        [[ -z "$_fl" ]] && continue
        if [[ "$_fl" != *:* ]]; then
          local _fn="${_fl%% *}"; echo "${_fn//|/ }"
        elif [[ "$_fl" == "${1}:"* ]]; then
          _fl="${_fl#${1}:}"; local _fn="${_fl%% *}"; echo "${_fn//|/ }"
        fi
      done <<< "$GLOBAL_FLAGS"
    fi
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
    if [[ -n "$GLOBAL_METHODS" ]]; then
      while IFS= read -r _ml; do
        [[ -n "$_ml" ]] && echo "${_ml%% *}"
      done <<< "$GLOBAL_METHODS"
    fi
    echo help
  fi
}

_default_help() {
  local name="${_B}${GLOBAL_PREFIX}$(basename "${GLOBAL_SCRIPT//.sh/}")${_RST}"
  local _methods="" _flags="" _has_module_flags=false
  if [[ -n "$GLOBAL_METHODS" ]]; then
    while IFS= read -r _ml; do
      [[ -n "$_ml" ]] && _methods+="${_ml%% *} "
    done <<< "$GLOBAL_METHODS"
  fi
  if [[ -n "$GLOBAL_FLAGS" ]]; then
    while IFS= read -r _fl; do
      [[ -z "$_fl" || "$_fl" != -* ]] && continue
      local _fn="${_fl%% *}"; _flags+="${_fn%%|*} "
    done <<< "$GLOBAL_FLAGS"
  fi

  printf "\n  ${_DIM}Usage:${_RST} ${name} ${_CY}[ ${_methods}help ]${_RST}"
  if [[ -n "$GLOBAL_FLAGS" ]]; then
    [[ -n "$_flags" ]] && printf " ${_YL}[ ${_flags}]${_RST}\n" || printf "\n"
    if [[ -n "$GLOBAL_FLAGS" ]]; then
      while IFS= read -r line; do
        [[ -z "$line" || "$line" != -* ]] && continue
        if [[ "$_has_module_flags" == false ]]; then
          printf "\n  ${_B}Flags:${_RST}\n"; _has_module_flags=true
        fi
        local flag="${line%% *}" rest="${line#* }"
        rest="${rest#"${rest%%[![:space:]]*}"}"
        printf "  ${_YL}%-20s${_RST} ${_DIM}%s${_RST}\n" "$flag" "$rest"
      done <<< "$GLOBAL_FLAGS"
    fi
    [[ "$_has_module_flags" == true ]] && echo "" || printf "\n"
  else
    printf "\n\n"
  fi
  printf "  ${_B}Commands:${_RST}\n"
  if [[ -n "$GLOBAL_METHODS" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local cmd="${line%% *}" rest="${line#* }"
      rest="${rest#"${rest%%[![:space:]]*}"}"
      printf "  ${_CY}%-20s${_RST} ${_DIM}%s${_RST}\n" "$cmd" "$rest"
      if [[ -n "$GLOBAL_FLAGS" ]]; then
        while IFS= read -r _fl; do
          [[ "$_fl" != "${cmd}:"* ]] && continue
          local fline="${_fl#${cmd}:}"
          local ff="${fline%% *}" fr="${fline#* }"; fr="${fr#"${fr%%[![:space:]]*}"}"
          printf "    ${_YL}%-18s${_RST} ${_DIM}%s${_RST}\n" "$ff" "$fr"
        done <<< "$GLOBAL_FLAGS"
      fi
    done <<< "$GLOBAL_METHODS"
  fi
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
  local _nl=$'\n'
  if [[ -n "$first" ]] && [[ "${_nl}${GLOBAL_METHODS}" == *"${_nl}${first} "* ]]; then
    "$first" "$@"; exit 0
  fi
  case "$first" in
    shortlist)            _shortlist "$@" ;;
    help|--help|-h)       _help ;;
    version|--version|-V) _version ;;
    *)                    _error "unknown command '${first}'"; _help; exit 2 ;;
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
  local _missing_required=""

  # Regex patterns stored in variables for bash 3.2 compatibility
  local _re_enum_dyn='^enum\(\$\{([^}]+)\}\)$'
  local _re_enum_static='^enum\(([^)]+)\)$'
  local _re_array_typed='^array\((.+)\)$'
  local _re_array_plain='^array$'
  local _re_quoted='"(([^"\\]|\\.)*)"'
  local _re_env='^\$\{([A-Z_][A-Z0-9_]*)(:-([^}]+))?\}$'
  local _re_flag='^#@flag[[:space:]]+([^[:space:]]+)[[:space:]]+([A-Z_][A-Z0-9_]*)[[:space:]]+'$_re_quoted'[[:space:]]*([^[:space:]~]*)[[:space:]]*(~[[:space:]]+(.*))?'

  # Flush pending flag: build help string + extract value from args
  _flush_flag() {
    [[ -z "$p_flag" ]] && return
    # Detect required modifier and strip from type
    local _required=false
    case "$p_ftype" in
      required:*) _required=true; p_ftype="${p_ftype#required:}" ;;
      required)   _required=true; p_ftype="" ;;
    esac
    # Detect env var fallback in default (e.g. "${API_KEY}" or "${API_KEY:-fallback}")
    local _env_hint=""
    if [[ "$p_def" =~ $_re_env ]]; then
      _env_hint="${BASH_REMATCH[1]}"
      local _env_fb="${BASH_REMATCH[3]}"
      if [[ -n "${!_env_hint:-}" ]]; then
        p_def="${!_env_hint}"
      elif [[ -n "$_env_fb" ]]; then
        p_def="$_env_fb"
      else
        p_def=""
      fi
    fi
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
    [[ "$_required" == true ]] && help_desc+=" (required)"
    [[ "$_is_array" == true ]] && help_desc+=" (multiple)"
    [[ -n "$_env_hint" ]] && help_desc+=" [env: ${_env_hint}]"
    local help_line=$(printf "%-20s %s" "$p_flag" "$help_desc")
    local _short="${p_flag%%|*}" _long="${p_flag#*|}"

    # --- Value extraction ---
    local _was_set=false
    if [[ "$p_ftype" == "boolean" ]]; then
      if [[ "$str" =~ ${s}($p_flag)([$s=])([^$s]*) ]]; then
        local val="${BASH_REMATCH[3]}"; val="${val#\"}"; val="${val%\"}"; val="${val#\'}"; val="${val%\'}"
        local _consume=false
        [[ "${BASH_REMATCH[2]}" == "=" ]] && _consume=true
        case "$val" in true|false) _consume=true ;; esac
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
        [[ "$_val" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || _die "invalid value '${_val}' for $p_flag (expected: number)"
      fi
    fi

    # --- Track missing required flags (checked before dispatch) ---
    if [[ "$_required" == true && "$_was_set" == false && -z "${!p_var}" ]]; then
      _missing_required+="${p_flag} "
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
        [[ "$t" =~ $_re_flag ]]
        p_flag="${BASH_REMATCH[1]}"; p_var="${BASH_REMATCH[2]}"; p_def="${BASH_REMATCH[3]//\\\"/\"}"; p_ftype="${BASH_REMATCH[5]}"; p_fdesc="${BASH_REMATCH[7]}" ;;
      '#@description '*)
        [[ -n "$p_flag" ]] && p_fdesc="${t#'#@description '}" || p_desc="${t#'#@description '}" ;;
      '#@version '*)
        version="${t#'#@version '}" ;;
      '#@'*|'#'*|'') ;;
      'function '*)
        _flush_flag
        if [[ "$t" =~ ^function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_-]*)[[:space:]]*\(\) && -n "$p_vis" ]]; then
          local fname="${BASH_REMATCH[1]}"
          if [[ "$p_vis" == public ]]; then
            [[ -n "$methods" ]] && methods+=$'\n'
            methods+="$(printf '%-20s %s' "$fname" "$p_desc")"
          fi
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

  # Warn about unknown flags (all known flags already removed from str)
  # Skip during tab completion (shortlist passes flag names as positional args)
  if [[ "$str" != *"${s}shortlist"* ]]; then
    local _uf_str="$str" _re_uf="${s}(--?[a-zA-Z][^${s}]*)"
    while [[ "$_uf_str" =~ $_re_uf ]]; do
      case "${BASH_REMATCH[1]}" in -h|--help|-V|--version) ;; *) printf "ignored unknown flag '%s'\n" "${BASH_REMATCH[1]}" >&2 ;; esac
      _uf_str="${_uf_str/${BASH_REMATCH[0]}/}"
    done
  fi

  # Check required flags (skip for help/shortlist/version)
  if [[ -n "$_missing_required" ]]; then
    case "$str" in
      *"${s}shortlist"*|*"${s}help"*|*"${s}--help"*|*"${s}-h"*|*"${s}--version"*|*"${s}-V"*|*"${s}version"*) ;;
      *) _die "missing required flag: ${_missing_required% }" ;;
    esac
  fi

  str="${str#${s}}"

  local _av; for _av in $_oo_array_vars; do
    local _raw="${!_av}"
    if [[ -n "$_raw" ]]; then
      IFS=$'\x1E' read -ra "$_av" <<< "$_raw"
    else
      read -ra "$_av" < /dev/null || true
    fi
  done

  local old_ifs="$IFS"; IFS="$s"; local all=($str); IFS="$old_ifs"
  _call "${all[@]}"
}
