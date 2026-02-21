#!/bin/bash
#
# oosh validate — static analysis for oosh CLI scripts
#
# Usage: oosh validate <target> [module] [--no-color]
#

set -euo pipefail

# --- colors & symbols (respect --no-color flag and NO_COLOR env) ---
_USE_COLOR=1
[[ -n "${NO_COLOR:-}" ]] && _USE_COLOR=0
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
OK="${GR}✔${RST}"  ERR="${RD}✘${RST}"  WRN="${YL}⚠${RST}"  DOT="${MG}◆${RST}"

_fail() { printf "\n  ${ERR}  ${RD}%s${RST}\n\n" "$*" >&2; exit 1; }
_resolve() { local s="$1"; while [ -L "$s" ]; do local d="$(cd "$(dirname "$s")" && pwd)"; s="$(readlink "$s")"; [[ "$s" != /* ]] && s="$d/$s"; done; echo "$s"; }

# --- arg parsing ---
TARGET=""  SCOPE_MOD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    *)
      if [[ -z "$TARGET" ]]; then TARGET="$1"
      elif [[ -z "$SCOPE_MOD" ]]; then SCOPE_MOD="$1"
      else _fail "unexpected argument: $1"
      fi
      shift ;;
  esac
done

[[ -z "$TARGET" ]] && { printf "\n  ${B}Usage:${RST} oosh validate ${CY}<target>${RST} ${DIM}[module] [--no-color]${RST}\n\n"; exit 1; }

# --- target resolution (same as trace.sh) ---
SCRIPT=""
if [[ "$TARGET" == */* || "$TARGET" == *.sh ]]; then
  [[ ! -f "$TARGET" ]] && _fail "file not found: $TARGET"
  SCRIPT="$(_resolve "$(cd "$(dirname "$TARGET")" && pwd)/$(basename "$TARGET")")"
else
  _bin="$(command -v "$TARGET" 2>/dev/null || true)"
  if [[ -n "$_bin" ]]; then
    SCRIPT="$(_resolve "$_bin")"
  elif [[ -f "${HOME}/.${TARGET}/${TARGET}.sh" ]]; then
    SCRIPT="${HOME}/.${TARGET}/${TARGET}.sh"
  else
    _fail "cannot find '$TARGET' — provide a path or install it"
  fi
fi

# --- constants ---

# Common environment variables that flag vars might shadow
_ENV_VARS=" PATH HOME USER SHELL TERM LANG LC_ALL EDITOR DISPLAY HOSTNAME PWD OLDPWD TMPDIR LOGNAME MAIL COLUMNS LINES PAGER VISUAL TZ CDPATH HISTFILE HISTSIZE "

# oosh internal globals
_OOSH_INTERNALS=" GLOBAL_SCRIPT GLOBAL_METHODS GLOBAL_FLAGS GLOBAL_PREFIX GLOBAL_VERSION OO_VERSION OO_COLOR MODULES_DIR "

# Valid flag types (base forms)
_VALID_BASE_TYPES=" boolean number file dir "

# --- regex patterns (match oo.sh main loop) ---
_RE_FLAG='^#@flag[[:space:]]+([^[:space:]]+)[[:space:]]+([A-Z_][A-Z0-9_]*)[[:space:]]+"([^"]*)"[[:space:]]*([^[:space:]~]*)[[:space:]]*(~[[:space:]]+(.*))?'
_RE_ENUM='^enum\([^)]+\)$'
_RE_ARRAY_TYPED='^array\(.+\)$'
_RE_ARRAY_PLAIN='^array$'
_RE_FUNC='^function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_-]*)[[:space:]]*\(\)'
_RE_FUNC_SHORT='^([a-zA-Z_][a-zA-Z0-9_-]*)[[:space:]]*\(\)[[:space:]]*\{?[[:space:]]*$'

# --- state ---
_ERRORS=0  _WARNINGS=0
_TOTAL_COMMANDS=0  _TOTAL_FLAGS=0
# Space-delimited tracking strings (bash 3.2 — no associative arrays)
# Format: "file:scope:flagname " for duplicate detection
_ALL_FLAG_NAMES=""
# Format: "file:varname " for cross-module collision detection
_ALL_VAR_NAMES=""

_report_error() {
  local file="$1" line_num="$2" msg="$3"
  printf "  ${ERR}  ${RD}error${RST} ${DIM}%s:%d${RST} — %s\n" "$(basename "$file")" "$line_num" "$msg"
  _ERRORS=$((_ERRORS + 1))
}

_report_warning() {
  local file="$1" line_num="$2" msg="$3"
  printf "  ${WRN}  ${YL}warn${RST}  ${DIM}%s:%d${RST} — %s\n" "$(basename "$file")" "$line_num" "$msg"
  _WARNINGS=$((_WARNINGS + 1))
}

_is_valid_type() {
  local t="$1"
  [[ -z "$t" ]] && return 0
  [[ "$_VALID_BASE_TYPES" == *" $t "* ]] && return 0
  [[ "$t" =~ $_RE_ENUM ]] && return 0
  [[ "$t" =~ $_RE_ARRAY_TYPED ]] && return 0
  [[ "$t" =~ $_RE_ARRAY_PLAIN ]] && return 0
  # array(enum(...)) — check inner
  if [[ "$t" =~ ^array\((.+)\)$ ]]; then
    local inner="${BASH_REMATCH[1]}"
    [[ "$_VALID_BASE_TYPES" == *" $inner "* ]] && return 0
    [[ "$inner" =~ $_RE_ENUM ]] && return 0
    return 1
  fi
  return 1
}

_validate_file() {
  local file="$1"
  local line_num=0
  local scope="__global__"
  local pending_vis="" pending_vis_line=0
  local prev_flag_line=0 prev_flag_var="" prev_flag_fdesc=""
  # Track flag names within this file: "scope:flagname "
  local file_flag_names=""

  while IFS= read -r line; do
    line_num=$((line_num + 1))
    local t="${line#"${line%%[![:space:]]*}"}"

    # Normalize function declarations (same as oo.sh)
    local is_func=false func_name=""
    if [[ ! "$t" == '#'* && "$t" =~ $_RE_FUNC_SHORT ]]; then
      func_name="${BASH_REMATCH[1]}"
      is_func=true
    elif [[ "$t" =~ $_RE_FUNC ]]; then
      func_name="${BASH_REMATCH[1]}"
      is_func=true
    fi

    case "$t" in
      '#@public'*|'#@protected'*)
        # Check for orphaned previous visibility annotation
        if [[ -n "$pending_vis" ]]; then
          _report_error "$file" "$pending_vis_line" "orphaned #@${pending_vis} — not followed by a function"
        fi
        # Handle deferred missing-description check from previous flag
        if [[ -n "$prev_flag_var" && -z "$prev_flag_fdesc" ]]; then
          # Check if THIS line is #@description (it's not — it's visibility)
          _report_warning "$file" "$prev_flag_line" "flag ${prev_flag_var} has no description"
        fi
        prev_flag_var="" prev_flag_fdesc="" prev_flag_line=0
        [[ "$t" == '#@public'* ]] && pending_vis="public" || pending_vis="protected"
        pending_vis_line=$line_num
        scope="__pending__"
        ;;
      '#@flag '*)
        # Handle deferred missing-description check from previous flag
        if [[ -n "$prev_flag_var" && -z "$prev_flag_fdesc" ]]; then
          _report_warning "$file" "$prev_flag_line" "flag ${prev_flag_var} has no description"
        fi
        if [[ "$t" =~ $_RE_FLAG ]]; then
          local flag_name="${BASH_REMATCH[1]}"
          local flag_var="${BASH_REMATCH[2]}"
          local flag_type="${BASH_REMATCH[4]}"
          local flag_desc="${BASH_REMATCH[6]}"
          _TOTAL_FLAGS=$((_TOTAL_FLAGS + 1))

          # Check type validity
          if [[ -n "$flag_type" ]] && ! _is_valid_type "$flag_type"; then
            _report_error "$file" "$line_num" "invalid type '${flag_type}' for ${flag_name}"
          fi

          # Check duplicate flag names in same scope
          local dup_key="${scope}:${flag_name}"
          if [[ "$file_flag_names" == *" ${dup_key} "* ]]; then
            _report_error "$file" "$line_num" "duplicate flag ${flag_name} in scope '${scope}'"
          fi
          file_flag_names="${file_flag_names} ${dup_key} "

          # Track for cross-file collision
          _ALL_FLAG_NAMES="${_ALL_FLAG_NAMES}$(basename "$file"):${scope}:${flag_name} "
          _ALL_VAR_NAMES="${_ALL_VAR_NAMES}$(basename "$file"):${flag_var} "

          # Check env var shadow
          if [[ "$_ENV_VARS" == *" ${flag_var} "* ]]; then
            _report_warning "$file" "$line_num" "${flag_var} shadows environment variable"
          fi

          # Check oosh internal shadow
          if [[ "$_OOSH_INTERNALS" == *" ${flag_var} "* ]]; then
            _report_warning "$file" "$line_num" "${flag_var} shadows oosh internal"
          fi

          # Defer description check (next line might be #@description)
          prev_flag_line=$line_num
          prev_flag_var="$flag_var"
          prev_flag_fdesc="$flag_desc"
        else
          _report_error "$file" "$line_num" "malformed #@flag — expected: #@flag -x|--name VAR \"default\" [type] [~ desc]"
          prev_flag_var="" prev_flag_fdesc="" prev_flag_line=0
        fi
        ;;
      '#@description '*)
        # Legacy description — suppress missing-description warning
        if [[ -n "$prev_flag_var" && -z "$prev_flag_fdesc" ]]; then
          prev_flag_fdesc="${t#'#@description '}"
        fi
        ;;
      '#@version '*|'#@module '*|'#@'*|'#'*|'')
        # Comments, blank lines, other annotations — skip
        ;;
      *)
        if [[ "$is_func" == true ]]; then
          if [[ -n "$pending_vis" ]]; then
            _TOTAL_COMMANDS=$((_TOTAL_COMMANDS + 1))
            pending_vis=""
            scope="$func_name"
          fi
          # Handle deferred missing-description check
          if [[ -n "$prev_flag_var" && -z "$prev_flag_fdesc" ]]; then
            _report_warning "$file" "$prev_flag_line" "flag ${prev_flag_var} has no description"
          fi
          prev_flag_var="" prev_flag_fdesc="" prev_flag_line=0
        else
          # Non-annotation, non-function line — check orphaned visibility
          if [[ -n "$pending_vis" ]]; then
            _report_error "$file" "$pending_vis_line" "orphaned #@${pending_vis} — not followed by a function"
            pending_vis=""
          fi
          # Handle deferred missing-description check
          if [[ -n "$prev_flag_var" && -z "$prev_flag_fdesc" ]]; then
            _report_warning "$file" "$prev_flag_line" "flag ${prev_flag_var} has no description"
          fi
          prev_flag_var="" prev_flag_fdesc="" prev_flag_line=0
          scope="__global__"
        fi
        ;;
    esac
  done < "$file"

  # End-of-file: check pending state
  if [[ -n "$pending_vis" ]]; then
    _report_error "$file" "$pending_vis_line" "orphaned #@${pending_vis} — not followed by a function"
  fi
  if [[ -n "$prev_flag_var" && -z "$prev_flag_fdesc" ]]; then
    _report_warning "$file" "$prev_flag_line" "flag ${prev_flag_var} has no description"
  fi
}

# --- banner ---
printf "\n${MG}"
printf '    ___    ___    ___   _\n'
printf '   / _ \\  / _ \\  / __| | |__\n'
printf '  | (_) || (_) | \\__ \\ | '"'"'_ \\\n'
printf '   \\___/  \\___/  |___/ |_| |_|\n'
printf "${RST}\n"

_CLI="$(basename "${SCRIPT//.sh/}")"
printf "  ${DOT}  ${B}oosh validate${RST} ${DIM}—${RST} ${B}%s${RST}\n" "$_CLI"

# --- module discovery ---
_SCRIPT_DIR="$(cd "$(dirname "$SCRIPT")" && pwd)"
_FILES=""
_FILE_COUNT=0

if [[ -d "${_SCRIPT_DIR}/modules" ]]; then
  if [[ -n "$SCOPE_MOD" ]]; then
    _mod_file="${_SCRIPT_DIR}/modules/${SCOPE_MOD}.sh"
    [[ ! -f "$_mod_file" ]] && _fail "module not found: ${SCOPE_MOD}"
    _FILES="$_mod_file"
    _FILE_COUNT=1
    printf "  ${DIM}scope: %s${RST}\n" "$SCOPE_MOD"
  else
    _FILES="$SCRIPT"
    _FILE_COUNT=1
    for _mf in "${_SCRIPT_DIR}/modules/"*.sh; do
      [[ -f "$_mf" ]] || continue
      _FILES="${_FILES}"$'\n'"$_mf"
      _FILE_COUNT=$((_FILE_COUNT + 1))
    done
  fi
else
  _FILES="$SCRIPT"
  _FILE_COUNT=1
fi

printf "\n"

# --- validate each file ---
while IFS= read -r _file; do
  [[ -z "$_file" ]] && continue
  printf "  ${CY}►${RST}  %s\n" "$(basename "$_file")"
  _validate_file "$_file"
done <<< "$_FILES"

# --- cross-module variable collision check ---
if [[ $_FILE_COUNT -gt 1 ]]; then
  # Build list of "var:file" pairs and check for same var in different files
  _seen_vars=""
  for _entry in $_ALL_VAR_NAMES; do
    local_file="${_entry%%:*}"
    local_var="${_entry#*:}"
    if [[ "$_seen_vars" == *"|${local_var}:"* ]]; then
      # Var seen before — check if from a different file
      _prev_file=""
      for _prev in $_ALL_VAR_NAMES; do
        _pf="${_prev%%:*}"
        _pv="${_prev#*:}"
        if [[ "$_pv" == "$local_var" && "$_pf" != "$local_file" ]]; then
          _prev_file="$_pf"
          break
        fi
      done
      if [[ -n "$_prev_file" ]]; then
        # Only report once per var — check if already warned
        if [[ "$_seen_vars" != *"|${local_var}:warned"* ]]; then
          printf "  ${WRN}  ${YL}warn${RST}  ${DIM}cross-module${RST} — %s used in %s and %s\n" "$local_var" "$_prev_file" "$local_file"
          _WARNINGS=$((_WARNINGS + 1))
          _seen_vars="${_seen_vars}|${local_var}:warned"
        fi
      fi
    fi
    _seen_vars="${_seen_vars}|${local_var}:${local_file}"
  done
fi

# --- variable collision check (same var, different scopes within file) ---
_checked_vars=""
for _entry in $_ALL_VAR_NAMES; do
  local_file="${_entry%%:*}"
  local_var="${_entry#*:}"
  # Count occurrences of this var in this file
  _var_count=0
  for _e2 in $_ALL_VAR_NAMES; do
    _e2f="${_e2%%:*}"
    _e2v="${_e2#*:}"
    [[ "$_e2f" == "$local_file" && "$_e2v" == "$local_var" ]] && _var_count=$((_var_count + 1))
  done
  if [[ $_var_count -gt 1 && "$_checked_vars" != *" ${local_file}:${local_var} "* ]]; then
    printf "  ${WRN}  ${YL}warn${RST}  ${DIM}%s${RST} — %s used by multiple flags\n" "$local_file" "$local_var"
    _WARNINGS=$((_WARNINGS + 1))
    _checked_vars="${_checked_vars} ${local_file}:${local_var} "
  fi
done

# --- summary ---
printf "\n  ${DIM}%d command(s), %d flag(s) across %d file(s)${RST}\n" "$_TOTAL_COMMANDS" "$_TOTAL_FLAGS" "$_FILE_COUNT"

if [[ $_ERRORS -gt 0 ]]; then
  _es=""; [[ $_ERRORS -gt 1 ]] && _es="s"
  _ws=""; [[ $_WARNINGS -gt 1 ]] && _ws="s"
  if [[ $_WARNINGS -gt 0 ]]; then
    printf "  ${RD}%d error%s${RST}, ${YL}%d warning%s${RST}\n\n" "$_ERRORS" "$_es" "$_WARNINGS" "$_ws"
  else
    printf "  ${RD}%d error%s${RST}\n\n" "$_ERRORS" "$_es"
  fi
  exit 1
elif [[ $_WARNINGS -gt 0 ]]; then
  _ws=""; [[ $_WARNINGS -gt 1 ]] && _ws="s"
  printf "  ${YL}%d warning%s${RST}\n\n" "$_WARNINGS" "$_ws"
else
  printf "  ${GR}0 errors, 0 warnings${RST}\n\n"
fi
