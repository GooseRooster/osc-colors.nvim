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
        vim.health.ok(string.format("disk cache present (variant: %s) -- used to paint instantly on next startup", cached.variant))
    else
        vim.health.warn(
            "no disk cache yet -- first-ever startup in a terminal that never answers OSC 4/10/11 will leave Neovim's default colors untouched"
        )
    end

    if vim.env.TMUX then
        vim.health.warn(
            "running inside tmux -- OSC 4/10/11 queries only reach the outer terminal if tmux's `allow-passthrough` (and, for OSC 10/11 replies, a modern-enough tmux) is configured; if colors never update, check that first"
        )
    else
        vim.health.info("not running inside tmux")
    end

    local term = vim.env.TERM or ""
    if term:match("256color") or term:match("direct") or term == "xterm-ghostty" then
        vim.health.ok(string.format("$TERM=%s looks truecolor-capable", term))
    else
        vim.health.info(string.format("$TERM=%s -- if this terminal doesn't support truecolor/OSC queries, osc-colors has nothing to work with", term))
    end

    vim.health.info(string.format("cache file: %s", vim.fn.stdpath("cache") .. "/osc-colors-palette.lua"))
end

return M
