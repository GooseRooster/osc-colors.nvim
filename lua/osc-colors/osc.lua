-- Synthesizes a base16 palette from the host terminal's live colors, queried
-- via OSC 4 (palette) and OSC 10/11 (fg/bg). This is the only "scheme source"
-- osc-colors has: there is no selector, no scheme registry, no dependency on
-- tinty/base16-shell being installed. Whatever the terminal is currently
-- rendering with is what Neovim gets painted with -- including inside
-- devcontainers/remote hosts, where no tinted-theming state is synced in but
-- the OSC round-trip still reaches back through the PTY to the host terminal.
--
-- Kept as real 24-bit hex (not cterm/ANSI names) specifically so
-- termguicolors can stay on: lualine's blends and floating-window shadow
-- depth need real RGB math, which cterm-only mode can't do.

local M = {}

local CACHE_PATH = vim.fn.stdpath("cache") .. "/osc-colors-palette.lua"
local ESC, ST = "\027", "\027\\"
local ANSI_HUE_INDEX = { 1, 2, 3, 4, 5, 6 } -- red, green, yellow, blue, magenta, cyan

local in_flight = false

-- : Color math [[[

local function hex_to_rgb(hex)
    hex = hex:gsub("#", "")
    return tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
end

local function rgb_to_hex(r, g, b)
    return string.format("#%02x%02x%02x", math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5))
end

local function lerp_rgb(hex_a, hex_b, t)
    local r1, g1, b1 = hex_to_rgb(hex_a)
    local r2, g2, b2 = hex_to_rgb(hex_b)
    return rgb_to_hex(r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t)
end

local function luminance(hex)
    local r, g, b = hex_to_rgb(hex)
    return 0.299 * r + 0.587 * g + 0.114 * b
end

-- : ]]]

-- : Cache [[[

-- Load the last successfully queried palette from disk, if any. Used both to
-- paint instantly on startup (before the async query below resolves) and to
-- diff against a freshly queried palette so we can skip a no-op reload.
function M.load_cached()
    local ok, tbl = pcall(dofile, CACHE_PATH)
    if not ok or type(tbl) ~= "table" or not tbl.base00 or not tbl.variant then
        return nil
    end
    return tbl
end

local function write_cache(palette)
    local parts = { "return {\n" }
    table.insert(parts, string.format("  variant = %q,\n", palette.variant))
    for _, key in ipairs({
        "base00",
        "base01",
        "base02",
        "base03",
        "base04",
        "base05",
        "base06",
        "base07",
        "base08",
        "base09",
        "base0A",
        "base0B",
        "base0C",
        "base0D",
        "base0E",
        "base0F",
    }) do
        table.insert(parts, string.format("  %s = %q,\n", key, palette[key]))
    end
    table.insert(parts, "}\n")

    local ok, f = pcall(io.open, CACHE_PATH, "w")
    if ok and f then
        f:write(table.concat(parts))
        f:close()
    end
end

local function palettes_equal(a, b)
    if not a or not b then
        return false
    end
    if a.variant ~= b.variant then
        return false
    end
    for i = 0, 15 do
        local key = string.format("base%02X", i)
        if a[key] ~= b[key] then
            return false
        end
    end
    return true
end

-- : ]]]

-- : OSC query/parse [[[

local function query_osc4(index)
    return ESC .. "]4;" .. index .. ";?" .. ST
end

local function query_osc10()
    return ESC .. "]10;?" .. ST
end

local function query_osc11()
    return ESC .. "]11;?" .. ST
end

local function parse_rgb(body)
    local r, g, b = body:match("rgb:(%x%x)%x%x/(%x%x)%x%x/(%x%x)%x%x")
    if not r then
        return nil
    end
    return string.format("#%s%s%s", r, g, b):lower()
end

-- Returns "osc4"|"osc10"|"osc11", index (osc4 only, else nil), hex-or-nil
local function classify_and_parse(sequence)
    local idx, body = sequence:match("%]4;(%d+);(rgb:%x+/%x+/%x+)")
    if idx then
        return "osc4", tonumber(idx), parse_rgb(body)
    end
    local b10 = sequence:match("%]10;(rgb:%x+/%x+/%x+)")
    if b10 then
        return "osc10", nil, parse_rgb(b10)
    end
    local b11 = sequence:match("%]11;(rgb:%x+/%x+/%x+)")
    if b11 then
        return "osc11", nil, parse_rgb(b11)
    end
    return nil
end

-- : ]]]

-- : Synthesis [[[

local function synthesize(osc10, osc11, osc4)
    local base00 = osc11
    local base07 = osc10
    local base08 = osc4[1]
    local base0B = osc4[2]
    local base0A = osc4[3]
    local base0D = osc4[4]
    local base0E = osc4[5]
    local base0C = osc4[6]

    -- 60% red / 40% yellow -- orange has no ANSI slot of its own
    local base09 = lerp_rgb(base08, base0A, 0.4)
    -- red muted 30% toward background -- brown has no ANSI slot of its own.
    -- This ratio is the most likely spot to want taste-adjusting once seen live.
    local base0F = lerp_rgb(base08, base00, 0.3)

    return {
        variant = (luminance(base00) < 128) and "dark" or "light",
        base00 = base00,
        base01 = lerp_rgb(base00, base07, 1 / 7),
        base02 = lerp_rgb(base00, base07, 2 / 7),
        base03 = lerp_rgb(base00, base07, 3 / 7),
        base04 = lerp_rgb(base00, base07, 4 / 7),
        base05 = lerp_rgb(base00, base07, 5 / 7),
        base06 = lerp_rgb(base00, base07, 6 / 7),
        base07 = base07,
        base08 = base08,
        base09 = base09,
        base0A = base0A,
        base0B = base0B,
        base0C = base0C,
        base0D = base0D,
        base0E = base0E,
        base0F = base0F,
    }
end

-- : ]]]

-- : Async refresh [[[

-- Query the terminal for its live 16-color palette + fg/bg and synthesize a
-- base16 scheme from it. Calls `on_result(palette)` exactly once, where
-- `palette` is the freshly synthesized table if it differs from the last
-- cached one, or nil if the query timed out or nothing changed. Safe to call
-- repeatedly; no-ops (does not call `on_result`) if a query is already in
-- flight.
---@param on_result fun(palette: table|nil)
function M.refresh_async(on_result)
    if in_flight then
        return
    end
    in_flight = true

    local results = { osc10 = nil, osc11 = nil, osc4 = {} }
    local augroup = vim.api.nvim_create_augroup("osc_colors_query", { clear = true })
    local timer = vim.uv.new_timer()
    local finished = false

    local function have_all()
        if not (results.osc10 and results.osc11) then
            return false
        end
        for _, idx in ipairs(ANSI_HUE_INDEX) do
            if not results.osc4[idx] then
                return false
            end
        end
        return true
    end

    local function finish(success)
        if finished then
            return
        end
        finished = true
        in_flight = false
        pcall(vim.api.nvim_del_augroup_by_id, augroup)
        if timer and not timer:is_closing() then
            timer:stop()
            timer:close()
        end

        if not success then
            on_result(nil)
            return
        end

        local palette = synthesize(results.osc10, results.osc11, results.osc4)
        local cached = M.load_cached()
        if palettes_equal(palette, cached) then
            on_result(nil)
            return
        end

        write_cache(palette)
        on_result(palette)
    end

    vim.api.nvim_create_autocmd("TermResponse", {
        group = augroup,
        callback = function(ev)
            local sequence = ev.data and ev.data.sequence
            if not sequence then
                return
            end
            local kind, idx, hex = classify_and_parse(sequence)
            if not kind or not hex then
                return
            end
            if kind == "osc10" then
                results.osc10 = hex
            elseif kind == "osc11" then
                results.osc11 = hex
            elseif kind == "osc4" then
                results.osc4[idx] = hex
            end
            if have_all() then
                vim.schedule(function()
                    finish(true)
                end)
            end
        end,
    })

    timer:start(
        200,
        0,
        vim.schedule_wrap(function()
            finish(false)
        end)
    )

    vim.api.nvim_ui_send(query_osc10())
    vim.api.nvim_ui_send(query_osc11())
    for _, idx in ipairs(ANSI_HUE_INDEX) do
        vim.api.nvim_ui_send(query_osc4(idx))
    end
end

-- : ]]]

return M
