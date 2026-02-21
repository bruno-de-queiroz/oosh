<p align="center">
  <img src="oosh.png" alt="oosh" width="300" />
</p>

An annotation-driven bash CLI framework with a built-in generator. ✨

Sprinkle some annotations on your functions and get help text, autocompletion, and flag parsing **for free**. Supports bash 3.2+ (macOS & Linux) -- no exotic dependencies, just good ol' bash. 🐚

## 🚀 Quick start

```bash
# Install oosh
curl -fsSL https://raw.githubusercontent.com/bruno-de-queiroz/oosh/main/install.sh | bash

# Spin up a brand-new CLI called "mytool"
oosh mytool

# The generator offers to install right away -- or do it later:
mytool install
```

Drop more `.sh` files into `modules/` and they're auto-discovered. That's it. Go build something cool. 🔧

### 🎬 What the generator looks like

```
    ___    ___    ___   _
   / _ \  / _ \  / __| | |__
  | (_) || (_) | \__ \ | '_ \
   \___/  \___/  |___/ |_| |_|

  mytool -> ~/.mytool

  oo.sh                  framework engine
  mytool.sh              entry point
  mytool.comp.sh         bash completion
  modules/hello.sh       sample module
  modules/install.sh     CLI installer
  modules/uninstall.sh   CLI uninstaller

  Enable colored output? (Y/n) y
  Install mytool to PATH? (Y/n) y
  Installed

  Done! Get started:

    mytool help
    mytool hello greet
    mytool hello greet --name World
```

### 📖 Help output

Your CLI comes with auto-generated help -- zero effort required:

```
  Usage: mytool [ hello install uninstall help ]

  Commands:
  help                 show options and flags available

  Modules:
  hello                Hello - sample module demonstrating oosh annotations
  install              Install - install and configure the mytool CLI
  uninstall            Uninstall - remove mytool from the system
```

And each module gets its own help too:

```
  Usage: hello [ greet farewell help ] [ -n ]

  Flags:
  -n|--name            who to greet

  Commands:
  greet                say hello
  farewell             say goodbye
  help                 show options and flags available
```

Method-scoped flags appear indented under their command:

```
  Usage: mytool [ deploy status help ] [ -v ]

  Flags:
  -v|--verbose         enable verbose output

  Commands:
  deploy               deploy the app
    -e|--env           target environment
    -f|--file          config file path
  status               check status
  help                 show options and flags available
```

## 🏷️ Annotations reference

| Annotation | Where | What it does |
|---|---|---|
| `#@module Description` | Top of module file | Module description shown in help |
| `#@public [~ description]` | Before a function | Expose as a user-facing command |
| `#@protected [~ description]` | Before a function | Hide from help/shortlist -- still callable internally |
| `#@flag -s\|--long VAR "default" [type] [~ description]` | Before a function or top-level | Declare a flag with short/long form, env var, default, and optional type |
| `#@description text` | After `#@flag` or `#@public`/`#@protected` | Legacy alternative to inline `~` descriptions |
| `#@version x.y.z` | Top of module file | Module version shown with `--version` |

Descriptions can be written inline using `~` on the same line, or on a separate `#@description` line (backward compatible). Flags declared after `#@public`/`#@protected` are scoped to that method and shown indented under it in help output.

Built-in commands: `help` / `--help` / `-h` show help, `version` / `--version` / `-V` show version info.

## 🚩 Flag syntax

```bash
#@flag -e|--env DEPLOY_ENV "default" ~ target environment

#@flag -f|--file DEPLOY_FILEPATH "" file ~ path to config file (triggers file completion)

#@flag -d|--dir DEPLOY_DIRPATH "" dir ~ output directory (triggers dir completion)

#@flag -v|--verbose DEPLOY_VERBOSE "false" boolean ~ toggle flag (doesn't consume the next arg)

#@flag -p|--port DEPLOY_PORT "8080" number ~ validated as numeric

#@flag -e|--env DEPLOY_ENVIRONMENT "production" enum(dev,staging,prod) ~ validated against allowed values

#@flag -b|--branch DEPLOY_BRANCH "" enum(${_get_branches}) ~ dynamic enum resolved by calling a function

#@flag -k|--key DEPLOY_API_KEY "" required ~ must be provided (errors before dispatch if missing)

#@flag -p|--port DEPLOY_PORT "" required:number ~ required + type validation combined

#@flag -t|--token DEPLOY_TOKEN "${DEPLOY_TOKEN}" ~ uses env var as fallback, shown in help as [env: DEPLOY_TOKEN]

#@flag -l|--lang DEPLOY_LANG "${DEPLOY_LANG:-en}" ~ env var with inline fallback (uses "en" if env var is unset)

#@flag -s|--secret DEPLOY_SECRET "${DEPLOY_SECRET}" required ~ required with env var fallback (satisfied if either is provided)
```

| Type | Completion | Validation |
|---|---|---|
| *(none)* | -- | -- |
| `file` | file completion | -- |
| `dir` | directory completion | -- |
| `boolean` | -- | toggle: `--flag` sets `true`, only consumes `true`/`false` as next arg |
| `number` | -- | must be numeric (integers or decimals) |
| `enum(a,b,c)` | completes with listed values | must match one of the listed values |
| `enum(${func})` | calls `func` at completion time | calls `func` at parse time for validation |
| `required` | -- | errors before dispatch if not provided and value is empty |
| `required:type` | inherits from type | required + type validation (e.g. `required:number`, `required:enum(a,b)`) |

- Short and long forms separated by `|`
- Variable name must be `UPPER_SNAKE_CASE`, prefixed with the module name (e.g. `deploy.sh` → `DEPLOY_`)
- Default value in double quotes (empty string = no default). Escaped quotes supported: `"say \"hello\""`
- Optional description after `~` separator (or use `#@description` on the next line)
- Function declarations work with or without the `function` keyword (`deploy() {` and `function deploy()` are both discovered)
- Unknown flags are reported on stderr (e.g. `ignored unknown flag '--vrebose'`) and execution continues
- Unknown commands show an error with help text and exit 2 (e.g. `unknown command 'foo'`)

Flags are parsed from `$@` and set as shell variables. If a flag isn't provided and the variable is unset, the default kicks in.

**Required flags**: Add `required` as the type (or prefix with `required:` for compound types like `required:number`). If the flag isn't provided and the value is empty after defaults, the CLI errors before dispatch. Help/shortlist/version commands always work without required flags. Help output shows `(required)` next to the flag.

**Env var fallback**: Use `"${VAR_NAME}"` as the default value to read from an environment variable. If the env var is set, its value becomes the default; if not, the default is empty. Use `"${VAR_NAME:-fallback}"` to provide an inline fallback when the env var is unset. Help output shows `[env: VAR_NAME]` so users know the fallback exists.

```bash
#@flag -k|--key API_KEY "${API_KEY}" required ~ must provide via flag or env
#@flag -l|--lang LANG "${LANG:-en}" ~ reads $LANG, falls back to "en"
```

Help output: `-k|--key             must provide via flag or env (required) [env: API_KEY]`

Priority: explicit flag > env var > inline fallback > empty

**Method-scoped flags**: Flags declared after `#@public`/`#@protected` (but before the `function` line) belong to that method. They're shown indented under the command in help output and only appear in tab-completion when that command is selected.

## 🧱 Module structure

```bash
#!/bin/bash
#@module MyModule - does useful things

#import oo.sh
. ${MODULES_DIR}/../oo.sh

#@flag -v|--verbose MYMODULE_VERBOSE "false" boolean ~ enable verbose output

#@public ~ deploy the app
#@flag -e|--env MYMODULE_ENVIRONMENT "production" enum(dev,staging,prod) ~ target environment
function deploy() {
  echo "Deploying to ${MYMODULE_ENVIRONMENT}..."
}

#@protected ~ internal helper
function _validate() {
  # hidden from help and shortlist -- your little secret 🤫
  echo "validating..."
}

# Bootstraps the parser
main $0 "$@"
```

In the example above, `-v|--verbose` is a **module-level flag** (available to all commands), while `-e|--env` is **scoped to deploy** (shown only under the deploy command in help).

Every module **must** end with `main $0 "$@"` to bootstrap the annotation parser. Don't forget this or nothing works! ⚠️

## 🎛️ Customizing

The entry point (`<name>.sh`) overrides three functions to route commands to modules:

- **`_shortlist`** -- returns completable words for the current context
- **`_help`** -- prints help text
- **`_call`** -- dispatches the command

These delegate to `_default_shortlist`, `_default_help`, and `_default_call` for non-module commands. Override them further to add global commands or custom routing.

## ⌨️ Autocompletion

Tab-completion works out of the box! The completion script (`<name>.comp.sh`) calls `<name> shortlist <words...>` to figure out what to suggest at the current cursor position.

Special markers:
- `__file__` -- triggers file completion
- `__dir__` -- triggers directory completion

These are returned automatically when a flag is declared with the `file` or `dir` type. Enum flags return their allowed values directly (static values or the output of a dynamic function). No extra wiring needed. 🪄

### 📦 Installation

The generator prompts to install after scaffolding. You can also run it manually:

```bash
<name> install
```

This will:
- Find a writable bin dir (`/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`)
- Find a bash completion dir (`/opt/homebrew/etc/bash_completion.d`, `/usr/local/etc/bash_completion.d`, `/etc/bash_completion.d`, `/usr/share/bash-completion/completions`) -- falls back to `~/.bash_completion.d/` with profile sourcing
- Symlink `<name>.sh` and `<name>.comp.sh` into those directories
- Add `<NAME>_DIR`, `<NAME>_PATH` exports and completion sourcing to `~/.bashrc` and `~/.zshrc`

And when you're done? `<name> uninstall` cleans everything up. No leftovers. 🧹

### 🔄 Updating

To update the oosh framework in an existing CLI, just run the generator again with the same name:

```bash
oosh mytool
```

If the directory already exists and contains `oo.sh`, the generator will offer to update it in place -- your modules and configuration are left untouched.

### 🔍 Trace

Profile tab-completion paths to find slow resolvers (e.g. dynamic enums calling `kubectl`):

```bash
oosh trace mytool                    # trace everything
oosh trace mytool kube               # trace only the kube module
oosh trace mytool kube use           # trace only "use" command in kube
oosh trace ./modules/kube.sh         # trace a specific module file
oosh trace mytool -t 50              # custom threshold (default 150ms)
oosh trace mytool -r 10              # custom runs (default 5)
```

Sample output:

```
    ___    ___    ___   _
   / _ \  / _ \  / __| | |__
  | (_) || (_) | \__ \ | '_ \
   \___/  \___/  |___/ |_| |_|

  oosh trace — mytool (5 runs, threshold: 150ms)

  Shortlist
  ✔  shortlist                                  15ms
  ✔  shortlist hello                            14ms
  ✔  shortlist hello greet                      18ms
  ✔  shortlist hello greet --name               12ms
  ✘  shortlist kube deploy --namespace        5204ms

  Help
  ✔  help                                       45ms

  1 warning — slowest: shortlist kube deploy --namespace (5204ms)
```

Colors: green <100ms, yellow 100–150ms, red >150ms. Exit code: 0 if no warnings, 1 if any — CI-friendly.

### 🔎 Lint

Catch annotation mistakes before they bite you at runtime:

```bash
oosh lint mytool                     # lint all files
oosh lint mytool hello               # lint only the hello module
oosh lint ./modules/deploy.sh        # lint a specific file
oosh lint mytool --fix               # auto-fix: add prefixes + placeholder descriptions
oosh lint mytool --no-color          # no ANSI codes (CI-friendly)
```

Sample output:

```
    ___    ___    ___   _
   / _ \  / _ \  / __| | |__
  | (_) || (_) | \__ \ | '_ \
   \___/  \___/  |___/ |_| |_|

  oosh lint — mytool

  ►  mytool.sh
  ►  hello.sh
  ►  deploy.sh
  ✘  error deploy.sh:5 — malformed #@flag — expected: #@flag -x|--name VAR "default" [type] [~ desc]
  ✘  error deploy.sh:8 — invalid type 'string' for -t|--target
  ⚠  warn  deploy.sh:12 — PATH shadows environment variable
  ⚠  warn  deploy.sh:15 — flag TIMEOUT has no description

  3 command(s), 8 flag(s) across 3 file(s)
  2 errors, 2 warnings
```

**Errors** (exit 1): malformed `#@flag`, invalid type, orphaned `#@public`/`#@protected`, duplicate flag names in the same scope.

**Warnings** (exit 0): missing module prefix (variable should start with `HELLO_` in `hello.sh`), variable name collisions across scopes, env var shadows (`PATH`, `HOME`, etc.), oosh internal shadows (`MODULES_DIR`, etc.), missing descriptions, cross-module variable collisions.

**`--fix`** auto-fixes what it can: renames unprefixed variables to use the module prefix (both in annotations and `$VAR` / `${VAR}` usages) and appends `~ TODO` descriptions to flags missing them. Run `oosh lint` again after fixing to verify.

## 🎨 Colors

Output is colored by default because life's too short for monochrome terminals. Three ways to tame it:

- **`OO_COLOR=0`** -- edit `oo.sh` to permanently disable (the generator asks during setup)
- **`NO_COLOR=1`** -- environment variable ([no-color.org](https://no-color.org)) to disable per-session
- **`--no-color`** -- pass to `generate.sh` to run the generator itself without colors

## ⚙️ Generator

```bash
./generate.sh <name> [output-dir]
./generate.sh --no-color <name> [output-dir]
```

- `<name>` -- CLI tool name (e.g., `sc`, `devops`, `mytool`)
- `[output-dir]` -- parent directory (defaults to `~/.<name>`), creates `<output-dir>/<name>/`
- `--no-color` -- disable colored generator output

Generated structure:

```
<name>/
├── <name>.sh        # Entry point
├── <name>.comp.sh   # Bash completion
├── oo.sh            # Framework engine
└── modules/
    ├── hello.sh       # Sample module
    ├── install.sh     # CLI installer (symlinks + profile setup)
    └── uninstall.sh   # CLI uninstaller (self-deletes)
```

## 🤖 Agent-friendly

oosh is designed to be easy for AI agents to work with. To add functionality to an oosh-generated CLI, an agent just needs to drop a `.sh` file into `modules/` following this template:

```bash
#!/bin/bash
#@module Name - short description

. ${MODULES_DIR}/../oo.sh

#@flag -x|--example NAME_VAR "default" ~ what this flag does
# types: file, dir, boolean, number, enum(a,b,c), enum(${func})

#@public ~ what this command does
function mycommand() {
  echo "doing things with ${NAME_VAR}"
}

main $0 "$@"
```

That's it -- no config files, no registration, no build step. The module is auto-discovered and immediately available with help text, flag parsing, and tab completion. Agents can scaffold entire CLIs by generating one module per concern. 🧩

## 📋 Known limitations

- **Two-level command nesting** — oosh supports `cli module command` (entry point dispatches to a module, module dispatches to a function). Arbitrary depth (`cli foo bar baz`) is not supported. Each module is a self-contained script with its own `main` call.
- **Control characters in values** — flag values are internally delimited with `\x1F` (unit separator) and arrays use `\x1E` (record separator). Values containing these characters will be split incorrectly. This is a non-issue in practice but worth knowing if you're piping binary data through flags.
- **Global variables** — the framework uses `GLOBAL_SCRIPT`, `GLOBAL_METHODS`, `GLOBAL_FLAGS`, `GLOBAL_PREFIX`, `GLOBAL_VERSION`, and `_SL_*` variables at the top level. These are reset on each `main()` call and isolated per-process in the module system, but avoid naming your own variables with these names.

## 💡 Cheatsheet

Patterns for things oosh doesn't handle natively.

### Mutually exclusive flags

Validate in your function body — oosh parses both, you enforce the constraint:

```bash
#@public ~ deploy the app
#@flag -s|--staging DEPLOY_STAGING "false" boolean ~ deploy to staging
#@flag -p|--production DEPLOY_PRODUCTION "false" boolean ~ deploy to production
function deploy() {
  if [[ "$DEPLOY_STAGING" == true && "$DEPLOY_PRODUCTION" == true ]]; then
    _error "--staging and --production are mutually exclusive"; exit 2
  fi
}
```

Alternatively, use an enum to make it a single choice:

```bash
#@flag -t|--target DEPLOY_TARGET "staging" enum(staging,production) ~ deployment target
```

### Dynamic enum from a slow source

Wrap the call in a function that caches to a temp file:

```bash
_get_namespaces() {
  local cache="/tmp/_ns_cache_$$"
  if [[ ! -f "$cache" ]]; then
    kubectl get ns -o name | sed 's|namespace/||' > "$cache"
  fi
  cat "$cache"
}
#@flag -n|--namespace DEPLOY_NS "" enum(${_get_namespaces}) ~ k8s namespace
```

oosh resolves dynamic enums lazily (only when the flag is actually used), so help and shortlist won't trigger the slow call. But tab-completing the flag will — the cache helps there.

### Multiline or computed enum values

Dynamic enums can return any list — build it however you want:

```bash
_get_regions() {
  # hardcoded but maintainable in one place
  printf "us-east-1\nus-west-2\neu-west-1\nap-southeast-1\n"
}

_get_envs() {
  # computed from directory contents
  ls environments/ | sed 's/\.yaml$//'
}
#@flag -r|--region DEPLOY_REGION "" enum(${_get_regions}) ~ AWS region
#@flag -e|--env DEPLOY_ENV "" enum(${_get_envs}) ~ environment config
```

### Dependent flags (flag B only makes sense with flag A)

Validate the dependency in your function:

```bash
#@flag -f|--format REPORT_FORMAT "text" enum(text,json,csv) ~ output format
#@flag -o|--output REPORT_OUTPUT "" file ~ write to file (requires --format json or csv)
function report() {
  if [[ -n "$REPORT_OUTPUT" && "$REPORT_FORMAT" == "text" ]]; then
    _error "--output requires --format json or csv"; exit 2
  fi
}
```

### Flag value with spaces

Users can quote values or use `=` syntax:

```bash
mytool --name "John Doe"
mytool --name="John Doe"
```

### Default that references another variable

Compute it in the function body — annotation defaults are static strings or env var lookups:

```bash
#@flag -o|--output DEPLOY_OUTPUT "" ~ output path
function deploy() {
  : "${DEPLOY_OUTPUT:="${DEPLOY_TARGET}/build"}"  # set default from another flag
}
```

### Global pre-flight checks

Override `_call` in your entry point or module to run validation before dispatch:

```bash
_call() {
  # skip checks for help/completion
  case "$1" in help|shortlist|--help|-h|--version|-V) _default_call "$@"; return ;; esac

  # pre-flight
  command -v docker >/dev/null || { _error "docker is required"; exit 1; }

  _default_call "$@"
}
```

### Custom help sections

Override `_help` to append or replace the default output:

```bash
_help() {
  _default_help
  printf "  ${_B}Examples:${_RST}\n"
  printf "  ${_DIM}%s${_RST}\n" "mytool deploy --env staging"
  printf "  ${_DIM}%s${_RST}\n" "mytool deploy --env production --dry-run"
  echo ""
}
```

### Deeper command nesting

oosh natively supports two levels (`cli module command`). For deeper nesting like `mytool db migrate up`, override `_shortlist` and `_call` in your module to add a sub-group:

```bash
#!/bin/bash
#@module DB - database operations

. ${MODULES_DIR}/../oo.sh

# --- sub-group: migrate ---
_migrate_commands="up down status"

migrate-up()     { echo "running migrations..."; }
migrate-down()   { echo "rolling back..."; }
migrate-status() { echo "pending: 3"; }

# --- top-level commands ---
#@public ~ seed the database
function seed() { echo "seeding..."; }

_shortlist() {
  case "$1" in
    migrate)
      # third level: mytool db migrate <tab>
      if [[ -n "$2" ]]; then
        _default_shortlist migrate "$2"  # handle flags on migrate sub-commands
      else
        echo $_migrate_commands
      fi ;;
    *)
      _default_shortlist "$@"
      echo migrate  # add migrate as a completable word alongside seed, help
      ;;
  esac
}

_call() {
  case "$1" in
    migrate)
      local sub="${2:-help}"; shift 2 2>/dev/null || shift
      case "$sub" in
        up|down|status) "migrate-${sub}" "$@" ;;
        help) printf "\n  Usage: db migrate [ ${_migrate_commands} ]\n\n" ;;
        *)    _error "unknown migrate command '${sub}'"; exit 2 ;;
      esac ;;
    *) _default_call "$@" ;;
  esac
}

main $0 "$@"
```

This gives you `mytool db migrate up`, `mytool db migrate status`, etc. with working tab completion at every level. The pattern scales — add more sub-groups by extending the `case` statements in `_shortlist` and `_call`.

## ⏱️ Performance

oosh parses annotations at runtime — no compilation, no caching. The display and dispatch layer (`help`, `shortlist`, `_call`) uses zero external process forks — all string operations are pure bash builtins (`${var%%pattern}`, `${var//old/new}`, glob matching). Here's the overhead vs a hand-rolled pure bash CLI (~130 lines of manual flag parsing, case statements, help text, and completion) doing the same job that oosh does in ~45 lines of annotations.

**macOS (bash 3.2, Apple Silicon, 20 runs)**

| Operation | bash | oosh | Overhead |
|---|---|---|---|
| Tab-complete: top-level | 16ms | 27ms | +11ms |
| Tab-complete: command flags | 16ms | 27ms | +11ms |
| Tab-complete: enum values | 16ms | 27ms | +11ms |
| Help | 16ms | 33ms | +17ms |
| Dispatch: simple command | 16ms | 26ms | +10ms |
| Dispatch: enum + number flags | 16ms | 27ms | +11ms |
| Dispatch: all flags combined | 16ms | 27ms | +11ms |

**Linux (bash 5.1, Docker ubuntu:22.04, 20 runs)**

| Operation | bash | oosh | Overhead |
|---|---|---|---|
| Tab-complete: top-level | 2ms | 8ms | +6ms |
| Tab-complete: command flags | 2ms | 8ms | +6ms |
| Tab-complete: enum values | 2ms | 9ms | +7ms |
| Help | 2ms | 10ms | +8ms |
| Dispatch: simple command | 2ms | 9ms | +7ms |
| Dispatch: enum + number flags | 2ms | 9ms | +7ms |
| Dispatch: all flags combined | 2ms | 9ms | +7ms |

Worth noting: the pure bash baseline is ~130 lines of tedious boilerplate (manual `case` flag parsing, `_parse_global_flags`, per-command `while/case` loops, hand-written help text, hand-written completion function). The oosh module is ~45 lines of annotations. That's the trade-off — 6-17ms overhead for 3x less code and zero manual flag parsing. All times include bash startup (~14-16ms on macOS, ~2ms on Linux).

Usage errors (invalid flags, missing required flags, unknown commands) exit with code 2 following POSIX convention. Runtime errors exit with code 1.

Happy hacking! 🎉
