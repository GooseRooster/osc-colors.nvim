-- Soul extraction: distill a palette's "soul" -- a low-dimensional
-- descriptor of what a terminal theme actually *is* -- from the queried
-- anchors.
--
-- The descriptor drives role-based highlight mapping (roles.lua): what hue
-- family the scheme orbits, how tightly (hue concentration), how saturated
-- it is (chroma envelope), how much lightness room exists (bg/fg envelope),
-- and whether it's effectively achromatic. Everything downstream is a pure
-- function of this descriptor, so soul mapping is deterministic and
-- snapshot-testable.

local oklch = require("osc-colors.oklch")
local utils = require("osc-colors.utils")

local M = {}

-- Below this OKLCH chroma, a color is visually gray. If *every* anchor is
-- under it, the scheme is achromatic: hue is meaningless and role mapping
-- degrades to pure lightness/chroma structure (a structured grayscale
-- scheme -- a feature, not an error state).
M.ACHROMATIC_CHROMA = 0.03

-- The ANSI hue anchors, in OSC 4 query order: red, green, yellow, blue,
-- magenta, cyan.
local HUE_SLOTS = { "base08", "base0B", "base0A", "base0D", "base0E", "base0C" }

-- LuaJIT's math.atan takes a single argument (no atan2 form).
local function atan2(y, x)
    if x > 0 then
        return math.atan(y / x)
    elseif x < 0 and y >= 0 then
        return math.atan(y / x) + math.pi
    elseif x < 0 then
        return math.atan(y / x) - math.pi
    elseif y > 0 then
        return math.pi / 2
    elseif y < 0 then
        return -math.pi / 2
    end
    return 0
end

local function hue_distance(a, b)
    local d = math.abs(a - b) % 360
    if d > 180 then
        d = 360 - d
    end
    return d
end

---Extract the soul descriptor from a flat-or-normalized palette.
---@param palette osc-colors.Palette
---@return table soul
function M.extract(palette)
    local anchors = {}
    for _, slot in ipairs(HUE_SLOTS) do
        local hex = palette[slot]
        if not utils.is_hex(hex) and palette.palette then
            -- tree-only palettes: fall back through the canonical paths
            local path = ({
                base08 = "palette.red.normal",
                base0B = "palette.green.normal",
                base0A = "palette.yellow.normal",
                base0D = "palette.blue.normal",
                base0E = "palette.magenta.normal",
                base0C = "palette.cyan.normal",
            })[slot]
            hex = path and utils.lookup(palette, path) or nil
        end
        if utils.is_hex(hex) then
            local L, C, H = oklch.hex_to_oklch(hex)
            table.insert(anchors, { hex = hex, L = L, C = C, H = H, slot = slot })
        end
    end

    local bg = palette.base00 or (palette.ui and palette.ui.global.background.normal)
    local fg = palette.base07 or (palette.ui and palette.ui.global.foreground.normal)
    local bg_L = bg and select(1, oklch.hex_to_oklch(bg)) or 0
    local fg_L = fg and select(1, oklch.hex_to_oklch(fg)) or 1

    -- Chroma-weighted circular hue statistics. A naive mean of hues on a
    -- ring is nonsense (the mean of 350deg and 10deg is not 180deg), and
    -- chroma weighting lets near-gray anchors stay out of the vote.
    local sum_sin, sum_cos, sum_c = 0, 0, 0
    local chromas = {}
    for _, a in ipairs(anchors) do
        local h = math.rad(a.H)
        sum_sin = sum_sin + a.C * math.sin(h)
        sum_cos = sum_cos + a.C * math.cos(h)
        sum_c = sum_c + a.C
        table.insert(chromas, a.C)
    end

    local hue_mean, hue_kappa = 0, 0
    if sum_c > 1e-6 then
        hue_mean = math.deg(atan2(sum_sin, sum_cos)) % 360
        hue_kappa = math.sqrt(sum_sin ^ 2 + sum_cos ^ 2) / sum_c
    end

    table.sort(chromas)
    local chroma_median = chromas[math.ceil(#chromas / 2)] or 0
    local chroma_max = chromas[#chromas] or 0

    -- Warm/cool bias: where the circular mass sits relative to the
    -- warm pole (yellow-orange, ~60deg). +1 = warm scheme, -1 = cool.
    local warm_bias = hue_kappa * math.cos(math.rad(hue_mean - 60))

    return {
        variant = palette.variant or (bg_L < fg_L and "dark" or "light"),
        bg = bg,
        fg = fg,
        bg_L = bg_L,
        fg_L = fg_L,
        anchors = anchors,
        hue_mean = hue_mean,
        hue_kappa = hue_kappa,
        warm_bias = warm_bias,
        chroma_median = chroma_median,
        chroma_max = chroma_max,
        achromatic = chroma_max < M.ACHROMATIC_CHROMA,
    }
end

---Anchor (or synthesize) a hue inside a conventional sector, preferring the
---scheme's own accent when it already lives there.
---@param soul table from extract()
---@param slot string base slot of the preferred anchor (e.g. "base08" for error)
---@param sector number[] { lo, hi } degrees, inclusive
---@return number hue, number chroma of the preferred anchor (0 if none)
function M.sector_hue(soul, slot, sector)
    local pref_hue, pref_chroma = nil, 0
    for _, a in ipairs(soul.anchors) do
        if a.slot == slot then
            pref_hue, pref_chroma = a.H, a.C
        end
    end
    local lo, hi = sector[1], sector[2]
    if pref_hue == nil then
        -- no anchor to prefer: sit at the sector edge nearest the soul's
        -- dominant hue, so even semantic colors lean "in family"
        local mid = (lo + hi) / 2
        return mid, 0
    end
    if pref_hue >= lo and pref_hue <= hi then
        return pref_hue, pref_chroma
    end
    -- anchor is off-sector (theme labeled it oddly): clamp to nearest edge
    if hue_distance(pref_hue, lo) < hue_distance(pref_hue, hi) then
        return lo, pref_chroma
    end
    return hi, pref_chroma
end

return M
