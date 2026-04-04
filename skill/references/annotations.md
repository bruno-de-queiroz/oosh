# oosh Annotation Reference

## File-level
```bash
#@module Description          # module name + description (top of file)
#@version x.y.z               # version string (top of file)
```

## Function visibility
```bash
#@public [~ description]      # exposed in help + shortlist
#@protected [~ description]   # callable but hidden from help
#@default                     # called when no command is given (zero args)
```

## Flag syntax
```bash
#@flag -s|--long VAR "default" [type] [~ description]
```

**Types:** `boolean`, `number`, `file`, `dir`, `enum(a,b,c)`, `enum(${func})`, `array`, `array(enum(...))`, `required`, `required:type`

**Env var fallback:** Use `"${ENV_VAR}"` or `"${ENV_VAR:-fallback}"` as default.

Flags declared after `#@public`/`#@protected` but before `function` are **scoped** to that command — shown indented in help and only offered in tab-completion when that command is selected.

## Conventions
- Variable names: `UPPER_SNAKE_CASE`, prefixed with module name (e.g., `DEPLOY_ENV` in `deploy.sh`)
- Every module ends with: `main $0 "$@"`
- No external tools (`sed`, `awk`, `grep`) in hot paths — bash builtins only
- Bash 3.2 compatible: no associative arrays, no `mapfile`, no `printf '%q'`, no `[[ -v var ]]`
- Default values must be valid for the declared type (e.g., enum default must be in the enum list)

## Exit codes
- `0` — success
- `1` — runtime error
- `2` — usage error (unknown command, invalid flag, missing required flag)

## Module Template
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
