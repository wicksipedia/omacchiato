---
name: Bug report
about: Something broken in the Omacchiato stack
---

**What happened / what you expected**


**Setup**
- macOS version:
- Mac model + displays (built-in / external, how many):
- Trackpads (built-in / Magic Trackpad / both):
- Apple Development signing identity present? (install.sh says at build time):
- Clone location (matters for TCC — `~/Documents` clones copy configs):

**Logs** — the stack writes its diagnostics to `/tmp`. Attach whatever
exists of:

```sh
ls -la /tmp/omacchiato-*.log
```

For bar issues also paste the failing item's state:

```sh
sketchybar --query <item>   # e.g. bluetooth, weather, space.1
```

**Reproduction** — steps, and whether it survives
`omacchiato-toggle off && omacchiato-toggle on`.
