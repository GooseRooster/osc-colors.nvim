local M = {}

---@param palette osc-colors.Palette
---@param _aliases table<string, string>
---@param _cfg osc-colors.Config
---@return osc-colors.Highlights
function M.build(palette, _aliases, _cfg)
    local pal = palette.palette
    return {
        TelescopeNormal = { link = "Normal" },
        TelescopeSelection = { link = "Visual" },
        TelescopeBorder = { link = "FloatBorder" },
        TelescopeMatching = { fg = pal.blue.normal },
        TelescopeTitle = { fg = pal.blue.normal },
        TelescopeSelectionCaret = { fg = pal.brown.normal },
        TelescopePreviewLine = { link = "Visual" },
    }
end

return M
