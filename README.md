# osc-colors.nvim

A Neovim colorscheme plugin that paints Neovim with whatever 16-color palette
your terminal is *currently* rendering with, queried live via OSC 4/10/11
escape sequences. There is no scheme registry, no external selector, and no
dependency on [tinty]/[tinted-shell]/tinted-theming being installed anywhere.
If your terminal answers OSC queries (directly, or tunneled back through a
devcontainer/SSH session's PTY), osc-colors follows it, including across
`tinty apply` switches, without restarting Neovim.

This is a fork of [tinted-nvim]'s highlight-group engine: the part that maps
a base16 palette onto ~600 correctly-aliased Neovim highlight groups across
core UI, treesitter, LSP, diagnostics, and popular plugins (telescope, cmp,
blink, dapui, lualine, notify, snacks). Only the palette *source* changed:
tinted-nvim resolves a *named* scheme from a file/env var/command that some
external tool (`tinty`) maintains; osc-colors has no names or external tool at
all, rather, it just asks the terminal what it's currently showing and hands that
straight to the same highlight-building engine.

If you don't use a terminal-driven workflow like this, you probably want
[tinted-nvim] itself, not this fork.

<img width="1162" height="1435" alt="image" src="https://github.com/user-attachments/assets/1df12b6f-af1e-4440-bc02-e252652ad697" />


## How it works

On `UIEnter` (and again on `FocusGained`, so switching your terminal's theme
in another window and tabbing back updates Neovim without a restart),
osc-colors sends:

- `OSC 4` queries for ANSI colors 1–6 (red/green/yellow/blue/magenta/cyan)
- `OSC 10`/`OSC 11` for the terminal's current foreground/background

...and synthesizes a full base16 palette from the replies: the grayscale ramp
(`base01`-`base06`) is interpolated between background and foreground, and the
two base16 slots with no ANSI color of their own — orange (`base09`) and brown
(`base0F`) — are derived from red/yellow and red/background respectively. The
result is cached to disk (`stdpath("cache")/osc-colors-palette.lua`) so the
next startup can paint instantly, before the (async, ~200ms timeout) live
query resolves.

If the terminal never answers (a non-OSC-capable terminal, tmux without
passthrough configured, a dumb `$TERM`) **and there's no cache yet**,
osc-colors leaves Neovim's own default colors untouched rather than guessing.

## Installation

### lazy.nvim

```lua
{
  "GooseRooster/osc-colors.nvim",
  priority = 1000, -- load colorscheme early
  lazy = false,     -- apply on startup
  opts = {
    -- your config overrides
  },
}
```

### Manual

```lua
require("osc-colors").setup({
  -- your config overrides
})
```

## Usage

There's nothing to load by name. osc-colors queries and paints
automatically. To force a fresh query (e.g. right after running `tinty apply`
in another window, if you don't want to wait for `FocusGained`):

```vim
:OscColorsRefresh
```

## Configuration

Everything is configured through a single `setup()` call. The default config
is here: [lua/osc-colors/config.lua].

```lua
require("osc-colors").setup({
  capabilities = {
    -- Enable truecolor support (sets `termguicolors`).
    truecolor = true, -- default `true`

    -- Some terminal emulators cannot draw undercurls; falls back to underline.
    undercurl = false, -- default `false`

    -- Set vim.g.terminal_color_0 .. vim.g.terminal_color_17.
    terminal_colors = true, -- default `true`
  },

  ui = {
    -- If true, Normal background is left unset (transparent).
    transparent = false, -- default `false`

    -- Dim background of inactive windows.
    dim_inactive = false, -- default `false`
  },

  -- Change text attributes for certain highlight groups.
  -- Supported attributes: italic, bold, underline, undercurl, strikethrough.
  styles = {
    comments  = { italic = true }, -- default `{ italic = true }`
    keywords  = {},
    functions = {},
    variables = {},
    types     = {},
  },

  highlights = {
    -- Enable/disable bundled highlight definitions for popular plugins.
    integrations = {
      telescope = true,
      notify    = true,
      cmp       = true,
      blink     = true,
      dapui     = true,
      lualine   = true,
      snacks    = true,
    },

    -- Merge `highlights = { ... }` tables found in lazy.nvim plugin specs.
    use_lazy_specs = true, -- default `true`

    -- Override highlight groups directly. Same shape as tinted-nvim's.
    overrides = function(palette)
      return {
        Normal = { bg = "#ff0000" },
        FloatBorder = { fg = palette.base03 },
        CursorLine = { bg = "darkest_gray", fg = "foreground" },
      }
    end,
  },

  -- Autocmd events that trigger a fresh OSC query.
  refresh_on = { "UIEnter", "FocusGained" }, -- default
})
```

<details>
<summary>Complete color alias list</summary>
<code>background</code><br>
<code>darkest_gray</code><br>
<code>dark_gray</code><br>
<code>gray</code><br>
<code>bright_gray</code><br>
<code>foreground</code><br>
<code>bright_white</code><br>
<code>brightest_white</code><br>
<code>red</code><br>
<code>bright_red</code><br>
<code>orange</code><br>
<code>yellow</code><br>
<code>bright_yellow</code><br>
<code>green</code><br>
<code>bright_green</code><br>
<code>cyan</code><br>
<code>bright_cyan</code><br>
<code>blue</code><br>
<code>bright_blue</code><br>
<code>purple</code><br>
<code>bright_purple</code><br>
<code>dark_red</code>
</details>

## Commands

- `:OscColorsRefresh` - re-query the terminal and repaint if the palette changed.

## API

- `require("osc-colors").get_palette()` - returns the current palette table.
- `require("osc-colors").get_palette_aliases()` - returns the palette using color aliases.
- `require("osc-colors").apply(palette)` - apply a flat `{ variant, base00..base0F }` table directly.
- `require("osc-colors").refresh()` - re-query the terminal now.

## Integrations

### `lualine.nvim`

Aside from setting `highlights.integrations.lualine = true`, set lualine's
theme to `"osc-colors"`:

```lua
require("lualine").setup({
  options = {
    theme = "osc-colors",
  },
})
```

## Health check

`:checkhealth osc-colors` reports whether `termguicolors` is on, whether a
palette is currently applied, whether a disk cache exists, and flags common
gotchas (running inside tmux without `allow-passthrough`, a `$TERM` that
doesn't look truecolor-capable).

## Troubleshooting

- **Colors never update inside tmux**: OSC 4/10/11 queries and replies only
  reach the outer terminal if tmux's `allow-passthrough` is set (and your
  tmux is new enough to relay the *replies* back to Neovim, not just forward
  the query). Run `:checkhealth osc-colors` — it flags this.
- **Nothing happens on a fresh machine / SSH session**: the terminal (or
  whatever's in the middle of the PTY chain) may not answer OSC queries at
  all. osc-colors leaves Neovim's defaults alone in that case rather than
  showing something wrong; there's no bundled fallback palette by design.
- Plugin highlights not taking effect? Ensure the integration is enabled in
  `highlights.integrations` or defined in your `overrides`.
- **A live refresh (`:OscColorsRefresh`) worked once but has gone silent**:
  set `OSC_COLORS_DEBUG=1` (before starting Neovim) and watch `:messages`
  after triggering a refresh — every OSC reply received, and whether the
  round completed, gets logged. Zero replies logged means the terminal (or
  something in the PTY chain) isn't answering the live query at all; some but
  not all eight, or replies with no completion log line, points at something
  swallowing them partway through. Neovim `<0.11` is a common cause of the
  latter (see `:checkhealth osc-colors`).

## Contributing

This project uses a [dev container] for a reproducible environment (Neovim,
vusted, luacheck, stylua, lemmy-help) and [just] as a command runner. No local
Lua/Rust toolchain needed — open the repo in VS Code and choose "Dev
Containers: Reopen in Container" (or use the `devcontainer` CLI / GitHub
Codespaces).

```sh
# List all justfile commands
just list

# Run all tests
just test

# Run a specific test file
just test-file tests/colors_spec.lua

# Update doc/osc-colors.txt
just docs

# Format files with stylua
just fmt
```

Want your own dotfiles/editor config inside the container too? See
[`.devcontainer/local.example`](.devcontainer/local.example) — opt-in, gitignored,
never affects other contributors or CI.

### Project structure

```
lua/osc-colors/
  init.lua          # Main entry point: setup/apply/refresh
  config.lua        # Default configuration
  osc.lua           # OSC 4/10/11 query, parsing, synthesis, disk cache
  colors.lua        # Palette shape normalizer (forked from tinted-nvim)
  highlights/        # Highlight group builders (forked from tinted-nvim, unchanged)
  aliases.lua        # Color alias mappings (forked from tinted-nvim, unchanged)
  terminal.lua        # Terminal color mapping (forked from tinted-nvim, unchanged)
  utils.lua            # Utility functions (forked from tinted-nvim, unchanged)
  health.lua           # :checkhealth osc-colors
lua/lualine/themes/
  osc-colors.lua       # lualine theme (forked from tinted-nvim, unchanged)
tests/                 # Test suite (vusted)
```

## Lineage

The highlight-building engine (`highlights/`, `colors.lua`, `aliases.lua`,
`terminal.lua`, `utils.lua`, the lualine theme) is forked with minimal changes
from [tinted-nvim] (MIT-licensed) — see [LICENSE] for the original copyright
notices. Everything selector/scheme-registry/compile-cache related was
removed; everything else that turns a palette into Neovim highlights was
kept.

## License

See [LICENSE].

[dev container]: https://containers.dev/
[just]: https://github.com/casey/just
[tinty]: https://github.com/tinted-theming/tinty
[tinted-shell]: https://github.com/tinted-theming/tinted-shell
[tinted-nvim]: https://github.com/tinted-theming/tinted-nvim
[lua/osc-colors/config.lua]: lua/osc-colors/config.lua
[LICENSE]: ./LICENSE
