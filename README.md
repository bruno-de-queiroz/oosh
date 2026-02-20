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
| `#@flag -s\|--long VAR "default" [file\|dir] [~ description]` | Before a function or top-level | Declare a flag with short/long form, env var, default, and optional type |
| `#@description text` | After `#@flag` or `#@public`/`#@protected` | Legacy alternative to inline `~` descriptions |

Descriptions can be written inline using `~` on the same line, or on a separate `#@description` line (backward compatible). Flags declared after `#@public`/`#@protected` are scoped to that method and shown indented under it in help output.

## 🚩 Flag syntax

```bash
#@flag -e|--env VARNAME "default" ~ target environment

#@flag -f|--file FILEPATH "" file ~ path to config file (triggers file completion)

#@flag -d|--dir DIRPATH "" dir ~ output directory (triggers dir completion)
```

- Short and long forms separated by `|`
- Variable name must be `UPPER_SNAKE_CASE`
- Default value in double quotes (empty string = no default)
- Optional type: `file` or `dir` -- enables file/directory autocompletion for that flag 💡
- Optional description after `~` separator (or use `#@description` on the next line)

Flags are parsed from `$@` and exported as environment variables. If a flag isn't provided and the variable is unset, the default kicks in.

**Method-scoped flags**: Flags declared after `#@public`/`#@protected` (but before the `function` line) belong to that method. They're shown indented under the command in help output and only appear in tab-completion when that command is selected.

## 🧱 Module structure

```bash
#!/bin/bash
#@module MyModule - does useful things

#import oo.sh
. ${MODULES_DIR}/../oo.sh

#@flag -v|--verbose VERBOSE "false" ~ enable verbose output

#@public ~ deploy the app
#@flag -e|--env ENVIRONMENT "production" ~ target environment
function deploy() {
  echo "Deploying to ${ENVIRONMENT}..."
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

These are returned automatically when a flag is declared with the `file` or `dir` type. No extra wiring needed. 🪄

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

#@flag -x|--example VAR "default" ~ what this flag does

#@public ~ what this command does
function mycommand() {
  echo "doing things with ${VAR}"
}

main $0 "$@"
```

That's it -- no config files, no registration, no build step. The module is auto-discovered and immediately available with help text, flag parsing, and tab completion. Agents can scaffold entire CLIs by generating one module per concern. 🧩

Happy hacking! 🎉
