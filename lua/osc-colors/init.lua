---@mod osc-colors Introduction
---@toc osc-colors.contents
---@brief [[
---osc-colors is a Neovim colorscheme plugin that paints Neovim with whatever
---16-color palette the host terminal is currently rendering with, queried
---live via OSC 4/10/11 escape sequences. There is no scheme registry, no
---selector, and no dependency on tinty/base16-shell/tinted-theming being
---installed anywhere -- if your terminal answers OSC queries (directly, or
---tunneled back through a devcontainer/SSH session's PTY), osc-colors follows
---it, including across `tinty apply` switches without restarting Neovim.
---
---Its highlight-group mapping and plugin integrations (treesitter, LSP,
---telescope, cmp, blink, dapui, lualine, notify, snacks) are a fork of
---tinted-nvim's engine -- only the palette *source* changed.
---@brief ]]
---@mod osc-colors.install Installation
---@brief [[
---Using lazy.nvim:
--->lua
---  {
---    "GooseRooster/osc-colors.nvim",
---    lazy = false,
---    priority = 1000,
---    opts = {
---      -- your config overrides
---    }
---  }
---<
---@brief ]]
---@mod osc-colors.usage Usage
---@brief [[
---osc-colors queries the terminal and paints automatically -- there is
---nothing to load by name. To force a fresh query (e.g. right after running
---`tinty apply` in another window):
--->
---  :OscColorsRefresh
---<
---@brief ]]
---@mod osc-colors.commands Commands
---@brief [[
--->
---:OscColorsRefresh
---<
---  Re-query the terminal and repaint if the palette changed.
---@brief ]]

local M = {}

local config = require("osc-colors.config")
local colors = require("osc-colors.colors")
local highlights = require("osc-colors.highlights")
local terminal = require("osc-colors.terminal")
local osc = require("osc-colors.osc")
local aliases = require("osc-colors.aliases")

local public_state = {
    palette = nil,
    palette_aliases = nil,
}

---@mod osc-colors.api API
---@brief [[
---The main API functions for osc-colors.
---@brief ]]

---Apply a flat base16-shaped palette (`variant` + `base00`-`base0F`) to
---Neovim: builds and sets all highlight groups and terminal colors. No-ops if
---`palette` is nil (e.g. the terminal never answered the OSC query and there
---is no cached palette from a previous run).
---@param palette table|nil A flat palette table, e.g. from `require("osc-colors.osc").load_cached()`
---@usage `require("osc-colors").apply(require("osc-colors.osc").load_cached())`
function M.apply(palette)
    if not palette then
        return
    end

    local cfg = config.options or config.defaults

    palette = colors.normalize(palette)
    local hl_defs = highlights.build(palette, cfg)
    local term = terminal.build(palette, cfg)

    if vim.g.colors_name then
        vim.cmd("highlight clear")
    end

    if cfg.capabilities.truecolor ~= false then
        vim.o.termguicolors = true
    end
    vim.g.colors_name = "osc-colors"

    highlights.apply(hl_defs)
    terminal.apply(term)
    vim.o.background = palette.variant

    public_state.palette = palette
    public_state.palette_aliases = aliases.build(palette)

    vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "osc-colors" })
end

---Re-query the terminal for its live palette and apply it if it changed.
---Safe to call repeatedly; no-ops while a query is already in flight.
---@usage `require("osc-colors").refresh()`
function M.refresh()
    osc.refresh_async(M.apply)
end

---Configure and start the plugin. Paints instantly from the last cached
---palette (if any), then queries the terminal live on the events listed in
---`cfg.refresh_on` (default: `UIEnter`, `FocusGained`).
---@param opts? osc-colors.Config Configuration options (see |osc-colors.config|)
---@usage `require("osc-colors").setup({})`
function M.setup(opts)
    config.options = vim.tbl_deep_extend("force", {}, config.defaults, opts or {})

    M.apply(osc.load_cached())

    local augroup = vim.api.nvim_create_augroup("osc_colors_refresh", { clear = true })
    for _, event in ipairs(config.options.refresh_on or {}) do
        vim.api.nvim_create_autocmd(event, {
            group = augroup,
            callback = function()
                M.refresh()
            end,
        })
    end

    vim.api.nvim_create_user_command("OscColorsRefresh", function()
        M.refresh()
    end, {})
end

---Get the current Base16 palette.
---@return osc-colors.Palette|nil palette The current palette table (base00-base0F plus the derived tree), or nil.
---@usage `local palette = require("osc-colors").get_palette()`
function M.get_palette()
    return public_state.palette
end

---Get the current palette with color aliases resolved.
---Aliases include names like "background", "foreground", "red", "green", etc.
---@return table<string, string>|nil aliases A table mapping alias names to hex colors, or nil.
---@usage `local aliases = require("osc-colors").get_palette_aliases()`
function M.get_palette_aliases()
    return public_state.palette_aliases
end

return M
