local M = {}

---@param palette osc-colors.Palette
---@param _aliases table<string, string>
---@param cfg osc-colors.Config
---@return osc-colors.Highlights
function M.build(palette, _aliases, cfg)
    local sem = palette.semantics
    local hl = {
        DiagnosticError = { fg = sem.error },
        DiagnosticWarn = { fg = sem.warning },
        DiagnosticInfo = { fg = sem.info },
        DiagnosticHint = { fg = sem.hint },

        DiagnosticUnderlineError = {
            underline = not cfg.capabilities.undercurl,
            undercurl = cfg.capabilities.undercurl,
            sp = sem.error,
        },
        DiagnosticUnderlineWarn = {
            underline = not cfg.capabilities.undercurl,
            undercurl = cfg.capabilities.undercurl,
            sp = sem.warning,
        },
        DiagnosticUnderlineInfo = {
            underline = not cfg.capabilities.undercurl,
            undercurl = cfg.capabilities.undercurl,
            sp = sem.info,
        },
        DiagnosticUnderlineHint = {
            underline = not cfg.capabilities.undercurl,
            undercurl = cfg.capabilities.undercurl,
            sp = sem.hint,
        },

        DiagnosticFloatingError = { link = "DiagnosticError" },
        DiagnosticFloatingWarn = { link = "DiagnosticWarn" },
        DiagnosticFloatingInfo = { link = "DiagnosticInfo" },
        DiagnosticFloatingHint = { link = "DiagnosticHint" },

        DiagnosticSignError = { link = "DiagnosticError" },
        DiagnosticSignWarn = { link = "DiagnosticWarn" },
        DiagnosticSignInfo = { link = "DiagnosticInfo" },
        DiagnosticSignHint = { link = "DiagnosticHint" },

        DiagnosticVirtualTextError = { link = "DiagnosticError" },
        DiagnosticVirtualTextWarn = { link = "DiagnosticWarn" },
        DiagnosticVirtualTextInfo = { link = "DiagnosticInfo" },
        DiagnosticVirtualTextHint = { link = "DiagnosticHint" },
    }
    if vim.fn.has("nvim-0.9.0") == 1 then
        hl.DiagnosticOk = { fg = sem.success }
        hl.DiagnosticUnderlineOk = {
            underline = not cfg.capabilities.undercurl,
            undercurl = cfg.capabilities.undercurl,
            sp = sem.success,
        }
        hl.DiagnosticFloatingOk = { link = "DiagnosticOk" }
        hl.DiagnosticSignOk = { link = "DiagnosticOk" }
        hl.DiagnosticVirtualTextOk = { link = "DiagnosticOk" }
    end
    if vim.fn.has("nvim-0.6.0") == 0 then
        hl.LspDiagnosticsDefaultError = { link = "DiagnosticError" }
        hl.LspDiagnosticsDefaultWarning = { link = "DiagnosticWarn" }
        hl.LspDiagnosticsDefaultInformation = { link = "DiagnosticInfo" }
        hl.LspDiagnosticsDefaultHint = { link = "DiagnosticHint" }
        hl.LspDiagnosticsUnderlineError = { link = "DiagnosticUnderlineError" }
        hl.LspDiagnosticsUnderlineWarning = { link = "DiagnosticUnderlineWarn" }
        hl.LspDiagnosticsUnderlineInformation = { link = "DiagnosticUnderlineInfo" }
        hl.LspDiagnosticsUnderlineHint = { link = "DiagnosticUnderlineHint" }
        hl.LspDiagnosticsVirtualTextError = { link = "DiagnosticVirtualTextError" }
        hl.LspDiagnosticsVirtualTextWarning = { link = "DiagnosticVirtualTextWarn" }
        hl.LspDiagnosticsVirtualTextInformation = { link = "DiagnosticVirtualTextInfo" }
        hl.LspDiagnosticsVirtualTextHint = { link = "DiagnosticVirtualTextHint" }
        hl.LspDiagnosticsSignError = { link = "DiagnosticSignError" }
        hl.LspDiagnosticsSignWarning = { link = "DiagnosticSignWarn" }
        hl.LspDiagnosticsSignInformation = { link = "DiagnosticSignInfo" }
        hl.LspDiagnosticsSignHint = { link = "DiagnosticSignHint" }
    end

    return hl
end

return M
