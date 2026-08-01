# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this plugin does

osc-colors.nvim is a Neovim colorscheme that has no scheme registry and no named schemes. It queries the host
terminal live via OSC 4 (ANSI colors 1-6) and OSC 10/11 (fg/bg), synthesizes a full base16 palette from the
replies, and feeds that into a highlight-building engine forked from [tinted-nvim]. There is no dependency on
tinty/tinted-shell/tinted-theming — whatever the terminal is currently rendering with is what Neovim gets
painted with, including inside devcontainers/SSH sessions where the OSC round-trip tunnels back through the PTY.

## Commands (via `just`, run inside the dev container)

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

No local Lua/Rust toolchain is required — this project targets development inside the dev container (Neovim,
vusted, luacheck, stylua, lemmy-help preinstalled). Open in VS Code and "Dev Containers: Reopen in Container",
or use the `devcontainer` CLI / GitHub Codespaces.

Tests live in `tests/*_spec.lua` and use vusted (busted-style `describe`/`it`, with `luassert`). `.luacheckrc`
declares `vim` as a global and busted globals (`describe`, `it`, `before_each`, `after_each`, `assert`) as
read-only.

## Architecture

### Data flow: OSC query → base16 palette → highlight groups

1. **`osc.lua`** is the *only* palette source. On `UIEnter`/`FocusGained` (configurable via `refresh_on`) it
   sends OSC 4/10/11 escape sequences via `nvim_ui_send`, collects replies from `TermResponse` autocmd events
   (200ms timeout), and synthesizes a full base16 palette (`base00`-`base0F`):
   - `base00`/`base07` = OSC 11/10 (bg/fg)
   - `base08`,`base0A`,`base0B`,`base0C`,`base0D`,`base0E` = OSC 4 replies for ANSI 1-6
   - `base01`-`base06` = grayscale ramp interpolated between bg and fg
   - `base09` (orange) = 60/40 lerp of red/yellow; `base0F` (brown) = red lerped 30% toward bg — these two
     have no ANSI slot of their own and are the values most likely to want taste-adjusting
   - Result is cached to `stdpath("cache")/osc-colors-palette.lua` so the next startup paints instantly,
     before the async query resolves. If the terminal never answers and there's no cache, osc-colors leaves
     Neovim's defaults untouched — there's no bundled fallback palette by design.
2. **`colors.lua`** normalizes whatever palette shape it's given (flat base16 slots, base24, or the tinted8
   tree) into the canonical dual form: legacy `base00`-`base0F`/`base10`-`base17` slots *and* the derived
   `palette`/`ui`/`syntax` tree, deep-merged with "existing values win" semantics. This is a straight port of
   tinted-nvim's template-generation logic (`templates/base16.lua.mustache` etc.), reimplemented in Lua.
3. **`highlights/init.lua`** (`M.build`) is the aggregation point: it re-normalizes the palette, then merges
   output from the core domain builders (`core`, `syntax`, `treesitter`, `lsp`, `diagnostics` — always on),
   then opt-in integration builders (`telescope`, `notify`, `cmp`, `blink`, `dapui`, `lualine`, `snacks`, keyed
   by `cfg.highlights.integrations`), then `lazy.nvim` plugin-spec `highlights` tables (if
   `use_lazy_specs`), then user `cfg.highlights.overrides(palette)` — in that precedence order, last write
   wins per highlight group. Only after all merging does it resolve `fg`/`bg`/`sp` values: hex passes through,
   `"none"` becomes `NONE`, alias strings resolve via `aliases.map` + `utils.lookup` against the palette tree,
   and `{ darken = ..., amount = ... }`/`{ lighten = ... }` tables compute an adjusted hex against
   background/foreground. ctermfg/ctermbg are back-filled from a hex→cterm map when a resolved hex matches a
   known ANSI slot.
4. **`init.lua`** (`M.apply`) is the only place that touches `vim.api.nvim_set_hl`/`vim.o.termguicolors`/
   `vim.g.colors_name`: given a palette it normalizes, builds highlights + terminal colors, clears the
   previous colorscheme if one was set, applies, and fires a synthetic `ColorScheme` autocmd. `M.setup` paints
   once from the disk cache immediately (for instant startup), then wires `M.refresh` (→
   `osc.refresh_async(M.apply)`) to the configured autocmd events and registers `:OscColorsRefresh`.

### Fork lineage — what's original vs. ported

Only `osc.lua` (the palette source) and the OSC-specific parts of `init.lua`/`health.lua` are original to this
project. Everything else that turns a palette into ~600 Neovim highlight groups (`colors.lua`, `aliases.lua`,
`terminal.lua`, `utils.lua`, all of `highlights/`, `lua/lualine/themes/osc-colors.lua`) is forked with minimal
changes from [tinted-nvim] — when working in those files, prefer matching tinted-nvim's existing conventions
over introducing new ones, since divergence makes future upstream diffing harder. `types.lua` documents the
palette/config shapes with `@class`/`@field` annotations consumed by lua-language-server and lemmy-help.

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
