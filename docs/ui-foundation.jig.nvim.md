# ui-foundation.jig.nvim.md

Canonical help: `:help jig`

## Stable Semantic Highlight API
The following highlight groups are stable API:
- `JigUiDiagnostics`
- `JigUiAction`
- `JigUiInactive`
- `JigUiAccent`
- `JigUiNeutral`
- `JigUiDanger`
- `JigUiWarning`

Palette values are implementation detail and may evolve per profile.

## Active/Inactive Chrome Rules
- Active statusline uses `JigStatuslineActive`.
- Inactive statusline uses `JigStatuslineInactive`.
- Active winbar uses `JigWinbarActive`.
- Inactive winbar uses `JigWinbarInactive`.

## Accessibility Profiles
Set profile:
```vim
:JigUiProfile default
:JigUiProfile high-contrast
:JigUiProfile reduced-decoration
:JigUiProfile reduced-motion
```

Profile effects:
- `high-contrast`: stronger fg/bg contrast and emphasis.
- `reduced-decoration`: minimal float borders.
- `reduced-motion`: disables motion-oriented cues (policy flag only; no cmdline animation enabled).

## Icon Fallback Modes
```vim
:JigIconMode auto
:JigIconMode nerd
:JigIconMode ascii
```

- `auto`: choose by Nerd Font detection.
- `ascii`: force ASCII symbols for legibility.

## Cmdline and Float Policy
- Cmdline path is native and baseline-safe (`:` is not hijacked by default).
- Float design system (`lua/jig/ui/float.lua`) defines:
  - border hierarchy (`primary`, `secondary`, `tertiary`)
  - elevation model (`zindex` + `winhighlight`)
  - collision policy (editor-relative floats shift down to avoid overlap)
- `NVIM_APPNAME=jig-safe` does not load optional UI modules.
