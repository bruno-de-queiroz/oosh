#!/bin/bash
#
# oosh trace — performance profiler for oosh CLIs
#
# Usage: oosh trace <target> [module] [command] [-t threshold] [-r runs] [--no-color]
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
OK="${GR}✔${RST}"  ERR="${RD}✘${RST}"  DOT="${MG}◆${RST}"

_fail() { printf "\n  ${ERR}  ${RD}%s${RST}\n\n" "$*" >&2; exit 1; }
_resolve() { local s="$1"; while [ -L "$s" ]; do local d="$(cd "$(dirname "$s")" && pwd)"; s="$(readlink "$s")"; [[ "$s" != /* ]] && s="$d/$s"; done; echo "$s"; }

# --- arg parsing ---
TARGET=""  SCOPE_MOD=""  SCOPE_CMD=""  THRESHOLD=100  RUNS=5  MAX_ITEMS=20

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t) THRESHOLD="${2:-}"; [[ -z "$THRESHOLD" ]] && _fail "-t requires a value"; shift 2 ;;
    -r) RUNS="${2:-}"; [[ -z "$RUNS" ]] && _fail "-r requires a value"; shift 2 ;;
    *)
      if [[ -z "$TARGET" ]]; then TARGET="$1"
      elif [[ -z "$SCOPE_MOD" ]]; then SCOPE_MOD="$1"
      elif [[ -z "$SCOPE_CMD" ]]; then SCOPE_CMD="$1"
      else _fail "unexpected argument: $1"
      fi
      shift ;;
  esac
done

[[ -z "$TARGET" ]] && { printf "\n  ${B}Usage:${RST} oosh trace ${CY}<target>${RST} ${DIM}[module] [command] [-t threshold] [-r runs] [--no-color]${RST}\n\n"; exit 1; }

# --- target resolution ---
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

# If script lives inside modules/, set MODULES_DIR so oo.sh can be sourced
_SCRIPT_DIR="$(cd "$(dirname "$SCRIPT")" && pwd)"
_MOD_ENV=""
if [[ "$(basename "$_SCRIPT_DIR")" == "modules" ]]; then
  _MOD_ENV="MODULES_DIR=$_SCRIPT_DIR"
fi

# --- timing ---
_ms() { perl -MTime::HiRes=time -e 'printf "%.0f\n", time * 1000' 2>/dev/null \
     || python3 -c 'import time; print(int(time.time()*1000))'; }

_WARNINGS=0  _SLOWEST=""  _SLOWEST_MS=0

_run() {
  if [[ -n "$_MOD_ENV" ]]; then
    env "$_MOD_ENV" bash "$SCRIPT" "$@"
  else
    bash "$SCRIPT" "$@"
  fi
}

_trace() {
  local label="$1"; shift
  local total=0 i t0 t1
  for (( i=0; i<RUNS; i++ )); do
    t0=$(_ms)
    _run "$@" >/dev/null 2>&1
    t1=$(_ms)
    total=$((total + t1 - t0))
  done
  local elapsed=$((total / RUNS))
  local color="$GR" icon="$OK"
  if [[ "$elapsed" -gt "$THRESHOLD" ]]; then
    color="$RD"; icon="$ERR"; _WARNINGS=$((_WARNINGS + 1))
  elif [[ "$elapsed" -gt 50 ]]; then
    color="$YL"; icon="${YL}✔${RST}"
  fi
  [[ "$elapsed" -gt "$_SLOWEST_MS" ]] && { _SLOWEST_MS="$elapsed"; _SLOWEST="$label"; }
  printf "  %s  %-45s ${color}%dms${RST}\n" "$icon" "$label" "$elapsed"
}

# --- banner ---
printf "\n${MG}"
printf '    ___    ___    ___   _\n'
printf '   / _ \\  / _ \\  / __| | |__\n'
printf '  | (_) || (_) | \\__ \\ | '"'"'_ \\\n'
printf '   \\___/  \\___/  |___/ |_| |_|\n'
printf "${RST}\n"

_CLI="$(basename "${SCRIPT//.sh/}")"
printf "  ${DOT}  ${B}oosh trace${RST} ${DIM}—${RST} ${B}%s${RST} ${DIM}(%d runs, threshold: %dms)${RST}\n" "$_CLI" "$RUNS" "$THRESHOLD"

# --- build scope ---
_SCOPE_LABEL=""
[[ -n "$SCOPE_MOD" ]] && _SCOPE_LABEL=" $SCOPE_MOD"
[[ -n "$SCOPE_CMD" ]] && _SCOPE_LABEL="$_SCOPE_LABEL $SCOPE_CMD"

# --- helpers ---
_get_words() { _run shortlist "$@" 2>/dev/null | tr ' ' '\n' | grep -v '^$' || true; }

_trace_flags() {
  local items="$1"; shift
  local label_prefix="shortlist"
  local arg; for arg in "$@"; do label_prefix="$label_prefix $arg"; done
  local longs="" shorts=""
  while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    case "$item" in --*) longs="${longs}${item}"$'\n' ;; -*) shorts="${shorts}${item}"$'\n' ;; esac
  done <<< "$items"
  local to_trace="${longs:-$shorts}"
  [[ -z "$to_trace" ]] && return 0
  local count=0 output _w _is_completion
  while IFS= read -r flag; do
    [[ -z "$flag" ]] && continue
    [[ $count -ge $MAX_ITEMS ]] && break
    output=$(_run shortlist "$@" "$flag" 2>/dev/null || true)
    if [[ -n "$output" && "$output" != "__file__" && "$output" != "__dir__" ]]; then
      # Skip if output is only flags (boolean consumed, parent listing echoed)
      _is_completion=false
      for _w in $output; do
        case "$_w" in -*) ;; *) _is_completion=true; break ;; esac
      done
      if [[ "$_is_completion" == true ]]; then
        _trace "$label_prefix $flag" shortlist "$@" "$flag"
      fi
    fi
    count=$((count + 1))
  done <<< "$to_trace"
}

# --- crawl: Shortlist ---
printf "\n  ${B}Shortlist${RST}\n\n"

# Get items at scope level
_top_items=$(_get_words ${_SCOPE_LABEL})

# Trace the scope-level shortlist
# shellcheck disable=SC2086
_trace "shortlist${_SCOPE_LABEL}" shortlist ${_SCOPE_LABEL}

if [[ -n "$SCOPE_CMD" ]]; then
  # Scoped to command — only trace flag completions
  # shellcheck disable=SC2086
  _trace_flags "$_top_items" ${_SCOPE_LABEL}
else
  # Separate into commands and flags
  _top_cmds=""
  while IFS= read -r _item; do
    [[ -z "$_item" || "$_item" == "help" || "$_item" == "shortlist" ]] && continue
    case "$_item" in -*) ;; *) _top_cmds="${_top_cmds}${_item}"$'\n' ;; esac
  done <<< "$_top_items"

  _cmd_count=0 _total_cmds=0
  while IFS= read -r _c; do [[ -n "$_c" ]] && _total_cmds=$((_total_cmds + 1)); done <<< "$_top_cmds"

  while IFS= read -r _cmd; do
    [[ -z "$_cmd" ]] && continue
    if [[ $_cmd_count -ge $MAX_ITEMS ]]; then
      _remaining=$((_total_cmds - MAX_ITEMS))
      [[ $_remaining -gt 0 ]] && printf "  ${DIM}     (... and %d more)${RST}\n" "$_remaining"
      break
    fi

    # Get sub-items before tracing
    # shellcheck disable=SC2086
    _sub_items=$(_get_words ${_SCOPE_LABEL} "$_cmd")

    # Trace: shortlist [scope] <cmd>
    # shellcheck disable=SC2086
    _trace "shortlist${_SCOPE_LABEL} $_cmd" shortlist ${_SCOPE_LABEL} "$_cmd"

    # Trace flag completions
    # shellcheck disable=SC2086
    _trace_flags "$_sub_items" ${_SCOPE_LABEL} "$_cmd"

    # Separate sub-items into sub-commands (multi-module case)
    _sub_cmds=""
    while IFS= read -r _si; do
      [[ -z "$_si" || "$_si" == "help" || "$_si" == "shortlist" ]] && continue
      case "$_si" in -*) ;; *) _sub_cmds="${_sub_cmds}${_si}"$'\n' ;; esac
    done <<< "$_sub_items"

    _sub_count=0
    while IFS= read -r _subcmd; do
      [[ -z "$_subcmd" ]] && continue
      [[ $_sub_count -ge $MAX_ITEMS ]] && break
      # shellcheck disable=SC2086
      _subsub_items=$(_get_words ${_SCOPE_LABEL} "$_cmd" "$_subcmd")
      # shellcheck disable=SC2086
      _trace "shortlist${_SCOPE_LABEL} $_cmd $_subcmd" shortlist ${_SCOPE_LABEL} "$_cmd" "$_subcmd"
      # shellcheck disable=SC2086
      _trace_flags "$_subsub_items" ${_SCOPE_LABEL} "$_cmd" "$_subcmd"
      _sub_count=$((_sub_count + 1))
    done <<< "$_sub_cmds"

    _cmd_count=$((_cmd_count + 1))
  done <<< "$_top_cmds"
fi

# --- crawl: Help ---
printf "\n  ${B}Help${RST}\n\n"

if [[ -n "$_SCOPE_LABEL" ]]; then
  # shellcheck disable=SC2086
  _trace "${_SCOPE_LABEL# } help" ${_SCOPE_LABEL} help
else
  _trace "help" help
fi

# --- summary ---
printf "\n"
if [[ $_WARNINGS -eq 0 ]]; then
  printf "  ${GR}0 warnings${RST}\n\n"
else
  _s=""; [[ $_WARNINGS -gt 1 ]] && _s="s"
  printf "  ${RD}%d warning%s${RST} — slowest: ${B}%s${RST} (%dms)\n\n" \
    "$_WARNINGS" "$_s" "$_SLOWEST" "$_SLOWEST_MS"
  exit 1
fi
