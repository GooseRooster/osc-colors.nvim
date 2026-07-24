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
---@field ui osc-colors.Config.Ui UI appearance options
---@field styles osc-colors.Config.Styles Text style overrides for syntax groups
---@field highlights osc-colors.Config.Highlights Highlight configuration
---@field refresh_on string[] Autocmd events that trigger a fresh OSC query. Default: {"UIEnter", "FocusGained"}

---@class osc-colors.Config.Capabilities
---@field truecolor boolean Enable truecolor support (sets 'termguicolors'). Default: true
---@field undercurl boolean Use undercurl (falls back to underline if false). Default: false
---@field terminal_colors boolean Set terminal colors (g:terminal_color_0..17). Default: true

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
        truecolor = true,
        undercurl = false,
        terminal_colors = true,
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
