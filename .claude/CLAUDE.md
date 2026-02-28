# oosh — Developer Guide

An annotation-driven bash CLI framework. Drop annotated `.sh` modules into a directory, call `main $0 "$@"` at the bottom, and get help text, flag parsing, and tab-completion for free. Supports bash 3.2+ (macOS & Linux).

## Repository layout

```
oo.sh              # Framework engine — the only runtime file users deploy
generate.sh        # Scaffolds a new CLI (entry point, completion, sample modules)
lint.sh            # Static annotation checker (errors + warnings)
trace.sh           # Completion-path profiler (flags slow dynamic enums)
install.sh         # Installs oosh itself into PATH
tests/
  run.sh           # Runs all suites: oo, generate, trace, lint
  helpers.sh       # Shared assert helpers (_assert, _assert_perf, _assert_exit, …)
  oo.sh            # Core engine tests (flags, dispatch, completion, perf)
  generate.sh      # Generator tests
  lint.sh          # Lint tests
  trace.sh         # Trace tests
```

## oo.sh — the engine

### Architecture philosophy: performance first

**`oo.sh` is optimized for minimal passes and zero subprocess forks, not human readability.**

Every design decision in the engine trades clarity for speed:

- The entire file is read **once** in a single `while IFS= read -r line` pass. Annotation parsing, flag extraction, and method discovery all happen in that one loop.
- All string operations use **pure bash builtins** (`${var%%pattern}`, `${var//old/new}`, `[[ =~ ]]`). No `sed`, `awk`, `cut`, `grep`, or external tools in the hot path.
- Internal delimiters are `\x1F` (unit separator) and `\x1E` (record separator) — chosen because they never appear in normal shell arguments, avoiding the need for escaping or quoting when passing the entire arg list as a single string.
- Regex patterns that are used repeatedly are stored in local variables (`_re_flag`, `_re_enum_dyn`, etc.) to avoid re-compiling them on every use — bash 3.2 does not cache regex literals.
- The `_flush_flag()` helper is defined as a nested function inside `main()` and unset after the parse loop (`unset -f _flush_flag`) to keep it out of the module's function namespace.
- Dynamic enum resolvers are **lazy** — they are never called during `help`, `shortlist` (without the flag), or dispatch when the flag is absent. Only called when the flag is actually provided or when tab-completing that specific flag.
- Unknown-flag warnings skip scanning when the first positional argument is not a locally-known command (i.e., it might be dispatched to a child module that handles its own flags).

When reading or modifying `oo.sh`, expect dense one-liners and pattern-matching chains. Do not refactor for readability — the current shape is deliberate.

### Global state

`main()` resets these on every call, so each subprocess/module invocation is isolated:

| Variable | Purpose |
|---|---|
| `GLOBAL_SCRIPT` | Path to the script being parsed |
| `GLOBAL_METHODS` | Newline-separated `name   description` lines for public methods |
| `GLOBAL_FLAGS` | Newline-separated flag help lines (global and `cmd:` prefixed scoped ones) |
| `GLOBAL_VERSION` | Version string from `#@version` |
| `_SL_FILE_FLAGS` | Space-separated list of flag names that trigger file completion |
| `_SL_DIR_FLAGS` | Space-separated list of flag names that trigger dir completion |
| `_SL_ENUM` | Space-separated `flag=values` pairs for enum completion |

### Override stubs

Modules override these to customise behaviour:

```
_shortlist()    → _default_shortlist()
_help()         → _default_help()
_command_help() → _default_command_help()
_call()         → _default_call()
_version()      → _default_version()
```

### Exit codes

- `0` — success
- `1` — runtime error (missing dependency, etc.)
- `2` — usage error (unknown command, invalid flag value, missing required flag)

## Annotation syntax

```bash
#@module Description          # top of file — module name + description
#@version x.y.z               # top of file — version string
#@public [~ description]      # before a function — expose in help + shortlist
#@protected [~ description]   # before a function — callable but hidden from help
#@flag -s|--long VAR "default" [type] [~ description]
#@description text            # legacy: alternative to inline ~ on #@flag or #@public
```

Flag types: `file`, `dir`, `boolean`, `number`, `enum(a,b,c)`, `enum(${func})`, `array`, `array(enum(...))`, `required`, `required:type`.

Variable names must be `UPPER_SNAKE_CASE` and conventionally prefixed with the module name (e.g. `DEPLOY_` in `deploy.sh`). The linter warns when this convention is violated.

Flags declared **after** `#@public`/`#@protected` but before `function` are scoped to that method — shown indented under the command in help output and only offered in tab-completion when that command is selected.

Every module **must** end with:

```bash
main $0 "$@"
```

## Testing requirements

### Run the full suite

```bash
bash tests/run.sh
```

This runs four suites in order: `oo`, `generate`, `trace`, `lint`.

### Test matrix — mandatory

All changes must pass on **all three** of:

| Environment | Shell | Notes |
|---|---|---|
| macOS (bash 3.2) | bash | Default macOS shell — oldest supported bash |
| Ubuntu (bash 5.x) | bash | CI runs `ubuntu-latest` via GitHub Actions |
| Any platform | **zsh** | Completion scripts are installed into zsh via `bashcompinit` |

CI is defined in `.github/workflows/test.yml` and runs on `ubuntu-latest` and `macos-latest`. **Local zsh testing is not automated** — run completion and invocation tests manually in a zsh terminal before submitting changes that touch `oo.sh`, `generate.sh`, or `*.comp.sh` logic.

### Test helpers (`tests/helpers.sh`)

| Helper | Purpose |
|---|---|
| `_assert name expected actual` | Exact string equality |
| `_assert_contains name needle haystack` | Substring check |
| `_assert_not_contains name needle haystack` | Negative substring check |
| `_assert_exit name code cmd...` | Exit code assertion |
| `_assert_perf name max_ms cmd...` | Timing assertion — **all operations must complete within 150ms** |

Performance assertions use `perl` (preferred) or `python3` for millisecond timestamps. Both are available on macOS and Ubuntu.

### Performance budget

The 150ms ceiling covers the **entire process** including bash startup (~14–16ms macOS, ~2ms Linux). If a new code path risks blowing this budget, profile it with `oosh trace` and check both platforms.

## Key conventions

- **No external tools in hot paths.** Use bash builtins. Any call to `sed`, `awk`, `grep`, etc. inside `main()` or `_default_*` functions is a regression.
- **Bash 3.2 compat.** No `declare -A` (associative arrays), no `mapfile`/`readarray`, no `printf '%q'`, no `[[ -v var ]]`. Use indexed arrays carefully — they work but syntax differs slightly. Test on macOS.
- **zsh compat.** The framework sources into zsh via `bashcompinit`. Completion scripts call `<name> shortlist ...` as a subprocess, so the engine runs under bash regardless. But `generate.sh` and install logic write to `~/.zshrc` and must handle both shells.
- **Module variable isolation.** Each module runs as a separate bash subprocess. Global variables set in one module are not visible in another — by design.
- **The `--` separator.** Everything after `--` is stripped from the flag-parsing string and rejoined before dispatch. The `--` token itself is consumed and not passed to the function.
