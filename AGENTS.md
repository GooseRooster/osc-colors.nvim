# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, opencode, etc.) when working with code in this
repository.

## What this plugin does

osc-colors.nvim is a Neovim colorscheme that has no scheme registry and no named schemes. It queries the host
terminal live via OSC 4 (ANSI colors 1-6 and brights 9-14) and OSC 10/11 (fg/bg), probes terminal color
capability via XTGETTCAP, synthesizes a full base16 palette from the replies (plus the terminal's real
256-color cube when needed), and by default runs a "soul mapping" pass — assigning highlight roles to the
scheme's own color families by salience — before feeding a highlight-building engine forked from
[tinted-nvim]. There is no dependency on tinty/tinted-shell/tinted-theming — whatever the terminal is
currently rendering with is what Neovim gets painted with, including inside devcontainers/SSH sessions where
the OSC round-trip tunnels back through the PTY.

## Commands (via `just`, inside the Nix dev shell: `nix develop`)

```sh
just list                          # list all commands
just test                          # run full test suite (vusted)
just test filter="pattern"         # run tests matching filter
just test-file tests/colors_spec.lua  # run a single test file
just lint                          # luacheck lua/ tests/
just check                         # lua-language-server --check
just fmt                           # stylua lua/ tests/
just fmt-check                     # stylua --check (CI mode)
just docs                          # regenerate doc/osc-colors.txt from lemmy-help annotations + helptags
```

No local Lua/Rust toolchain is required. This project's `flake.nix` provides a `nix develop` shell with
Neovim, vusted, luacheck, stylua, lua-language-server, and lemmy-help preinstalled and on `PATH`. Run `nix
develop` (flakes must be enabled), or use `nix develop --command <cmd>` / `direnv` if you prefer not to enter
an interactive shell.

Tests live in `tests/*_spec.lua` and use vusted (busted-style `describe`/`it`, with `luassert`). `.luacheckrc`
declares `vim` as a global and busted globals (`describe`, `it`, `before_each`, `after_each`, `assert`) as
read-only.

## Architecture

### Data flow: OSC query → capability tier → soul/roles → highlight groups

1. **`osc.lua`** is the *only* palette source. On `UIEnter`/`FocusGained` (configurable via `refresh_on`) it
   sends an XTGETTCAP probe plus OSC 4/10/11 escape sequences via `nvim_ui_send` (one batch, probe first —
   terminals answer in order, so the probe never adds latency), collects replies from `TermResponse`
   autocmd events (200ms default timeout, `capabilities.query_timeout_ms`), and synthesizes a full base16
   palette (`base00`-`base0F`) plus a capability tier:
   - `base00`/`base07` = OSC 11/10 (bg/fg)
   - `base08`,`base0A`,`base0B`,`base0C`,`base0D`,`base0E` = OSC 4 replies for ANSI 1-6
   - `brights` = `{ red=…, green=…, … }` from ANSI 9-14 — optional (a palette-phase timeout with every base
     slot answered still succeeds, possibly with partial/no brights) and deliberately *not* stored in the
     base24 slots `base12`-`base17`, whose presence would flip `colors.normalize` into base24 mode and change
     the `mapping = "base16"` output
   - `base01`-`base06` = grayscale ramp interpolated between bg and fg
   - `base09` (orange) = 60/40 lerp of red/yellow; `base0F` (brown) = red lerped 30% toward bg — these two
     have no ANSI slot of their own and are the values most likely to want taste-adjusting
   - `capability.tier` (`"truecolor"|"256"|"unknown"`) from `capability.classify` — probe result + env
     hints. Unknown deliberately assumes truecolor (status quo): a 256-only terminal approximates RGB
     escapes to its cube gently, while wrongly snapping a truecolor terminal loses fidelity for nothing.
   - The round optionally extends into a **cube phase**: OSC 4 for slots 16-255 (the terminal's *actual*
     256-color cube, which generic RGB→256 converters can't know). Lazy — `opts.cube(tier)` (wired in
     `init.M.refresh` to "soul mapping on a probed 256 tier") decides; skipped when the cache already
     carries a matching palette + cube; a partial cube on timeout still yields a complete palette.
   - Result (v3: `version`, base slots, `capability`, optional `brights`, optional `cube`; v1/v2 still load)
     is cached to `stdpath("cache")/osc-colors-palette.lua` so the next startup paints instantly, before the
     async query resolves. If the terminal never answers and there's no cache, osc-colors leaves Neovim's
     defaults untouched — there's no bundled fallback palette by design.
2. **`capability.lua`** (original) probes and decides the tier. Only replies naming `RGB`/`Tc` count as
   probe answers — Neovim ≥0.11 sends its *own* XTGETTCAP traffic (clipboard/OSC52 caps like `Ms`), whose
   replies land in the same TermResponse stream and must not be miscounted as probed-negatives. Inside
   tmux the probe is deliberately NOT passthrough-wrapped: tmux answers XTGETTCAP for itself, and it (not
   the outer terminal) is the rendering authority; a wrapped probe is silently dropped when
   `allow-passthrough` is off.
3. **`colors.lua`** normalizes whatever palette shape it's given (flat base16 slots, base24, or the tinted8
   tree) into the canonical dual form: legacy `base00`-`base0F`/`base10`-`base17` slots *and* the derived
   `palette`/`ui`/`syntax` tree, deep-merged with "existing values win" semantics. This is a port of
   tinted-nvim's template-generation logic, plus a static `semantics` table (`error`/`warning`/`info`/
   `hint`/`success`/`deprecated`/`diff.{add,delete,change}`) whose base16 values are identical to what the
   builders consumed before it existed.
4. **`soul.lua` + `roles.lua`** (original) are the "soul mapping" pass, applied in `init.M.apply` after
   `colors.normalize` when `cfg.mapping == "soul"` (the default; `"base16"` skips it entirely and must stay
   bit-identical to the old output):
   - `soul.extract` builds the scheme's color **families**: one per chromatic ANSI 1-6 anchor (gray anchors,
     C < 0.03, stay out); each bright is folded in as a `shade` when it's the same hue or a nearby hue at a
     clearly different lightness, otherwise promoted to its own `bright_<name>` family (solarized's
     orange/violet); perceptually identical families merge (`aliases`). Each family gets a **salience**:
     gamut-relative vividness (C / `oklch.max_chroma(L, H)` — raw chroma would always crown red/blue,
     whose gamut cusps sit far out), cohesion with the other vivid families, and deliberate shift off the
     stock ANSI hue. `ranked` is by salience; `dominant` is the top family (its hue tints neutrals and the
     gray ramp). No families → `achromatic`.
   - `roles.generate` runs an exact branch-and-bound search assigning each of six role **groups** (keyword,
     function, type, string, constant, special — weighted by prominence) to a family, maximizing
     prominence × salience plus an adjacency-weighted separation term (sharing a family is penalized, not
     banned). Lead roles take their family's color as-is; member roles vary it (bright shade, OKLCH L/C
     steps, hue drift steered away from neighboring groups). Semantic roles go through
     `soul.sector_color`: the scheme's own color for the conventional hue sector (source in sector → source
     clamped if just outside → another in-sector family not yet claimed → clamp), with a 0.1 chroma floor;
     diffs copy success/error/info. Contrast targets are enforced by stepping L toward the foreground.
     On tier-256, everything snaps (OKLab ΔE) to the real queried cube, or the nominal xterm cube.
   - Styles (`cfg.soul.styles`, default `"auto"`): italic/bold are spent where color runs out — a group
     lead sharing a family/near-identical color with a more prominent group, member roles within ΔE of a
     lead, everything for achromatic souls; headings always bold. `roles.style_highlights` (called by
     `highlights/init.lua` right after the core builders) merges `palette.role_styles` into the groups that
     paint each role, with "keep" semantics so `cfg.styles` and builder-set attributes win.
   - `roles.apply` rewrites the palette tree's role paths (bracketed segments like
     `name["function"]` are parsed properly — a silently dropped write here once left functions on their
     base16 slot), regenerates `semantics` + `ui.status`, stores `role_styles`, leans the gray ramp
     (base01-06 + their tree slots) a whisper toward the dominant hue, refines the tag-attribute accent
     from the assigned role hues, and stamps `_soul_applied` so it's idempotent (the flag survives
     `colors.normalize`'s deep-extend copying).
5. **`oklch.lua`** (original) is the perceptual math foundation: srgb↔OKLab/OKLCH (Björn Ottosson's
   reference), gamut clamping via chroma binary search with an epsilon (pure blue sits exactly on the
   boundary and would flunk its own round-trip), OKLab ΔE, WCAG contrast. NOTE: LuaJIT's `math.atan` takes
   one argument (no atan2) — use the local `atan2` helpers.
6. **`highlights/init.lua`** (`M.build`) is the aggregation point: it re-normalizes the palette (keep
   semantics preserve soul values), then merges output from the core domain builders (`core`, `syntax`,
   `treesitter`, `lsp`, `diagnostics` — always on), then soul role styles (`roles.style_highlights`, keep
   semantics, no-op in base16 mode), then opt-in integration builders (`telescope`,
   `notify`, `cmp`, `blink`, `dapui`, `lualine`, `snacks`, `mini`, keyed by `cfg.highlights.integrations`), then
   `lazy.nvim` plugin-spec `highlights` tables (if `use_lazy_specs`), then user
   `cfg.highlights.overrides(palette)` — in that precedence order, last write wins per highlight group. Only
   after all merging does it resolve `fg`/`bg`/`sp` values: hex passes through, `"none"` becomes `NONE`,
   alias strings resolve via `aliases.map` + `utils.lookup` against the palette tree, and
   `{ darken = ..., amount = ... }`/`{ lighten = ... }` tables compute an adjusted hex against
   background/foreground. ctermfg/ctermbg are back-filled: exact hex→cterm matches first (the map is
   deterministic — `.normal` tree paths win over spec-collapsed bright duplicates), then perceptual
   nearest-match against the real cube (or nominal cube on tier 256 without a queried one).
7. **`init.lua`** (`M.apply`) is the only place that touches `vim.api.nvim_set_hl`/`vim.o.termguicolors`/
   `vim.g.colors_name`: given a palette it normalizes, runs the soul pass (unless `mapping = "base16"`),
   builds highlights + terminal colors, clears the previous colorscheme if one was set, applies, and fires
   a synthetic `ColorScheme` autocmd. The `termguicolors` decision: `capabilities.truecolor` `true`/`false`
   keep their historical meanings (force on / leave untouched); `"auto"` sets it per the probed tier
   (256 → exact cube indices via cterm, else RGB — the status quo). `M.setup` paints once from the disk
   cache immediately (for instant startup), then wires `M.refresh` (→ `osc.refresh_async(M.apply, ...)`,
   with the lazy cube predicate) to the configured autocmd events and registers `:OscColorsRefresh`.

### Testing notes for the query/probe/soul pipeline

`tests/osc_spec.lua` feeds canned `TermResponse` events via `nvim_exec_autocmds` (see `fire()`); a full
round includes the ANSI 9-14 brights (a round without them only completes at the timeout). Cube tests
fire replies in a single burst with the round armed with a long timeout, relying on the completeness re-check
at the palette→cube transition. `tests/fixtures/schemes.lua` holds a dozen real terminal schemes (with their
actual brights) plus `to_palette`, mirroring osc.lua's synthesis; `tests/roles_spec.lua` uses it for the
cross-scheme invariants — notably the *divergence* test (no family may own keyword/function/type/string in
more than half the schemes), which encodes the point of soul mapping. `tests/roles_golden_spec.lua` pins
`soul in → role colors + styles + group assignment out` for gruvbox (warm/vivid), nord (cool/muted),
github_light (light bg) and a monochrome soul: the algorithm is pure math, so any drift is a deliberate (or
accidental) algorithm/descriptor change — when taste-tuning, regenerate the tables and let the diff be the
review.

### Fork lineage — what's original vs. ported

This is a **hard fork** — divergence from tinted-nvim is deliberate and upstream merges are not planned.
Original to this project: `osc.lua`, `capability.lua`, `soul.lua`, `roles.lua`, `oklch.lua`, `utils.lua`'s
nominal-cube/derive-accent extensions, the semantics tree, and the OSC/soul-specific parts of
`init.lua`/`health.lua`. The highlight-building engine (`colors.lua`, `aliases.lua`, `terminal.lua`, all of
`highlights/`, the lualine theme) is forked from [tinted-nvim]; when touching engine files prefer matching
tinted-nvim's existing conventions unless the change is part of the soul-mapping feature.
`highlights/mini.lua` (mini.nvim integration) is an exception: it has no tinted-nvim upstream equivalent and
is original to this project, added by re-targeting each mini.nvim module's own suggested default highlight
mapping onto osc-colors' equivalent groups.
`types.lua` documents the palette/config shapes with `@class`/`@field` annotations consumed by
lua-language-server and lemmy-help.

### Color aliases vs. palette tree

Internal highlight-domain builders (`highlights/core.lua`, `highlights/syntax.lua`, etc.) read the palette
tree directly (e.g. `palette.palette.red.normal`), never through aliases. `aliases.lua`'s `M.map` (alias name
→ dotted tree path) exists purely as a stable, human-readable surface for user-facing override callbacks
(`highlights.overrides`) and terminal color slot identity — e.g. a user override can write `fg = "red"` instead
of reaching into the tree.

### Docs generation

`doc/osc-colors.txt` is generated from `---@mod`/`---@brief`/`---@field` annotations in `init.lua` and
`config.lua` via `lemmy-help` (`just docs`) — don't hand-edit `doc/osc-colors.txt` directly, edit the doc
comments in those two files and regenerate.

[tinted-nvim]: https://github.com/tinted-theming/tinted-nvim
