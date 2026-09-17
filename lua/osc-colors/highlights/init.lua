-- Build the complete highlight table.
-- This module:
--   - collects highlights from all domains
--   - applies user overrides
--   - resolves color aliases
--   - returns a flat table ready for nvim_set_hl()

local M = {}

-- Domain builders (always on)
local core = require("osc-colors.highlights.core")
local syntax = require("osc-colors.highlights.syntax")
local treesitter = require("osc-colors.highlights.treesitter")
local lsp = require("osc-colors.highlights.lsp")
local diagnostics = require("osc-colors.highlights.diagnostics")
local aliases = require("osc-colors.aliases")
local utils = require("osc-colors.utils")
local oklch = require("osc-colors.oklch")

-- Integrations (opt in)
local integrations = {
    telescope = "osc-colors.highlights.telescope",
    notify = "osc-colors.highlights.notify",
    cmp = "osc-colors.highlights.cmp",
    blink = "osc-colors.highlights.blink",
    dapui = "osc-colors.highlights.dapui",
    lualine = "osc-colors.highlights.lualine",
    snacks = "osc-colors.highlights.snacks",
    mini = "osc-colors.highlights.mini",
}

-- Resolve a single color value.
local function resolve_color(value, palette)
    if type(value) == "table" then
        local amount = value.amount or 0
        if type(amount) ~= "number" then
            error("osc-colors: color transform amount must be a number")
        end

        local target = value.darken or value.lighten
        if not target then
            error("osc-colors: color transform requires darken or lighten")
        end

        local base = resolve_color(target, palette)
        if base == "NONE" then
            return "NONE"
        end
        if not utils.is_hex(base) then
            error("osc-colors: color transform requires a hex color")
        end
        if value.darken then
            local background = palette.ui.global.background.normal
            if not utils.is_hex(background) then
                error("osc-colors: background color could not be resolved")
            end
            return utils.darken(base, amount, background)
        end
        local foreground = palette.ui.global.foreground.normal
        if not utils.is_hex(foreground) then
            error("osc-colors: foreground color could not be resolved")
        end
        return utils.lighten(base, amount, foreground)
    end

    if type(value) ~= "string" then
        return value
    end

    local lower = value:lower()
    if lower == "none" then
        return "NONE"
    end

    -- hex color
    if utils.is_hex(value) then
        return value
    end

    -- alias
    local path = aliases.map[value]
    if path then
        local color = utils.lookup(palette, path)
        if color then
            return color
        end
    end

    error("osc-colors: color '" .. value .. "' is not a hex or alias")
end

-- Resolve aliases in a highlight spec.
-- `nearest` (optional) snaps unresolved hexes to the terminal's *real*
-- 256-color cube (queried via OSC 4 slots 16-255) by perceptual distance,
-- back-filling ctermfg/ctermbg even when the hex isn't an exact palette
-- match -- generic converters match against the nominal xterm cube, which
-- terminals routinely remap.
local function resolve_spec(spec, palette, hex_to_cterm, nearest)
    if spec.link then
        return spec
    end

    local out = {}
    for k, v in pairs(spec) do
        if k == "fg" or k == "bg" then
            local color = resolve_color(v, palette)
            out[k] = color
            -- Add cterm colors when we can map a resolved hex color to an ANSI slot.
            if utils.is_hex(color) then
                local cterm = hex_to_cterm[color:lower()]
                if cterm == nil and nearest then
                    cterm = nearest(color)
                end
                local cterm_key = k == "fg" and "ctermfg" or "ctermbg"
                if cterm and out[cterm_key] == nil then
                    out[cterm_key] = cterm
                end
            end
        elseif k == "sp" then
            local color = resolve_color(v, palette)
            out[k] = color
        else
            out[k] = v
        end
    end
    return out
end

-- Build full highlight table.
---@param palette osc-colors.Palette
---@param cfg osc-colors.Config
---@return table<string, osc-colors.Highlight>
function M.build(palette, cfg)
    -- Ensure palette is in canonical form (tree + legacy slots) regardless of
    -- whether it came from colors.resolve or was constructed directly (e.g. tests).
    local colors = require("osc-colors.colors")
    palette = colors.normalize(palette)

    local result = {}
    local palette_aliases = aliases.build(palette)

    -- helper to merge domain output
    local function merge(tbl)
        for group, spec in pairs(tbl or {}) do
            result[group] = spec
        end
    end

    -- core domains
    merge(core.build(palette, palette_aliases, cfg))
    merge(syntax.build(palette, palette_aliases, cfg))
    merge(treesitter.build(palette, palette_aliases, cfg))
    merge(lsp.build(palette, palette_aliases, cfg))
    merge(diagnostics.build(palette, palette_aliases, cfg))

    -- integrations
    local enabled = cfg.highlights and cfg.highlights.integrations or {}
    for name, module_path in pairs(integrations) do
        if enabled[name] then
            local mod = require(module_path)
            merge(mod.build(palette, palette_aliases, cfg))
        end
    end

    -- lazy.nvim plugin spec highlights (optional)
    if cfg.highlights and cfg.highlights.use_lazy_specs then
        local ok, lazy_config = pcall(require, "lazy.core.config")
        if ok and lazy_config and lazy_config.plugins then
            for _, plugin in pairs(lazy_config.plugins) do
                if plugin.highlights then
                    merge(plugin.highlights)
                end
            end
        end
    end

    -- user overrides (last)
    if cfg.highlights and type(cfg.highlights.overrides) == "function" then
        merge(cfg.highlights.overrides(palette))
    end

    -- resolve aliases
    local hex_to_cterm = utils.build_hex_to_cterm_map(palette, aliases.cterm)

    -- Real-cube awareness: exact matches against the terminal's actual
    -- cube slots, then perceptual nearest-match for everything else. On a
    -- probed 256 tier with no queried cube, the nominal xterm cube is the
    -- fallback (roles.lua snaps its generated colors to the same
    -- candidates, so gui and cterm stay consistent).
    local nearest = nil
    local tier = palette.capability and palette.capability.tier or "unknown"
    local cube = palette.cube or (tier == "256" and utils.nominal_cube() or nil)
    if type(cube) == "table" then
        local cube_coords = {}
        for idx, hex in pairs(cube) do
            if utils.is_hex(hex) then
                hex_to_cterm[hex:lower()] = hex_to_cterm[hex:lower()] or idx
                local L, a, b = oklch.hex_to_oklab(hex)
                table.insert(cube_coords, { idx = idx, L = L, a = a, b = b })
            end
        end
        local memo = {}
        nearest = function(hex)
            local key = hex:lower()
            if memo[key] ~= nil then
                return memo[key]
            end
            local L, a, b = oklch.hex_to_oklab(hex)
            local best, best_d = nil, math.huge
            for _, c in ipairs(cube_coords) do
                local d = (L - c.L) ^ 2 + (a - c.a) ^ 2 + (b - c.b) ^ 2
                if d < best_d then
                    best, best_d = c.idx, d
                end
            end
            memo[key] = best
            return best
        end
    end

    local resolved = {}
    for group, spec in pairs(result) do
        resolved[group] = resolve_spec(spec, palette, hex_to_cterm, nearest)
    end

    return resolved
end

-- Apply highlights.
---@param highlights table<string, osc-colors.Highlight>
function M.apply(highlights)
    for group, spec in pairs(highlights) do
        vim.api.nvim_set_hl(0, group, spec)
    end
end

return M
