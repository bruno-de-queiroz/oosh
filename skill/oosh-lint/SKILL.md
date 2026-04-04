---
name: oosh-lint
description: "Lint oosh CLI annotations for errors and warnings. Use /oosh-lint <cli> [module] to check annotation syntax, flag types, variable naming, and structural issues. Offers --fix for auto-correction. Trigger when the user wants to validate or fix oosh annotations."
---

# /oosh-lint <cli> [module] — Lint annotations

Run the annotation linter:

```bash
oosh lint <cli> [module]
```

## Analyze output

- **Errors** (exit code 1): malformed flags, invalid types, duplicate flags, orphaned visibility annotations. Offer to run with `--fix` to auto-correct.
- **Warnings** (exit code 0): missing descriptions, variable naming conventions, missing `#@module`, missing `main $0 "$@"`, env var shadows. Explain each and suggest manual fixes.

## Auto-fix capabilities (`--fix`)

```bash
oosh lint <cli> [module] --fix
```

Fixes: rename variables to match module prefix, add missing descriptions, escape unquoted strings in defaults. After fixing, re-run lint to confirm clean output.
