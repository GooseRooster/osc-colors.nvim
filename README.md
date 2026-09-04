# osc-colors.nvim

A Neovim colorscheme plugin that paints Neovim with whatever palette your
terminal is *currently* rendering with, queried live via OSC 4/10/11 escape
sequences. Plus, a terminal capability probe (XTGETTCAP) and role-based
"soul" color mapping that goes beyond the terminal's 16 ANSI slots on
truecolor terminals. There is no scheme registry, no external selector, and
no dependency on [tinty]/[tinted-shell]/tinted-theming being installed
anywhere. If your terminal answers OSC queries (directly, or tunneled back
through a devcontainer/SSH session's PTY), osc-colors follows it, including
across `tinty apply` switches, without restarting Neovim.

This is a fork of [tinted-nvim]'s highlight-group engine: the part that maps
a palette onto ~600 correctly-aliased Neovim highlight groups across core UI,
treesitter, LSP, diagnostics, and popular plugins (telescope, cmp, blink,
dapui, lualine, notify, snacks). Only the palette *source* changed:
tinted-nvim resolves a *named* scheme from a file/env var/command that some
external tool (`tinty`) maintains; osc-colors has no names or external tool at
all, rather, it just asks the terminal what it's currently showing and hands that
straight to the same highlight-building engine.

If you don't use a terminal-driven workflow like this, you probably want
[tinted-nvim] itself, not this fork.

Please note this plugin is still heavily work in progress, but I hope you get as much value out of it as I do!

<img width="1162" height="1435" alt="image" src="https://github.com/user-attachments/assets/1df12b6f-af1e-4440-bc02-e252652ad697" />


## How it works

On `UIEnter` (and again on `FocusGained`, so switching your terminal's theme
in another window and tabbing back updates Neovim without a restart),
osc-colors sends:

- an `XTGETTCAP` probe for the terminal's `RGB`/`Tc` (truecolor) capabilities
- `OSC 4` queries for ANSI colors 1–6 (red/green/yellow/blue/magenta/cyan)
- `OSC 10`/`OSC 11` for the terminal's current foreground/background

...and synthesizes a full base16 palette from the replies: the grayscale ramp
(`base01`-`base06`) is interpolated between background and foreground, and the
two base16 slots with no ANSI color of their own — orange (`base09`) and brown
(`base0F`) — are derived from red/yellow and red/background respectively. The
result (plus the probed capability tier) is cached to disk
(`stdpath("cache")/osc-colors-palette.lua`) so the next startup can paint
instantly, before the (async, ~200ms timeout) live query resolves.

### Capability probing & graceful degradation

Env vars like `$COLORTERM` are treated as hints, never the decision-maker.
They're exactly the thing that dies in containers and over SSH. The XTGETTCAP
probe answers through the same PTY that carries the OSC replies, so it works
in the remote/container scenarios this plugin exists for. The resulting tier
decides how colors render:

- **truecolor / unknown** — free RGB via `termguicolors` (the status quo: a
  256-only terminal handed RGB approximates it to its cube and degrades
  gently, while the reverse would lose fidelity for nothing)
- **probed 256-only** — generated colors are snapped, by perceptual distance
  (OKLab), to the terminal's *actual* 256-color cube — queried via OSC 4 for
  slots 16-255, so remapped cube entries are respected (generic converters
  match against the nominal xterm cube; terminals routinely deviate). Queries
  run lazily: only when soul mapping is active on a 256-tier terminal.

### Soul mapping (default)

The concept of a Soul for the colorscheme is something I was thinking about while fighting the colorscheme working on a Blazor codebase at work.
I was switching colorschemes for testing (and for fun) and noticed over time that the base16 mappings for each role were becoming stale and weren't changing too much across colorschemes (though, to be fair, they still looked like they fit due to the palette sourcing at least)

So then my friday coffee-addled brain thought - what if we defined highlight groups by the relationship and role, then used OkLab color math to create a map for them? Could we insert some "soul" and character back into each colorscheme, while maintaining compatibility?

Thus the soul concept was born, in essence inspired by the unique palette-based role mappings some of the most popular vim colorschemes out there use.

In this system, highlight groups aren't assigned fixed slots: They're assigned *roles*.
Importance tier, hue offset from the scheme's dominant hue, chroma scale,
lightness weight all resolved through the palette's extracted **soul**
(circular hue statistics, chroma envelope, lightness envelope) with OKLCH
color math. A warm theme leans its whole role system warm; a monochrome theme
gets structured grayscale with lightness-based differentiation; the same
algorithm, radically different palettes out.

Semantic exceptions resist full relativization: errors, warnings, diffs and
friends stay anchored to their conventional hue *sectors* (errors are always
red-ish, whatever the scheme's soul), with the soul only placing the exact
hue, chroma and lightness within the sector. Set `mapping = "base16"` for the
classic static base16 slot mapping, bit-identical to the old behavior.

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
    -- Truecolor support (sets `termguicolors`). `"auto"` probes the terminal
    -- (XTGETTCAP + environment) and only drops to exact 256-color indices
    -- when the probe says the terminal is not truecolor; an inconclusive
    -- probe behaves like `true` (the status quo).
    truecolor = "auto", -- default `"auto"`; `true`/`false` for manual control

    -- How long to wait for terminal replies per refresh round, in ms.
    query_timeout_ms = 200, -- default `200`

    -- Some terminal emulators cannot draw undercurls; falls back to underline.
    undercurl = false, -- default `false`

    -- Set vim.g.terminal_color_0 .. vim.g.terminal_color_17.
    terminal_colors = true, -- default `true`
  },

  -- Highlight mapping mode: "soul" derives role colors from the palette's
  -- extracted soul via OKLCH color math (semantic exceptions stay anchored
  -- to their conventional hue sectors); "base16" is the classic static slot
  -- mapping, bit-identical to the old behavior.
  mapping = "soul", -- default `"soul"`

  -- Soul-mapping tuning knobs (only used when mapping = "soul").
  soul = {
    -- Semantic exception policy: "sector" keeps errors/warnings/diffs
    -- anchored to their conventional hue sectors; "derived" fully
    -- soul-derives them (experimental, cohesion over convention).
    -- think errors => mapping to a reddish color, etc
    semantic = "sector", -- default `"sector"`

    -- Minimum WCAG contrast for text roles against the background.
    contrast_target = 4.5, -- default `4.5`

    -- Scales the soul's chroma envelope ceiling (1.0 = as extracted).
    chroma_ceiling_scale = 1.0, -- default `1.0`

    -- Per-role descriptor overrides, keyed by role name. Roles include:
    -- keyword, type, import, heading, function, constant, float, character,
    -- escape, string, regexp, flow, modifier, tag, namespace, link,
    -- comment, punctuation, punct_section, variable, parameter, property,
    -- and the semantic roles: error, warning, info, hint, success,
    -- deprecated, diff_add, diff_delete, diff_change.
    --
    -- Syntax roles accept `offset` (hue degrees from the dominant hue),
    -- `weight` (0 = background, 1 = foreground lightness), and `chroma`
    -- (scale on the soul's chroma ceiling). Semantic roles accept `sector`
    -- (hue bounds in degrees) and `source` (preferred base slot).
    roles = {
      -- keyword = { offset = 12, weight = 0.8 },
      -- error = { sector = { 0, 30 } },
    },
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

`:checkhealth osc-colors` reports whether `termguicolors` is on, the probed
capability tier and what evidence decided it, whether a palette is currently
applied, the active mapping mode (plus the extracted soul descriptor when
soul mapping is on), whether a disk cache exists, and flags common gotchas
(running inside tmux without `allow-passthrough`, a `$TERM` that doesn't look
truecolor-capable).

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

## Known issues

- Still trying to figure out why Foot sometimes misbehaves.

## Contributing

This project uses a [Nix flake](https://nixos.org/) for a reproducible
development environment (Neovim, vusted, luacheck, stylua, lua-language-server,
lemmy-help) and [just] as a command runner. With Nix installed (with flakes
enabled), run `nix develop` to drop into a shell with everything on `PATH` —
no local Lua/Rust toolchain needed.

```sh
# Enter the dev shell
nix develop

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

### Project structure

```
lua/osc-colors/
  init.lua          # Main entry point: setup/apply/refresh, soul-pass hook
  config.lua        # Default configuration
  osc.lua           # OSC 4/10/11 + XTGETTCAP queries, parsing, cache (original)
  capability.lua    # Terminal capability probing & tier decision (original)
  soul.lua          # Soul descriptor extraction: circular hue stats, envelopes (original)
  roles.lua         # Role-based highlight color generation & tree application (original)
  oklch.lua         # OKLab/OKLCH color math, gamut clamping, ΔE, contrast (original)
  colors.lua        # Palette shape normalizer (forked from tinted-nvim)
  highlights/        # Highlight group builders (forked from tinted-nvim)
  aliases.lua        # Color alias mappings (forked from tinted-nvim)
  terminal.lua        # Terminal color mapping (forked from tinted-nvim)
  utils.lua            # Utility functions (forked from tinted-nvim)
  types.lua            # LuaLS/lemmy-help type annotations
  health.lua           # :checkhealth osc-colors
lua/lualine/themes/
  osc-colors.lua       # lualine theme (forked from tinted-nvim, unchanged)
tests/                 # Test suite (vusted)
```

## Lineage

The highlight-building engine (`highlights/`, `colors.lua`, `aliases.lua`,
`terminal.lua`, `utils.lua`, the lualine theme) is forked from
[tinted-nvim] (MIT-licensed) — see [LICENSE] for the original copyright
notices. This is a hard fork: the palette source (OSC querying, capability
probing, soul extraction, role-based mapping) is entirely original and
deliberately diverges from upstream rather than tracking it.

## License

See [LICENSE].

[just]: https://github.com/casey/just
[tinty]: https://github.com/tinted-theming/tinty
[tinted-shell]: https://github.com/tinted-theming/tinted-shell
[tinted-nvim]: https://github.com/tinted-theming/tinted-nvim
[lua/osc-colors/config.lua]: lua/osc-colors/config.lua
[LICENSE]: ./LICENSE
