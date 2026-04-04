---
name: oosh-trace
description: "Profile tab-completion performance for an oosh CLI. Use /oosh-trace <cli> [module] to measure shortlist and help timing, flag slow dynamic enum resolvers. Trigger when the user wants to check or optimize oosh completion speed."
---

# /oosh-trace <cli> [module] — Profile completion performance

Run the completion profiler:

```bash
oosh trace <cli> [module]
```

## Analyze output

The profiler measures every shortlist and help path. Flag any operation exceeding **150ms** (the oosh performance budget, which includes bash startup).

If dynamic enum resolvers are slow, suggest:
- Caching the resolver output
- Making the resolver async-safe
- Replacing with a static enum if the values rarely change

Exit code 1 means at least one path exceeded the threshold.
