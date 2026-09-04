-- Synthesizes a base16 palette from the host terminal's live colors, queried
-- via OSC 4 (palette) and OSC 10/11 (fg/bg), plus a terminal capability tier
-- from an XTGETTCAP probe (see capability.lua). This is the only "scheme
-- source" osc-colors has: there is no selector, no scheme registry, no
-- dependency on tinty/base16-shell being installed. Whatever the terminal is
-- currently rendering with is what Neovim gets painted with -- including
-- inside devcontainers/remote hosts, where no tinted-theming state is synced
-- in but the OSC round-trip still reaches back through the PTY to the host
-- terminal.
--
-- Kept as real 24-bit hex (not cterm/ANSI names) specifically so
-- termguicolors can stay on: lualine's blends and floating-window shadow
-- depth need real RGB math, which cterm-only mode can't do.

local M = {}

local capability = require("osc-colors.capability")

local CACHE_PATH = vim.fn.stdpath("cache") .. "/osc-colors-palette.lua"
local ESC, ST = "\027", "\027\\"
local ANSI_HUE_INDEX = { 1, 2, 3, 4, 5, 6 } -- red, green, yellow, blue, magenta, cyan
local CUBE_FIRST, CUBE_LAST = 16, 255
local DEFAULT_TIMEOUT_MS = 200

local in_flight = false
local round_seq = 0

-- Opt-in diagnostic logging for live-refresh issues (e.g. a terminal that
-- answers the OSC queries once at startup but goes silent on later manual
-- refreshes). Off by default and zero-cost when unset; set
-- OSC_COLORS_DEBUG=1 and check :messages to see exactly which replies (if
-- any) arrive for a given refresh round, and whether `finish()` completes.
local function dbg(fmt, ...)
    if vim.env.OSC_COLORS_DEBUG then
        vim.notify(string.format("[osc-colors] " .. fmt, ...), vim.log.levels.DEBUG)
    end
end

-- : Color math [[[
--
-- (RGB-level helpers only; perceptual color math lives in oklch.lua.)

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
--
-- Schema v2 adds `version` and `capability` (the probed tier + evidence).
-- v1 files (flat base16, no version field) still load; they simply carry an
-- "unknown" tier until the next successful live query upgrades the cache.

-- Load the last successfully queried palette from disk, if any. Used both to
-- paint instantly on startup (before the async query below resolves) and to
-- diff against a freshly queried palette so we can skip a no-op reload.
---@return osc-colors.Palette|nil
function M.load_cached()
    local ok, tbl = pcall(dofile, CACHE_PATH)
    if not ok or type(tbl) ~= "table" or not tbl.base00 or not tbl.variant then
        return nil
    end
    if type(tbl.capability) ~= "table" or not tbl.capability.tier then
        tbl.capability = { tier = "unknown", evidence = { reason = "legacy cache (pre-capability probe)" } }
    end
    if type(tbl.cube) ~= "table" then
        tbl.cube = nil
    end
    return tbl
end

local BASE_KEYS = {
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
}

local function write_cache(palette)
    local parts = { "return {\n" }
    table.insert(parts, "  version = 2,\n")
    table.insert(parts, string.format("  variant = %q,\n", palette.variant))
    for _, key in ipairs(BASE_KEYS) do
        table.insert(parts, string.format("  %s = %q,\n", key, palette[key]))
    end
    table.insert(parts, string.format("  capability = { tier = %q },\n", palette.capability.tier))
    if palette.cube then
        table.insert(parts, "  cube = {\n")
        for i = CUBE_FIRST, CUBE_LAST do
            if palette.cube[i] then
                table.insert(parts, string.format("    [%d] = %q,\n", i, palette.cube[i]))
            end
        end
        table.insert(parts, "  },\n")
    end
    table.insert(parts, "}\n")

    local ok, f = pcall(io.open, CACHE_PATH, "w")
    if ok and f then
        f:write(table.concat(parts))
        f:close()
    end
end

-- Evidence (which channel happened to answer this round) is deliberately
-- excluded: only the tier affects rendering, and a same-palette repaint
-- triggered by evidence noise would be pointless flicker.
local function base_equal(a, b)
    if not a or not b then
        return false
    end
    if a.variant ~= b.variant then
        return false
    end
    local a_tier = a.capability and a.capability.tier or "unknown"
    local b_tier = b.capability and b.capability.tier or "unknown"
    if a_tier ~= b_tier then
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

-- The cube is enrichment, not identity: a cube-less fresh palette equals a
-- cube-carrying cache when the colors match (so cube-less refresh rounds
-- never needlessly repaint, and a cached cube survives untouched). When a
-- fresh palette *does* carry a cube, the cached cube must match.
--
-- Trade-off: a terminal-side cube remap with unchanged base16 colors won't
-- trigger a repaint for cache-equal rounds; that's vanishingly rare next to
-- palette remaps, which do re-query the cube (see on_palette_complete).
local function palettes_equal(a, b)
    if not base_equal(a, b) then
        return false
    end
    if a.cube == nil then
        return true
    end
    if not b.cube then
        return false
    end
    for i = CUBE_FIRST, CUBE_LAST do
        if a.cube[i] ~= b.cube[i] then
            return false
        end
    end
    return true
end

-- : ]]]

-- : OSC/DCS query/parse [[[
--
-- Reply format notes:
--   * Color specs follow XParseColor: `rgb:` (or `rgba:`, alpha ignored)
--     with 1-4 hex digits *per channel*, scaled to their bit width, plus
--     the `#<hex>` form. Terminals vary in which width they answer with
--     (xterm replies 16-bit channels, plenty reply 8-bit), so everything
--     1-4 digits wide must parse or a whole palette silently times out.
--   * Replies may terminate with ST (ESC \) or BEL.
--   * OSC 4 replies may carry several index;spec pairs in one sequence.

local function query_osc4(index)
    return ESC .. "]4;" .. index .. ";?" .. ST
end

local function query_osc10()
    return ESC .. "]10;?" .. ST
end

local function query_osc11()
    return ESC .. "]11;?" .. ST
end

-- Convert one channel of `digits` hex digits to 0-255. For 12/16-bit
-- channels the high byte is the significant one under both reply
-- conventions seen in the wild -- terminals either scale 8-bit values up
-- (0xff00) or zero-pad them (0xff00) -- so truncation is exact where
-- proportional scaling would be off by one (and matches the original
-- parser's behavior).
local function scale_channel(digits)
    local n = #digits
    local v = tonumber(digits, 16)
    if not v then
        return nil
    end
    if n == 1 then
        return math.floor(v * 255 / 15 + 0.5)
    end
    if n == 2 then
        return v
    end
    return math.floor(v / (16 ^ (n - 2)))
end

local function parse_rgb(body)
    local chans = {}
    if body:sub(1, 1) == "#" then
        local hex = body:sub(2)
        if #hex < 3 or #hex % 3 ~= 0 then
            return nil
        end
        local w = #hex / 3
        for i = 0, 2 do
            table.insert(chans, hex:sub(i * w + 1, i * w + w))
        end
    else
        local rest = body:match("^rgba?:([%x/]+)$")
        if not rest then
            return nil
        end
        for part in rest:gmatch("[%x]+") do
            table.insert(chans, part)
        end
    end
    if #chans ~= 3 and #chans ~= 4 then
        return nil
    end
    local r, g, b = scale_channel(chans[1]), scale_channel(chans[2]), scale_channel(chans[3])
    if not (r and g and b) then
        return nil
    end
    return string.format("#%02x%02x%02x", r, g, b)
end

-- Classify one TermResponse sequence into a list of events:
--   { kind = "osc4", idx = N, hex = "#rrggbb" } (possibly several per reply)
--   { kind = "osc10"|"osc11", hex = "#rrggbb" }
--   { kind = "xtgettcap", ... }  (capability.parse_dcs shape)
-- Unknown sequences yield an empty list and are ignored by the collector.
local function classify_and_parse(sequence)
    local events = {}

    -- OSC 4: the body after `]4;` is one or more `index;spec` pairs joined
    -- by `;` (xterm answers one pair per reply; some terminals batch).
    local body4 = sequence:match("%]4;([^%c]*)")
    if body4 then
        local fields = {}
        for field in body4:gmatch("[^;]+") do
            table.insert(fields, field)
        end
        local i = 1
        while i + 1 <= #fields do
            local idx = tonumber(fields[i])
            local hex = parse_rgb(fields[i + 1])
            if idx and hex then
                table.insert(events, { kind = "osc4", idx = idx, hex = hex })
            end
            i = i + 2
        end
    end

    local body10 = sequence:match("%]10;([^%c]*)")
    if body10 then
        local hex = parse_rgb(body10)
        if hex then
            table.insert(events, { kind = "osc10", hex = hex })
        end
    end

    local body11 = sequence:match("%]11;([^%c]*)")
    if body11 then
        local hex = parse_rgb(body11)
        if hex then
            table.insert(events, { kind = "osc11", hex = hex })
        end
    end

    local dcs = capability.parse_dcs(sequence)
    if dcs then
        table.insert(events, { kind = "xtgettcap", dcs = dcs })
    end

    return events
end

-- : ]]]

-- : Synthesis [[[
--
-- In addition to the base16 slots, the palette carries the probed capability
-- tier so consumers (init.lua's termguicolors decision, the soul/cube
-- pipeline, health checks) know what the terminal can actually render.

local function synthesize(osc10, osc11, osc4, cap)
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
        capability = cap,
    }
end

-- : ]]]

-- : Async refresh [[[
--
-- Query the terminal for its live 16-color palette + fg/bg, probe its color
-- capability, and synthesize a base16 scheme + capability tier from the
-- answers. The XTGETTCAP probe is sent *first* and the OSC queries after,
-- in a single batch: terminals answer queries in order, so by the time the
-- OSC replies complete the round, any XTGETTCAP answer has already arrived
-- -- without ever extending the round's latency for terminals that stay
-- silent on DCS.
--
-- The round runs in two phases:
--   1. "palette": OSC 10/11 + ANSI 1-6, plus the XTGETTCAP probe. Completes
--      as soon as all replies arrive.
--   2. "cube" (lazy, optional): OSC 4 for indices 16-255 -- the terminal's
--      *actual* 256-color cube, which generic RGB->256 converters can't
--      know (terminals and themes routinely remap cube entries). Only runs
--      when `opts.cube(tier)` says the consumer needs it; skipped entirely
--      when the cached palette already carries one. A partial cube on
--      timeout still yields a complete palette.
--
-- Calls `on_result(palette)` exactly once, where `palette` is the freshly
-- synthesized table if it differs from the last cached one, or nil if the
-- query timed out or nothing changed. Safe to call repeatedly; no-ops (does
-- not call `on_result`) if a query is already in flight.
---@param on_result fun(palette: table|nil)
---@param opts? { timeout_ms?: number, cube?: fun(tier: string): boolean }
function M.refresh_async(on_result, opts)
    if in_flight then
        dbg("refresh_async called while already in flight -- ignoring")
        return
    end
    in_flight = true
    round_seq = round_seq + 1
    local my_round = round_seq
    opts = opts or {}
    local timeout_ms = opts.timeout_ms or DEFAULT_TIMEOUT_MS
    local t0 = vim.uv.hrtime()
    dbg("round %d: refresh_async start", my_round)

    local results = { osc10 = nil, osc11 = nil, osc4 = {} }
    local xtgettcap = { caps = {}, answered = false }
    local augroup = vim.api.nvim_create_augroup("osc_colors_query", { clear = true })
    local timer = vim.uv.new_timer()
    local finished = false
    local phase = "palette"
    local palette = nil --[[@type osc-colors.Palette?]]

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

    local function cube_complete()
        for i = CUBE_FIRST, CUBE_LAST do
            if not results.osc4[i] then
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
        dbg(
            "round %d: finish(success=%s) phase=%s at %dms",
            my_round,
            tostring(success),
            phase,
            (vim.uv.hrtime() - t0) / 1e6
        )
        pcall(vim.api.nvim_del_augroup_by_id, augroup)
        -- pcall'd so a throw here (e.g. an already-closing timer handle)
        -- can never abandon the on_result(...) calls below.
        pcall(function()
            if timer and not timer:is_closing() then
                timer:stop()
                timer:close()
            end
        end)

        -- A cube-phase timeout still carries a complete palette; only the
        -- cube is partial.
        if phase == "cube" then
            success = true
            local cube = {}
            for i = CUBE_FIRST, CUBE_LAST do
                if results.osc4[i] then
                    cube[i] = results.osc4[i]
                end
            end
            if next(cube) then
                palette.cube = cube
            end
        end

        if not success then
            dbg("round %d: on_result(nil) [timeout]", my_round)
            on_result(nil)
            return
        end

        local cached = M.load_cached()
        if palettes_equal(palette, cached) then
            dbg("round %d: on_result(nil) [unchanged]", my_round)
            on_result(nil)
            return
        end

        write_cache(palette)
        dbg("round %d: on_result(palette)", my_round)
        on_result(palette)
    end

    -- Palette phase complete: classify capability, synthesize, and either
    -- extend into the cube phase or hand the palette to finish().
    local function on_palette_complete()
        if palette then
            return
        end
        local cap = capability.classify(vim.tbl_extend("force", capability.env_signals(), {
            xtgettcap = next(xtgettcap.caps) and xtgettcap.caps or nil,
            xtgettcap_answered = xtgettcap.answered,
        }))
        dbg("round %d: capability tier=%s (%s)", my_round, cap.tier, cap.evidence.reason)

        palette = synthesize(results.osc10, results.osc11, results.osc4, cap)

        local want_cube = type(opts.cube) == "function" and opts.cube(cap.tier) == true
        if not want_cube then
            finish(true)
            return
        end

        -- Skip the 240-query cube round when nothing about the palette
        -- changed and the cache already carries a cube.
        local cached = M.load_cached()
        if base_equal(palette, cached) and cached.cube then
            finish(true)
            return
        end

        phase = "cube"
        dbg("round %d: querying 256-color cube (slots %d-%d)", my_round, CUBE_FIRST, CUBE_LAST)
        pcall(function()
            if not timer:is_closing() then
                timer:stop()
                timer:start(
                    timeout_ms,
                    0,
                    vim.schedule_wrap(function()
                        finish(false)
                    end)
                )
            end
        end)
        local batch = {}
        for i = CUBE_FIRST, CUBE_LAST do
            table.insert(batch, query_osc4(i))
        end
        vim.api.nvim_ui_send(table.concat(batch))

        -- Replies that raced ahead of this transition (possible when the
        -- terminal answers between the palette-phase schedule and this
        -- callback) may already complete the cube.
        if cube_complete() then
            vim.schedule(function()
                finish(true)
            end)
        end
    end

    vim.api.nvim_create_autocmd("TermResponse", {
        group = augroup,
        callback = function(ev)
            local sequence = ev.data and ev.data.sequence
            if not sequence then
                return
            end
            local events = classify_and_parse(sequence)
            if #events == 0 then
                return
            end
            for _, e in ipairs(events) do
                if e.kind == "osc10" then
                    results.osc10 = e.hex
                elseif e.kind == "osc11" then
                    results.osc11 = e.hex
                elseif e.kind == "osc4" then
                    results.osc4[e.idx] = e.hex
                elseif e.kind == "xtgettcap" then
                    capability.absorb(xtgettcap, e.dcs)
                end
            end
            dbg(
                "round %d: TermResponse raw=%q events=%d at %dms",
                my_round,
                sequence,
                #events,
                (vim.uv.hrtime() - t0) / 1e6
            )
            if phase == "palette" and have_all() then
                vim.schedule(on_palette_complete)
            elseif phase == "cube" and cube_complete() then
                vim.schedule(function()
                    finish(true)
                end)
            end
        end,
    })

    timer:start(
        timeout_ms,
        0,
        vim.schedule_wrap(function()
            finish(false)
        end)
    )

    -- One batched write: XTGETTCAP first (see comment above), then the
    -- OSC queries.
    local batch = { capability.probe_batch(), query_osc10(), query_osc11() }
    for _, idx in ipairs(ANSI_HUE_INDEX) do
        table.insert(batch, query_osc4(idx))
    end
    dbg("round %d: sending XTGETTCAP probe + 8 OSC queries", my_round)
    vim.api.nvim_ui_send(table.concat(batch))
end

-- : ]]]

return M
