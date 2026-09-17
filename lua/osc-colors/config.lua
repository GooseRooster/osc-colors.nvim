---@mod osc-colors.config Configuration
---@brief [[
---All configuration is done through `setup()`. Defaults are shown below.
---
---Example:
--->lua
---  require("osc-colors").setup({
---    ui = { transparent = true },
---  })
---<
---@brief ]]

local M = {}

---@class osc-colors.Config
---@field capabilities osc-colors.Config.Capabilities Terminal capability options
---@field mapping "soul"|"base16" Highlight mapping mode. Default: `"soul"`
-- `"soul"` derives highlight-role colors from the palette's extracted
-- "soul" (dominant hues, chroma envelope, lightness envelope) via OKLCH
-- color math, with semantic exceptions (errors/warnings/diffs) kept
-- anchored to their conventional hue sectors. `"base16"` is the classic
-- static base16 slot mapping.
---@field soul osc-colors.Config.Soul Soul-mapping tuning knobs (only used when `mapping = "soul"`)
---@field ui osc-colors.Config.Ui UI appearance options
---@field styles osc-colors.Config.Styles Text style overrides for syntax groups
---@field highlights osc-colors.Config.Highlights Highlight configuration
---@field refresh_on string[] Autocmd events that trigger a fresh OSC query. Default: {"UIEnter", "FocusGained"}

---@class osc-colors.Config.Capabilities
---@field truecolor boolean|"auto" Enable truecolor support (sets 'termguicolors'). Default: `"auto"`
-- `"auto"` is probe-informed: it only drops to exact 256-color indices when
-- the XTGETTCAP/env probe says the terminal is not truecolor; an inconclusive
-- probe behaves like `true` (the status quo). Legacy `true` forces
-- 'termguicolors' on; legacy `false` leaves it untouched.
---@field query_timeout_ms number Terminal reply wait per refresh round, in ms. Default: 200
---@field undercurl boolean Use undercurl (falls back to underline if false). Default: false
---@field terminal_colors boolean Set terminal colors (g:terminal_color_0..17). Default: true

---@class osc-colors.Config.Soul
---@field semantic "sector"|"derived" Semantic exception policy. Default: `"sector"`
-- `"sector"` keeps errors/warnings/diffs anchored to their conventional
-- hue sectors (the soul picks exact hue/chroma/lightness within the
-- sector); `"derived"` fully soul-derives them (experimental).
---@field contrast_target number Minimum WCAG contrast for text roles against the background. Default: 4.5
---@field chroma_ceiling_scale number Scales the soul's chroma envelope ceiling (1.0 = as extracted). Default: 1.0
---@field roles table<string, table> Per-role descriptor overrides, keyed by role name (see README for the role list)

---@class osc-colors.Config.Ui
---@field transparent boolean Leave Normal background unset. Default: false
---@field dim_inactive boolean Dim inactive windows. Default: false

---@class osc-colors.Config.StyleAttrs
---@field italic? boolean
---@field bold? boolean
---@field underline? boolean
---@field undercurl? boolean
---@field strikethrough? boolean

---@class osc-colors.Config.Styles
---@field comments osc-colors.Config.StyleAttrs
---@field keywords osc-colors.Config.StyleAttrs
---@field functions osc-colors.Config.StyleAttrs
---@field variables osc-colors.Config.StyleAttrs
---@field types osc-colors.Config.StyleAttrs

---@class osc-colors.Config.Highlights
---@field integrations table<string, boolean> Enable/disable plugin integrations (see README for the list)
---@field use_lazy_specs boolean Merge highlights from lazy.nvim plugin specs. Default: true
---@field overrides fun(palette: osc-colors.Palette): table Function returning highlight overrides

---@mod osc-colors.highlights Highlights
---@brief [[
---Overrides are returned as a table of highlight specs. Color values can be:
---
---  - Hex colors (`"#rrggbb"`)
---  - `"NONE"`
---  - Color aliases (e.g., `"red"`, `"background"`, `"foreground"`)
---  - Transform tables: `{ darken = <color>, amount = <number> }`
---    or `{ lighten = <color>, amount = <number> }`
---
---Complete color alias list:
---
---  - `background`
---  - `darkest_gray`
---  - `dark_gray`
---  - `gray`
---  - `bright_gray`
---  - `foreground`
---  - `bright_white`
---  - `brightest_white`
---  - `red`
---  - `bright_red`
---  - `orange`
---  - `yellow`
---  - `bright_yellow`
---  - `green`
---  - `bright_green`
---  - `cyan`
---  - `bright_cyan`
---  - `blue`
---  - `bright_blue`
---  - `purple`
---  - `bright_purple`
---  - `dark_red`
---
---Example override:
--->lua
---highlights = {
---  overrides = function(palette)
---    return {
---      Normal = { bg = "#ff0000" },
---      FloatBorder = { fg = palette.base03 },
---      CursorLine = { bg = "darkest_gray", fg = "foreground" },
---    }
---  end,
---}
---<
---
---If `highlights.use_lazy_specs` is true, tables named `highlights` inside
---lazy.nvim plugin specs are merged into the final highlight table.
---@brief ]]

---@type osc-colors.Config
M.defaults = {
    capabilities = {
        truecolor = "auto",
        query_timeout_ms = 200,
        undercurl = false,
        terminal_colors = true,
    },

    mapping = "soul",

    soul = {
        semantic = "sector",
        contrast_target = 4.5,
        chroma_ceiling_scale = 1.0,
        roles = {},
    },

    ui = {
        transparent = false,
        dim_inactive = false,
    },

    styles = {
        comments = { italic = true },
        keywords = {},
        functions = {},
        variables = {},
        types = {},
    },

    highlights = {
        integrations = {
            telescope = true,
            notify = true,
            cmp = true,
            blink = true,
            dapui = true,
            lualine = true,
            snacks = true,
            mini = true,
        },
        use_lazy_specs = true,

        overrides = function(_palette)
            return {}
        end,
    },

    refresh_on = { "UIEnter", "FocusGained" },
}

---@type osc-colors.Config?
M.options = nil

return M
