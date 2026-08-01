local M = {}

function M.check()
    vim.health.start("osc-colors")

    if vim.o.termguicolors then
        vim.health.ok("'termguicolors' is enabled")
    else
        vim.health.warn("'termguicolors' is disabled -- colors will be degraded to cterm approximations")
    end

    local plugin = require("osc-colors")
    local osc = require("osc-colors.osc")

    local palette = plugin.get_palette()
    if palette then
        vim.health.ok(string.format("a palette is currently applied (variant: %s)", palette.variant))
    else
        vim.health.warn("no palette has been applied yet -- did setup() run, and has a query ever succeeded?")
    end

    local cached = osc.load_cached()
    if cached then
        vim.health.ok(
            string.format("disk cache present (variant: %s) -- paints instantly on next startup", cached.variant)
        )
    else
        vim.health.warn("no disk cache yet -- a terminal that never answers OSC 4/10/11 leaves colors untouched")
    end

    if vim.env.TMUX then
        vim.health.warn(
            "running inside tmux -- OSC replies only reach Neovim if `allow-passthrough` is set "
                .. "(and tmux is new enough to relay OSC 10/11 replies); check that first if colors never update"
        )
    else
        vim.health.info("not running inside tmux")
    end

    local term = vim.env.TERM or ""
    if term:match("256color") or term:match("direct") or term == "xterm-ghostty" then
        vim.health.ok(string.format("$TERM=%s looks truecolor-capable", term))
    else
        vim.health.info(
            string.format(
                "$TERM=%s -- if this doesn't support truecolor/OSC, osc-colors has nothing to work with",
                term
            )
        )
    end

    if vim.fn.has("nvim-0.11") ~= 1 then
        vim.health.info(
            "Neovim <0.11 has a known TermResponse/TermRequest re-entrancy edge case "
                .. "(neovim/neovim#32706) that can silently drop rapid terminal replies -- "
                .. "if a live refresh works once at startup but silently stops repainting on later "
                .. "manual refreshes, upgrading Neovim is worth trying"
        )
    end

    vim.health.info(string.format("cache file: %s", vim.fn.stdpath("cache") .. "/osc-colors-palette.lua"))
end

return M
