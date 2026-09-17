-- mini.nvim (https://github.com/nvim-mini/mini.nvim) highlight groups.
--
-- mini.nvim is a collection of independently-usable modules, most of which
-- ship their own `H.create_default_hl()` mapping each `Mini*` group onto a
-- standard Vim/Neovim highlight group (`FloatBorder`, `DiagnosticFloating*`,
-- `TabLine(Sel)`, `Title`, `Comment`, etc). osc-colors already defines nearly
-- all of those groups, so most of this file just re-targets mini's own
-- suggested defaults at our equivalents explicitly (rather than relying on
-- `default = true` + highlight-group-already-set timing). Deviations from
-- mini's own default are called out per group below.
--
-- Only modules that define their own `Mini*` groups are covered here; things
-- like `mini.ai`/`mini.surround`'s textobjects, `mini.pairs`, `mini.comment`,
-- etc. either have no dedicated groups or are covered already (`mini.surround`
-- has exactly one group, included below).
local M = {}

---@param palette osc-colors.Palette
---@param _aliases table<string, string>
---@param _cfg osc-colors.Config
---@return osc-colors.Highlights
function M.build(palette, _aliases, _cfg)
    local pal = palette.palette
    local ui = palette.ui
    local sem = palette.semantics
    local diff = sem.diff
    local hl = {}

    -- mini.statusline ---------------------------------------------------
    -- Mode colors mirror the same Normal/Insert/Visual/Replace/Command
    -- convention used by the bundled lualine theme, instead of mini's own
    -- generic Cursor/Diff*/IncSearch links, so the two statusline plugins
    -- feel consistent when swapped in/out.
    hl.MiniStatuslineModeNormal = { fg = ui.global.background.normal, bg = pal.gray.normal, bold = true }
    hl.MiniStatuslineModeInsert = { fg = ui.global.background.normal, bg = pal.blue.normal, bold = true }
    hl.MiniStatuslineModeVisual = { fg = ui.global.background.normal, bg = pal.yellow.normal, bold = true }
    hl.MiniStatuslineModeReplace = { fg = ui.global.background.normal, bg = pal.red.normal, bold = true }
    hl.MiniStatuslineModeCommand = { fg = ui.global.background.normal, bg = pal.green.normal, bold = true }
    hl.MiniStatuslineModeOther = { fg = ui.global.background.normal, bg = pal.cyan.normal, bold = true }
    hl.MiniStatuslineDevinfo = { link = "StatusLine" }
    hl.MiniStatuslineFilename = { link = "StatusLineNC" }
    hl.MiniStatuslineFileinfo = { link = "StatusLine" }
    hl.MiniStatuslineInactive = { link = "StatusLineNC" }

    -- mini.tabline --------------------------------------------------------
    hl.MiniTablineCurrent = { link = "TabLineSel" }
    hl.MiniTablineVisible = { link = "TabLineSel" }
    hl.MiniTablineHidden = { link = "TabLine" }
    hl.MiniTablineModifiedCurrent = { link = "StatusLine" }
    hl.MiniTablineModifiedVisible = { link = "StatusLine" }
    hl.MiniTablineModifiedHidden = { link = "StatusLineNC" }
    hl.MiniTablineTabpagesection = { link = "Search" }
    hl.MiniTablineFill = { link = "Normal" }
    hl.MiniTablineTrunc = { link = "MiniTablineHidden" }

    -- mini.starter ----------------------------------------------------------
    hl.MiniStarterCurrent = { link = "Normal" }
    hl.MiniStarterFooter = { link = "Title" }
    hl.MiniStarterHeader = { link = "Title" }
    hl.MiniStarterInactive = { link = "Comment" }
    hl.MiniStarterItem = { link = "Normal" }
    hl.MiniStarterItemBullet = { link = "Delimiter" }
    hl.MiniStarterItemPrefix = { link = "WarningMsg" }
    hl.MiniStarterSection = { link = "Delimiter" }
    hl.MiniStarterQuery = { link = "MoreMsg" }

    -- mini.cursorword ---------------------------------------------------
    hl.MiniCursorword = { underline = true }
    hl.MiniCursorwordCurrent = { link = "MiniCursorword" }

    -- mini.indentscope ----------------------------------------------------
    hl.MiniIndentscopeSymbol = { link = "Delimiter" }
    hl.MiniIndentscopeSymbolOff = { link = "MiniIndentscopeSymbol" }

    -- mini.trailspace -----------------------------------------------------
    -- Deviation: mini's own default links to `Error`, but our `Error` group
    -- is fg-only. Trailing *spaces* have no glyph, so an fg-only highlight
    -- renders invisible; a background is required to actually see it.
    hl.MiniTrailspace = { bg = sem.error }

    -- mini.jump -------------------------------------------------------------
    -- SpellRare already respects `cfg.capabilities.undercurl` (underline vs.
    -- undercurl), so linking to it carries that preference through for free.
    hl.MiniJump = { link = "SpellRare" }

    -- mini.jump2d -----------------------------------------------------------
    -- Mirrors mini's own light/dark-aware contrast logic (reverse of
    -- Normal's fg/bg) using our own background/foreground roles directly.
    hl.MiniJump2dSpot =
        { fg = ui.global.background.normal, bg = ui.global.foreground.normal, bold = true, nocombine = true }
    hl.MiniJump2dSpotUnique = { link = "MiniJump2dSpot" }
    hl.MiniJump2dSpotAhead = { fg = pal.gray.normal, bg = ui.global.foreground.normal, nocombine = true }
    hl.MiniJump2dDim = { link = "Comment" }

    -- mini.notify -----------------------------------------------------------
    hl.MiniNotifyBorder = { link = "FloatBorder" }
    hl.MiniNotifyNormal = { link = "NormalFloat" }
    hl.MiniNotifyTitle = { link = "FloatTitle" }
    hl.MiniNotifyLspProgress = { link = "MiniNotifyNormal" }

    -- mini.hipatterns -------------------------------------------------------
    -- Deviation: mini's own default computes a bold/reverse flip of
    -- Diagnostic{Error,Warn,Info,Hint} at runtime. We define the resulting
    -- "badge" look explicitly (fg/bg pair) since the highlight resolver's
    -- ctermfg/ctermbg backfill only inspects `fg`/`bg` keys, not `reverse`.
    hl.MiniHipatternsFixme = { fg = ui.global.background.normal, bg = sem.error, bold = true }
    hl.MiniHipatternsHack = { fg = ui.global.background.normal, bg = sem.warning, bold = true }
    hl.MiniHipatternsTodo = { fg = ui.global.background.normal, bg = sem.info, bold = true }
    hl.MiniHipatternsNote = { fg = ui.global.background.normal, bg = sem.hint, bold = true }

    -- mini.pick ---------------------------------------------------------
    hl.MiniPickBorder = { link = "FloatBorder" }
    hl.MiniPickBorderBusy = { link = "DiagnosticFloatingWarn" }
    hl.MiniPickBorderText = { link = "FloatTitle" }
    hl.MiniPickCursor = { blend = 100, nocombine = true }
    hl.MiniPickIconDirectory = { link = "Directory" }
    hl.MiniPickIconFile = { link = "MiniPickNormal" }
    hl.MiniPickHeader = { link = "DiagnosticFloatingHint" }
    hl.MiniPickMatchCurrent = { link = "CursorLine" }
    hl.MiniPickMatchMarked = { link = "Visual" }
    hl.MiniPickMatchRanges = { link = "DiagnosticFloatingHint" }
    hl.MiniPickNormal = { link = "NormalFloat" }
    hl.MiniPickPreviewLine = { link = "CursorLine" }
    hl.MiniPickPreviewRegion = { link = "IncSearch" }
    hl.MiniPickPrompt = { link = "DiagnosticFloatingInfo" }
    hl.MiniPickPromptCaret = { link = "MiniPickPrompt" }
    hl.MiniPickPromptPrefix = { link = "MiniPickPrompt" }

    -- mini.files --------------------------------------------------------
    hl.MiniFilesBorder = { link = "FloatBorder" }
    hl.MiniFilesBorderModified = { link = "DiagnosticFloatingWarn" }
    hl.MiniFilesCursorLine = { link = "CursorLine" }
    hl.MiniFilesDirectory = { link = "Directory" }
    hl.MiniFilesFile = { link = "Normal" }
    hl.MiniFilesNormal = { link = "NormalFloat" }
    hl.MiniFilesTitle = { link = "FloatTitle" }
    hl.MiniFilesTitleFocused = { link = "FloatTitle" }

    -- mini.diff -----------------------------------------------------------
    -- Sign-column indicators follow the gitsigns-style convention (colored
    -- fg only, no bg) using the same semantic diff roles the rest of the
    -- theme already uses for Git/DiffAdd-style coloring.
    hl.MiniDiffSignAdd = { fg = diff.add }
    hl.MiniDiffSignChange = { fg = diff.change }
    hl.MiniDiffSignDelete = { fg = diff.delete }
    hl.MiniDiffOverAdd = { link = "DiffAdd" }
    hl.MiniDiffOverChange = { link = "DiffText" }
    hl.MiniDiffOverChangeBuf = { link = "MiniDiffOverChange" }
    hl.MiniDiffOverContext = { link = "DiffChange" }
    hl.MiniDiffOverContextBuf = {}
    hl.MiniDiffOverDelete = { link = "DiffDelete" }

    -- mini.map ------------------------------------------------------------
    hl.MiniMapNormal = { link = "NormalFloat" }
    hl.MiniMapSymbolCount = { link = "Special" }
    hl.MiniMapSymbolLine = { link = "Title" }
    hl.MiniMapSymbolView = { link = "Delimiter" }

    -- mini.animate ------------------------------------------------------
    hl.MiniAnimateCursor = { reverse = true, nocombine = true }
    hl.MiniAnimateNormalFloat = { link = "NormalFloat" }

    -- mini.completion -----------------------------------------------------
    hl.MiniCompletionActiveParameter = { link = "LspSignatureActiveParameter" }
    -- Deviation: mini's own default links to `DiagnosticDeprecated`, which
    -- osc-colors doesn't define. Defined directly instead.
    hl.MiniCompletionDeprecated = { fg = sem.deprecated, strikethrough = true }
    hl.MiniCompletionInfoBorderOutdated = { link = "DiagnosticFloatingWarn" }

    -- mini.snippets -------------------------------------------------------
    local underdouble = { underdouble = true }
    hl.MiniSnippetsCurrent = vim.tbl_extend("force", { sp = sem.warning }, underdouble)
    hl.MiniSnippetsCurrentReplace = vim.tbl_extend("force", { sp = sem.error }, underdouble)
    hl.MiniSnippetsFinal = vim.tbl_extend("force", { sp = sem.success }, underdouble)
    hl.MiniSnippetsUnvisited = vim.tbl_extend("force", { sp = sem.hint }, underdouble)
    hl.MiniSnippetsVisited = vim.tbl_extend("force", { sp = sem.info }, underdouble)

    -- mini.clue -----------------------------------------------------------
    hl.MiniClueBorder = { link = "FloatBorder" }
    hl.MiniClueDescGroup = { link = "DiagnosticFloatingWarn" }
    hl.MiniClueDescSingle = { link = "NormalFloat" }
    hl.MiniClueNextKey = { link = "DiagnosticFloatingHint" }
    hl.MiniClueNextKeyWithPostkeys = { link = "DiagnosticFloatingError" }
    hl.MiniClueSeparator = { link = "DiagnosticFloatingInfo" }
    hl.MiniClueTitle = { link = "FloatTitle" }

    -- mini.operators ------------------------------------------------------
    hl.MiniOperatorsExchangeFrom = { link = "IncSearch" }

    -- mini.test -----------------------------------------------------------
    hl.MiniTestEmphasis = { bold = true }
    hl.MiniTestFail = { fg = sem.error, bold = true }
    hl.MiniTestPass = { fg = sem.success, bold = true }

    -- mini.deps -----------------------------------------------------------
    -- Deviation: mini's own default links to Neovim's built-in `Added`/
    -- `Removed` groups, which osc-colors doesn't define. Defined directly
    -- against the same semantic diff roles used elsewhere instead.
    hl.MiniDepsChangeAdded = { fg = diff.add }
    hl.MiniDepsChangeRemoved = { fg = diff.delete }
    hl.MiniDepsHint = { link = "DiagnosticHint" }
    hl.MiniDepsInfo = { link = "DiagnosticInfo" }
    hl.MiniDepsMsgBreaking = { link = "DiagnosticWarn" }
    hl.MiniDepsPlaceholder = { link = "Comment" }
    hl.MiniDepsTitle = { link = "Title" }
    hl.MiniDepsTitleError = { link = "DiffDelete" }
    hl.MiniDepsTitleSame = { link = "DiffText" }
    hl.MiniDepsTitleUpdate = { link = "DiffAdd" }

    -- mini.icons -----------------------------------------------------------
    -- Deviation: mini's own default reuses only 4 Diagnostic hues across all
    -- 9 icon groups. osc-colors derives a full chromatic palette, so each
    -- group gets its own distinct hue instead.
    hl.MiniIconsAzure = { fg = pal.cyan.bright }
    hl.MiniIconsBlue = { fg = pal.blue.normal }
    hl.MiniIconsCyan = { fg = pal.cyan.normal }
    hl.MiniIconsGreen = { fg = pal.green.normal }
    hl.MiniIconsGrey = { fg = pal.gray.bright }
    hl.MiniIconsOrange = { fg = pal.orange.normal }
    hl.MiniIconsPurple = { fg = pal.magenta.normal }
    hl.MiniIconsRed = { fg = pal.red.normal }
    hl.MiniIconsYellow = { fg = pal.yellow.normal }

    -- mini.input ----------------------------------------------------------
    hl.MiniInputAdded = { link = "DiagnosticFloatingOk" }
    hl.MiniInputBorder = { link = "FloatBorder" }
    hl.MiniInputCaret = { link = "MiniInputPrompt" }
    hl.MiniInputHide = { link = "DiagnosticFloatingWarn" }
    hl.MiniInputHint = { link = "DiagnosticFloatingHint" }
    hl.MiniInputNormal = { link = "NormalFloat" }
    hl.MiniInputPrompt = { link = "DiagnosticFloatingInfo" }
    hl.MiniInputSpecial = { link = "DiagnosticFloatingWarn" }

    -- mini.cmdline ----------------------------------------------------------
    hl.MiniCmdlinePeekBorder = { link = "FloatBorder" }
    hl.MiniCmdlinePeekLineNr = { link = "DiagnosticSignWarn" }
    hl.MiniCmdlinePeekNormal = { link = "NormalFloat" }
    hl.MiniCmdlinePeekSep = { link = "SignColumn" }
    hl.MiniCmdlinePeekSign = { link = "DiagnosticSignHint" }
    hl.MiniCmdlinePeekTitle = { link = "FloatTitle" }

    -- mini.surround -------------------------------------------------------
    hl.MiniSurround = { link = "IncSearch" }

    return hl
end

return M
