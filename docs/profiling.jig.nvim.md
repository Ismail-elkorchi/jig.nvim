# profiling.jig.nvim.md

## Startup Profiling
Use Neovim built-in startup timing:

```bash
nvim --startuptime /tmp/jig.startuptime.log -u ./init.lua '+qa'
```

Inspect the slowest entries:

```bash
tail -n 60 /tmp/jig.startuptime.log
```

## Compare Two Runs
Run twice on clean startup and compare top entries:

```bash
nvim --startuptime /tmp/jig.a.log -u ./init.lua '+qa'
nvim --startuptime /tmp/jig.b.log -u ./init.lua '+qa'
```

Focus on:
- plugin init spikes
- repeated provider checks
- optional module load on safe profile (should be absent)

## Recovery Profiling
For recovery baseline:

```bash
NVIM_APPNAME=jig-safe nvim --startuptime /tmp/jig.safe.log -u ./init.lua '+qa'
```
