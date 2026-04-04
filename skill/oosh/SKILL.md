---
name: oosh
description: "Scaffold a new bash CLI using the oosh framework. Use /oosh <name> to generate a complete CLI with entry point, tab completion, modules directory, and sample modules. Trigger when the user wants to create a new bash CLI tool or shell script with flags and completion."
---

# /oosh <name> — Scaffold a new CLI

Run the oosh generator:

```bash
oosh <name>
```

This creates `~/.<name>/` with:
- Entry point (`<name>.sh`) — routes commands to modules
- `oo.sh` — the framework engine
- Completion scripts (bash + zsh)
- `modules/` directory with sample modules (hello, install, uninstall)

After scaffolding, explain what was created and offer to create additional modules using `/oosh-module`.

For the annotation syntax and conventions, read `references/annotations.md` in this skill directory.
