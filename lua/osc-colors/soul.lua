-- Soul extraction: distill a palette's "soul" -- what a terminal theme
-- actually *is* -- from the queried anchors.
--
-- A terminal palette must cover all six ANSI hue families, so any single
-- "average hue" of it is mostly noise. What carries a scheme's character is
-- the designer's per-color choices: which hues they made vivid and which
-- they muted, which ones they moved away from the stock ANSI positions,
-- where their strong colors cluster. The soul is therefore a set of color
-- *families* (the scheme's own colors, with their bright variants as
-- shades), each scored by *salience* -- how much the designer invested in
-- it. Role mapping (roles.lua) assigns highlight roles to these families;
-- everything downstream is a pure function of this descriptor, so soul
-- mapping stays deterministic and snapshot-testable.

local oklch = require("osc-colors.oklch")
local utils = require("osc-colors.utils")

local M = {}

-- Below this OKLCH chroma, a color is visually gray and can't anchor a
-- hue family. If *no* family survives, the scheme is achromatic: role
-- mapping degrades to pure lightness + style structure (a structured
-- grayscale scheme -- a feature, not an error state).
M.ACHROMATIC_CHROMA = 0.03

-- A bright variant is a *shade* of its normal's family when it's the same
-- hue (within SHADE_HUE_TIGHT), or a nearby hue (within SHADE_HUE) that is
-- clearly a lightness step. Otherwise the designer gave it its own color
-- (solarized's bright red is its orange at the same lightness, nord's
-- bright cyan is a separate frost tone) and it becomes a family of its own.
local SHADE_HUE_TIGHT = 8
local SHADE_HUE = 25
local SHADE_MIN_DL = 0.04

-- Families closer than this (OKLab distance) read as the same color; the
-- less vivid one is folded into the other.
local MERGE_DELTA_E = 0.05

-- Salience blend. Vividness dominates (a designer's saturated colors are
-- the ones they want seen); cohesion rewards colors near the scheme's
-- other strong colors (the "family" the palette orbits); shift rewards
-- hues deliberately moved off the stock ANSI positions.
local SALIENCE_VIVID = 0.6
local SALIENCE_COHESION = 0.25
local SALIENCE_SHIFT = 0.15
local COHESION_SPREAD = 40 -- degrees, gaussian width of the cohesion kernel
local SHIFT_FULL = 60 -- degrees off-canon that count as a full shift

-- The six ANSI hue families: base slot, base24 bright slot, tree fallback,
-- and the stock color whose OKLCH hue is the family's "canonical" position.
local FAMILY_DEFS = {
    { name = "red", slot = "base08", bright_slot = "base12", tree = "palette.red.normal", stock = "#ff0000" },
    { name = "green", slot = "base0B", bright_slot = "base14", tree = "palette.green.normal", stock = "#00ff00" },
    { name = "yellow", slot = "base0A", bright_slot = "base13", tree = "palette.yellow.normal", stock = "#ffff00" },
    { name = "blue", slot = "base0D", bright_slot = "base16", tree = "palette.blue.normal", stock = "#0000ff" },
    { name = "magenta", slot = "base0E", bright_slot = "base17", tree = "palette.magenta.normal", stock = "#ff00ff" },
    { name = "cyan", slot = "base0C", bright_slot = "base15", tree = "palette.cyan.normal", stock = "#00ffff" },
}

for _, def in ipairs(FAMILY_DEFS) do
    def.canon = select(3, oklch.hex_to_oklch(def.stock))
end

local function hue_distance(a, b)
    local d = math.abs(a - b) % 360
    if d > 180 then
        d = 360 - d
    end
    return d
end
M.hue_distance = hue_distance

local function color(hex)
    if not utils.is_hex(hex) then
        return nil
    end
    local L, C, H = oklch.hex_to_oklch(hex)
    return { hex = hex, L = L, C = C, H = H }
end

local function new_family(name, base, def, order)
    local rel = base.C / math.max(oklch.max_chroma(base.L, base.H), 1e-6)
    return {
        name = name,
        aliases = { name },
        hex = base.hex,
        L = base.L,
        C = base.C,
        H = base.H,
        rel = math.min(rel, 1),
        canon = def.canon,
        order = order,
    }
end

-- Fold perceptually identical families together, keeping the more vivid
-- one (ties: definition order). Deterministic: a single ordered pass.
local function merge_families(families)
    local kept = {}
    for _, f in ipairs(families) do
        local absorbed = false
        for i, k in ipairs(kept) do
            if oklch.delta_e(f.hex, k.hex) < MERGE_DELTA_E then
                local survivor, loser = k, f
                if f.rel > k.rel then
                    survivor, loser = f, k
                    survivor.order = loser.order
                    kept[i] = survivor
                end
                for _, alias in ipairs(loser.aliases) do
                    table.insert(survivor.aliases, alias)
                end
                survivor.shade = survivor.shade or loser.shade
                absorbed = true
                break
            end
        end
        if not absorbed then
            table.insert(kept, f)
        end
    end
    return kept
end

local function score_salience(families)
    local max_rel, max_cohesion = 1e-6, 1e-6
    for _, f in ipairs(families) do
        max_rel = math.max(max_rel, f.rel)
    end
    for _, f in ipairs(families) do
        local cohesion = 0
        for _, g in ipairs(families) do
            if g ~= f then
                cohesion = cohesion + g.rel * math.exp(-(hue_distance(f.H, g.H) / COHESION_SPREAD) ^ 2)
            end
        end
        f.cohesion = cohesion
        max_cohesion = math.max(max_cohesion, cohesion)
    end
    for _, f in ipairs(families) do
        f.vivid = f.rel / max_rel
        f.shift = math.min(hue_distance(f.H, f.canon) / SHIFT_FULL, 1)
        f.salience = SALIENCE_VIVID * f.vivid
            + SALIENCE_COHESION * (f.cohesion / max_cohesion)
            + SALIENCE_SHIFT * f.shift
    end
end

---Extract the soul descriptor from a flat-or-normalized palette.
---@param palette osc-colors.Palette
---@return osc-colors.Soul soul
function M.extract(palette)
    local anchors = {}
    local families = {}
    local brights = type(palette.brights) == "table" and palette.brights or {}

    for _, def in ipairs(FAMILY_DEFS) do
        local hex = palette[def.slot]
        if not utils.is_hex(hex) and palette.palette then
            hex = utils.lookup(palette, def.tree)
        end
        local normal = color(hex)
        local bright = color(brights[def.name] or palette[def.bright_slot])
        if bright and normal and bright.hex == normal.hex then
            bright = nil
        end

        if normal then
            table.insert(anchors, {
                name = def.name,
                slot = def.slot,
                hex = normal.hex,
                L = normal.L,
                C = normal.C,
                H = normal.H,
            })
        end

        local fam = nil
        if normal and normal.C >= M.ACHROMATIC_CHROMA then
            fam = new_family(def.name, normal, def, #families + 1)
            table.insert(families, fam)
        end
        if bright and bright.C >= M.ACHROMATIC_CHROMA then
            local dh = fam and hue_distance(bright.H, fam.H)
            local is_shade = fam
                and (dh <= SHADE_HUE_TIGHT or (dh <= SHADE_HUE and math.abs(bright.L - fam.L) >= SHADE_MIN_DL))
            if is_shade then
                fam.shade = bright
            elseif fam then
                table.insert(families, new_family("bright_" .. def.name, bright, def, #families + 1))
            else
                -- the normal is gray but the bright carries the hue
                table.insert(families, new_family(def.name, bright, def, #families + 1))
            end
        end
    end

    families = merge_families(families)
    score_salience(families)

    local ranked = {}
    for _, f in ipairs(families) do
        table.insert(ranked, f)
    end
    table.sort(ranked, function(a, b)
        if a.salience ~= b.salience then
            return a.salience > b.salience
        end
        return a.order < b.order
    end)

    local chromas = {}
    for _, f in ipairs(families) do
        table.insert(chromas, f.C)
    end
    table.sort(chromas)

    local bg = palette.base00 or (palette.ui and palette.ui.global.background.normal)
    local fg = palette.base07 or (palette.ui and palette.ui.global.foreground.normal)
    local bg_L = bg and select(1, oklch.hex_to_oklch(bg)) or 0
    local fg_L = fg and select(1, oklch.hex_to_oklch(fg)) or 1

    local dominant = ranked[1]
    return {
        variant = palette.variant or (bg_L < fg_L and "dark" or "light"),
        bg = bg,
        fg = fg,
        bg_L = bg_L,
        fg_L = fg_L,
        anchors = anchors,
        families = families,
        ranked = ranked,
        dominant = dominant,
        dominant_hue = dominant and dominant.H or 0,
        chroma_median = chromas[math.ceil(#chromas / 2)] or 0,
        chroma_max = chromas[#chromas] or 0,
        achromatic = #families == 0,
    }
end

---Find a family by name (its own name or any name folded into it).
---@param soul osc-colors.Soul
---@param name string
---@return osc-colors.SoulFamily|nil
function M.family(soul, name)
    for _, f in ipairs(soul.families) do
        for _, alias in ipairs(f.aliases) do
            if alias == name then
                return f
            end
        end
    end
    return nil
end

local function in_sector(h, sector)
    return h >= sector[1] and h <= sector[2]
end

local function clamp_to_sector(h, sector)
    if in_sector(h, sector) then
        return h
    end
    if hue_distance(h, sector[1]) < hue_distance(h, sector[2]) then
        return sector[1]
    end
    return sector[2]
end

local function sector_distance(h, sector)
    if in_sector(h, sector) then
        return 0
    end
    return math.min(hue_distance(h, sector[1]), hue_distance(h, sector[2]))
end

-- A source color this close (degrees) outside its sector is still "the
-- scheme's red", just nudged in -- better than borrowing another family.
local CLAMP_REACH = 30

---Pick the scheme's own color for a semantic role constrained to a
---conventional hue sector (errors stay red-ish whatever the soul). In
---order of preference:
---  1. the source family, when it already lives in the sector
---  2. the source family clamped to the nearest sector edge, when it sits
---     just outside (within CLAMP_REACH)
---  3. the most salient family that lives in the sector (not yet `taken`)
---  4. the source family, clamped
---  5. the family nearest the sector, clamped
---Lightness and chroma always come from the chosen family.
---@param soul osc-colors.Soul
---@param source string family name to prefer
---@param sector number[] { lo, hi } degrees, inclusive
---@param taken? table<osc-colors.SoulFamily, boolean> families already claimed by other semantics
---@return { L: number, C: number, H: number, family: osc-colors.SoulFamily }|nil
function M.sector_color(soul, source, sector, taken)
    taken = taken or {}
    local src = M.family(soul, source)
    if src and in_sector(src.H, sector) then
        return { L = src.L, C = src.C, H = src.H, family = src }
    end
    if src and sector_distance(src.H, sector) <= CLAMP_REACH then
        return { L = src.L, C = src.C, H = clamp_to_sector(src.H, sector), family = src }
    end
    for _, f in ipairs(soul.ranked) do
        if not taken[f] and in_sector(f.H, sector) then
            return { L = f.L, C = f.C, H = f.H, family = f }
        end
    end
    if src then
        return { L = src.L, C = src.C, H = clamp_to_sector(src.H, sector), family = src }
    end
    local nearest, nearest_d = nil, math.huge
    for _, f in ipairs(soul.ranked) do
        local d = sector_distance(f.H, sector)
        if d < nearest_d then
            nearest, nearest_d = f, d
        end
    end
    if nearest then
        return { L = nearest.L, C = nearest.C, H = clamp_to_sector(nearest.H, sector), family = nearest }
    end
    return nil
end

return M
