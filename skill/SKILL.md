---
name: oosh
description: "Annotation-driven bash CLI framework. Use /oosh to scaffold new CLIs, create modules, lint annotations, and profile tab-completion performance. Trigger on /oosh or when the user wants to create bash CLI tools, shell scripts with flags/completion, or work with oosh projects."
---

# oosh — CLI Framework Skill

Parse the arguments to determine the subcommand:

| Pattern | Action |
|---|---|
| `/oosh <name>` | Scaffold a new CLI |
| `/oosh new-module <cli> <module>` | Create a new module in an existing CLI |
| `/oosh lint <cli> [module]` | Lint annotations and report/fix issues |
| `/oosh trace <cli> [module]` | Profile tab-completion performance |

If no arguments are provided, ask the user what they'd like to do.

---

## 1. Scaffold: `/oosh <name>`

Run the oosh generator to create a new CLI:

```bash
oosh <name>
```

This creates `~/.name/` with: entry point, oo.sh engine, completion scripts, and a `modules/` directory with sample modules (hello, install, uninstall).

After scaffolding, explain what was created and offer to create additional modules.

## 2. New Module: `/oosh new-module <cli> <module>`

Create a new module file at the CLI's modules directory. Determine the path:
- Check `~/.cli/modules/` (default location)
- If the CLI was generated to a custom path, ask the user

Write the module file following the template below. Ask the user what commands and flags the module should expose before writing.

### Module Template

```bash
#!/bin/bash
#@module <ModuleName> - <description>

#import oo.sh
. ${MODULES_DIR}/../oo.sh

# Global flags (available to all commands)
#@flag -v|--verbose <MODULE>_VERBOSE "false" boolean ~ enable verbose output

# Command-scoped flag (only for this command)
#@public ~ <command description>
#@flag -e|--env <MODULE>_ENV "prod" enum(dev,staging,prod) ~ target environment
function deploy() {
  echo "env=${<MODULE>_ENV}"
}

#@protected ~ internal helper
function _validate() {
  echo "validating..."
}

main $0 "$@"
```

## 3. Lint: `/oosh lint <cli> [module]`

Run the annotation linter:

```bash
oosh lint <cli> [module]
```

Parse the output. If errors are found, offer to run with `--fix` to auto-correct:
- Rename variables to match module prefix convention
- Add missing `#@description` annotations
- Escape unquoted strings in defaults

If warnings are found, explain each one and suggest fixes.

## 4. Trace: `/oosh trace <cli> [module]`

Profile tab-completion performance:

```bash
oosh trace <cli> [module]
```

Parse the output. Flag any operations exceeding 150ms. If dynamic enum resolvers are slow, suggest:
- Caching the resolver output
- Making the resolver async-safe
- Using static enums instead

---

## Annotation Reference

### File-level
```bash
#@module Description          # module name + description (top of file)
#@version x.y.z               # version string (top of file)
```

### Function visibility
```bash
#@public [~ description]      # exposed in help + shortlist
#@protected [~ description]   # callable but hidden from help
#@default                     # called when no command is given (zero args)
```

### Flag syntax
```bash
#@flag -s|--long VAR "default" [type] [~ description]
```

**Types:** `boolean`, `number`, `file`, `dir`, `enum(a,b,c)`, `enum(${func})`, `array`, `array(enum(...))`, `required`, `required:type`

**Env var fallback:** Use `"${ENV_VAR}"` or `"${ENV_VAR:-fallback}"` as default.

Flags declared after `#@public`/`#@protected` but before `function` are **scoped** to that command — shown indented in help and only offered in tab-completion when that command is selected.

### Conventions
- Variable names: `UPPER_SNAKE_CASE`, prefixed with module name (e.g., `DEPLOY_ENV` in `deploy.sh`)
- Every module ends with: `main $0 "$@"`
- No external tools (`sed`, `awk`, `grep`) in hot paths — bash builtins only
- Bash 3.2 compatible: no associative arrays, no `mapfile`, no `printf '%q'`, no `[[ -v var ]]`
- Default values must be valid for the declared type (e.g., enum default must be in the enum list)

### Exit codes
- `0` — success
- `1` — runtime error
- `2` — usage error (unknown command, invalid flag, missing required flag)
