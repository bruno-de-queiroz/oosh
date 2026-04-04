---
name: oosh-module
description: "Create a new module for an oosh CLI. Use /oosh-module <cli> <module> to generate an annotated .sh file in the CLI's modules directory. Trigger when the user wants to add a command, module, or feature to an existing oosh CLI."
---

# /oosh-module <cli> <module> — Create a new module

Create a new module file in the CLI's modules directory.

## Steps

1. Determine the modules path: `~/.<cli>/modules/` (default) — if the CLI was generated to a custom path, ask the user
2. Ask what commands and flags the module should expose
3. Write `<module>.sh` following the conventions below
4. Run `oosh lint <cli> <module>` to validate the new module

## Conventions

Read `references/annotations.md` in this skill directory for the full annotation reference and module template.

Key rules:
- File starts with `#!/bin/bash` and `#@module <Name> - <description>`
- Import the engine: `. ${MODULES_DIR}/../oo.sh`
- Variable names: `UPPER_SNAKE_CASE`, prefixed with module name (e.g., `DEPLOY_ENV` in `deploy.sh`)
- End with `main $0 "$@"`
- No `sed`, `awk`, `grep` in hot paths — bash builtins only
- Bash 3.2 compatible
