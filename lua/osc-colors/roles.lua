-- Role-based highlight color generation.
--
-- Where the base16 mapping statically assigns slots ("keywords are base0E,
-- strings are base0B"), role mapping assigns *relationships*: each highlight
-- role is a descriptor -- importance tier, hue offset from the scheme's
-- dominant hue, chroma scale, lightness weight -- resolved through the
-- palette's soul (soul.lua) with OKLCH color math. A warm scheme leans its
-- whole role system warm; a monochrome scheme gets lightness/chroma
-- structure instead of hue spread; the same algorithm, radically different
-- palettes out -- which is the point.
--
-- Semantic exceptions (error/warning/info/success/diff) resist full
-- relativization: red-ish errors are a learned convention with safety
-- weight, so they stay anchored to their conventional hue *sectors*, with
-- the soul only placing the exact hue (and chroma/lightness) within the
-- sector.
--
-- Everything here is a pure function of (palette, cfg): deterministic,
-- snapshot-testable, no randomness.

local oklch = require("osc-colors.oklch")
local utils = require("osc-colors.utils")
local soulmod = require("osc-colors.soul")

local M = {}

-- Minimum angular distance (degrees) between distinct syntax/semantic role
-- hues. Sixteen syntax roles at 25deg would demand 400deg of wheel, so
-- this is a target the nudge ladder pursues, not a hard invariant; role
-- lightness/chroma differences carry the rest of the distinguishability.
-- Roles that intentionally share a color use the same role *name*, so they
-- never enter the separation pass.
local MIN_SEPARATION = 20

-- : Role descriptors [[[
--
-- offset: hue degrees from the soul's dominant hue (identity roles sit on
--   it; secondary roles spread rotations around it)
-- weight: position in the bg->fg OKLCH lightness envelope (0 = bg, 1 = fg)
-- chroma: scale on the soul's chroma ceiling
-- sector: { lo, hi } degrees -- conventional hue sector (semantic roles)
-- source: base slot whose queried hue is preferred inside the sector

local ROLE_ORDER = {
    -- semantic roles first: sector-anchored, never nudged; everything
    -- else must respect them
    "error",
    "warning",
    "success",
    "info",
    "hint",
    "deprecated",
    "diff_add",
    "diff_delete",
    "diff_change",
    -- identity: the scheme's character
    "keyword",
    "type",
    "import",
    "heading",
    -- secondary: spread around the dominant hue
    "function",
    "constant",
    "float",
    "character",
    "escape",
    "string",
    "regexp",
    "flow",
    "modifier",
    "tag",
    "namespace",
    "link",
    -- neutrals: lightness/chroma structure only
    "comment",
    "punctuation",
    "punct_section",
    "variable",
    "parameter",
    "property",
}

-- Hue rotations (from the soul's dominant hue) for the experimental
-- `soul.semantic = "derived"` policy; spread far enough apart that derived
-- semantics don't collapse onto each other.
local DERIVED_OFFSETS = {
    error = 180,
    warning = 150,
    success = 120,
    info = 90,
    hint = 60,
    deprecated = -60,
    diff_add = 120,
    diff_delete = 180,
    diff_change = 90,
}

local ROLE_DEFAULTS = {
    error = { sector = { 0, 40 }, source = "base08", weight = 0.72, chroma = 1.0 },
    warning = { sector = { 45, 75 }, source = "base09", weight = 0.72, chroma = 1.0 },
    success = { sector = { 110, 160 }, source = "base0B", weight = 0.70, chroma = 0.95 },
    info = { sector = { 190, 250 }, source = "base0D", weight = 0.70, chroma = 0.9 },
    hint = { sector = { 150, 200 }, source = "base0C", weight = 0.66, chroma = 0.75 },
    deprecated = { sector = { 280, 330 }, source = "base0E", weight = 0.62, chroma = 0.6 },
    diff_add = { sector = { 110, 160 }, source = "base0B", weight = 0.70, chroma = 0.9 },
    diff_delete = { sector = { 0, 40 }, source = "base08", weight = 0.70, chroma = 0.9 },
    diff_change = { sector = { 190, 250 }, source = "base0D", weight = 0.70, chroma = 0.9 },

    keyword = { tier = "identity", offset = 0, weight = 0.76, chroma = 1.0 },
    type = { tier = "identity", offset = 28, weight = 0.72, chroma = 0.9 },
    import = { tier = "identity", offset = 15, weight = 0.74, chroma = 0.9 },
    heading = { tier = "identity", offset = -30, weight = 0.8, chroma = 0.95 },

    ["function"] = { tier = "secondary", offset = -55, weight = 0.74, chroma = 0.85 },
    constant = { tier = "secondary", offset = 95, weight = 0.7, chroma = 0.8 },
    float = { tier = "secondary", offset = 112, weight = 0.7, chroma = 0.75 },
    character = { tier = "secondary", offset = -105, weight = 0.7, chroma = 0.75 },
    escape = { tier = "secondary", offset = -160, weight = 0.7, chroma = 0.7 },
    string = { tier = "secondary", offset = 150, weight = 0.68, chroma = 0.7 },
    regexp = { tier = "secondary", offset = 168, weight = 0.68, chroma = 0.7 },
    flow = { tier = "secondary", offset = 55, weight = 0.72, chroma = 0.8 },
    modifier = { tier = "secondary", offset = 75, weight = 0.72, chroma = 0.8 },
    tag = { tier = "secondary", offset = 90, weight = 0.72, chroma = 0.8 },
    namespace = { tier = "secondary", offset = -85, weight = 0.7, chroma = 0.7 },
    link = { tier = "secondary", offset = 128, weight = 0.7, chroma = 0.75 },

    comment = { tier = "neutral", weight = 0.42, chroma = 0.25 },
    punctuation = { tier = "neutral", weight = 0.55, chroma = 0.15 },
    punct_section = { tier = "neutral", weight = 0.62, chroma = 0.18 },
    variable = { tier = "neutral", weight = 0.85, chroma = 0.1 },
    parameter = { tier = "neutral", weight = 0.8, chroma = 0.1 },
    property = { tier = "neutral", weight = 0.82, chroma = 0.1 },
}

-- : ]]]

-- : Hue assignment [[[
--
-- Semantic roles get sector-anchored hues; identity/secondary roles get
-- dominant-hue offsets, deterministically nudged away from collisions
-- (the harmony trap: per-role "reasonable" hues that collectively clash).

local function hue_distance(a, b)
    local d = math.abs(a - b) % 360
    if d > 180 then
        d = 360 - d
    end
    return d
end

local function min_distance(hue, assigned)
    local m = math.huge
    for _, h in ipairs(assigned) do
        local d = hue_distance(hue, h)
        if d < m then
            m = d
        end
    end
    if m == math.huge then
        return 360
    end
    return m
end

---Assign a hue per role. Returns { [role] = hue_degrees }.
---
---Ordering is the crux. Syntax roles are *points* (dominant-hue offsets);
---semantic roles are *ranges* (conventional sectors). Syntax goes first so
---identity roles actually sit on the soul's dominant hue, and each semantic
---then scans its sector for the point farthest from everything already
---placed (preferring the scheme's own anchor hue) -- the sector constraint
---is what carries the safety convention, not any specific point in it.
---
---Semantic roles never nudge; syntax roles get a deterministic nudge ladder
---when their target collides with an earlier-assigned syntax role.
---@param soul table
---@param roles table<string, table> merged role descriptors
---@param semantic_policy "sector"|"derived"
local function assign_hues(soul, roles, semantic_policy)
    local hues = {}

    -- 1) identity + secondary syntax roles: points around the dominant hue.
    -- Initial pass takes each target as-is (collisions are the repair
    -- pass's problem -- greedy nudging here just moves collisions around).
    local syntax_names = {}
    for _, name in ipairs(ROLE_ORDER) do
        local r = roles[name]
        if r and r.tier and r.tier ~= "neutral" and not r.sector then
            hues[name] = (soul.hue_mean + (r.offset or 0)) % 360
            table.insert(syntax_names, name)
        end
    end

    -- Repair pass: for any role closer than MIN_SEPARATION to another,
    -- spiral out from its *target* in 5deg steps and take the first
    -- well-separated position (preferring minimal drift). Sixteen roles at
    -- 20deg demand 320deg of wheel, so a global solution exists; two passes
    -- let earlier roles yield to later ones's moves.
    for _ = 1, 2 do
        for _, name in ipairs(syntax_names) do
            local others = {}
            for _, other in ipairs(syntax_names) do
                if other ~= name then
                    table.insert(others, hues[other])
                end
            end
            if min_distance(hues[name], others) < MIN_SEPARATION then
                local target = (soul.hue_mean + (roles[name].offset or 0)) % 360
                local best, best_score = hues[name], -math.huge
                for k = 0, 36 do
                    local cands = (k == 0) and { 0 } or { 1, -1 }
                    for _, sign in ipairs(cands) do
                        local cand = (target + sign * k * 5) % 360
                        local d = min_distance(cand, others)
                        local score = (d >= MIN_SEPARATION and 1000 or 0) + d - k * 0.5
                        if score > best_score then
                            best, best_score = cand, score
                        end
                    end
                end
                hues[name] = best
            end
        end
    end

    -- 2) semantic roles: conventional hue sectors. The scan sees every
    -- final syntax hue, then every semantic placed before it.
    local assigned = {}
    for _, name in ipairs(syntax_names) do
        table.insert(assigned, hues[name])
    end
    for _, name in ipairs(ROLE_ORDER) do
        local r = roles[name]
        if r and r.sector then
            if semantic_policy == "derived" then
                -- experimental: fully soul-derived semantics -- fixed
                -- rotations away from the dominant hue instead of
                -- conventional sectors
                hues[name] = (soul.hue_mean + (DERIVED_OFFSETS[name] or 180)) % 360
            else
                local lo, hi = r.sector[1], r.sector[2]
                -- preferred point: the scheme's own anchor clamped into
                -- the sector (near enough, or the nearest edge)
                local pref = select(1, soulmod.sector_hue(soul, r.source, r.sector))
                local best, best_score = pref, -math.huge
                local h = lo
                while h <= hi do
                    -- maximize distance to everything placed; tiny tiebreak
                    -- toward the anchor hue keeps the scheme's own colors
                    local score = min_distance(h, assigned) - math.abs(h - pref) * 0.01
                    if score > best_score then
                        best, best_score = h, score
                    end
                    h = h + 2
                end
                hues[name] = best
            end
            table.insert(assigned, hues[name])
        end
    end

    -- 3) neutrals: the soul's dominant hue at (near-)zero chroma
    for _, name in ipairs(ROLE_ORDER) do
        local r = roles[name]
        if r and r.tier == "neutral" then
            hues[name] = soul.hue_mean
        end
    end

    return hues
end

-- : ]]]

-- : Color synthesis [[[
--
-- L: position in the bg->fg envelope (weights may exceed 1 slightly to let
-- accents pop past fg toward white/black, clamped to sane bounds).
-- C: scale on the soul's chroma ceiling; achromatic souls collapse to a
--    structured grayscale (tiny chroma, differentiation via L only).

local function envelope_l(soul, weight)
    -- Symmetric across dark/light: weight 0 = bg, 1 = fg; on light themes
    -- fg is *darker*, so the same weight lands correctly on dark, saturated
    -- accent territory.
    local L = soul.bg_L + (soul.fg_L - soul.bg_L) * weight
    if L < 0.12 then
        L = 0.12
    elseif L > 0.95 then
        L = 0.95
    end
    return L
end

---Resolve a single role to a hex color, enforcing the contrast target for
---readability against the background.
---@return string hex
local function resolve_role(soul, r, hue, opts)
    local ceiling = math.max(soul.chroma_max, soul.chroma_median * 1.5) * (opts.chroma_ceiling_scale or 1.0)
    local chroma
    if r.sector then
        -- semantics carry the scheme's own anchor saturation when it has
        -- one (gruvbox's error should be as red as gruvbox's red), with a
        -- legibility floor for muted souls
        local anchor_c = 0
        for _, a in ipairs(soul.anchors) do
            if a.slot == r.source then
                anchor_c = a.C
            end
        end
        chroma = math.max(math.min(anchor_c * 0.95, ceiling), 0.1)
    elseif r.tier == "neutral" then
        chroma = ceiling * (r.chroma or 0.2)
        if soul.achromatic then
            chroma = 0
        end
    else
        chroma = ceiling * (r.chroma or 1.0)
        if soul.achromatic then
            chroma = 0.02
        end
    end

    local weight = r.weight or 0.7
    local hex = oklch.oklch_to_hex(envelope_l(soul, weight), chroma, hue)

    -- contrast enforcement for text roles: bump lightness toward fg until
    -- the target clears (or we run out of envelope)
    local target = opts.contrast_target or 4.5
    local bg = soul.bg
    if bg then
        for _ = 1, 12 do
            if oklch.contrast(hex, bg) >= target then
                break
            end
            weight = weight + 0.05
            local L = envelope_l(soul, weight)
            local c = chroma
            -- very light colors can't carry full chroma; clamp alongside L
            hex = oklch.oklch_to_hex(L, c, hue)
        end
    end

    return hex
end

-- : ]]]

-- : Cube snapping [[[
--
-- On a probed 256-only terminal, generated colors must land on slots the
-- terminal can actually render -- prefer the *queried real* cube (terminals
-- routinely remap entries); fall back to the nominal xterm cube when the
-- query failed but the tier is still 256 (better a nominal match than no
-- cterm index at all).

local function build_snapper(cube)
    if type(cube) ~= "table" then
        return nil
    end
    local coords = {}
    for idx, hex in pairs(cube) do
        if utils.is_hex(hex) then
            local L, a, b = oklch.hex_to_oklab(hex)
            table.insert(coords, { idx = idx, hex = hex, L = L, a = a, b = b })
        end
    end
    if #coords == 0 then
        return nil
    end
    local memo = {}
    return function(hex)
        local key = hex:lower()
        if memo[key] then
            return memo[key]
        end
        local L, a, b = oklch.hex_to_oklab(hex)
        local best ---@type table|nil
        local best_d = math.huge
        for _, c in ipairs(coords) do
            local d = (L - c.L) ^ 2 + (a - c.a) ^ 2 + (b - c.b) ^ 2
            if d < best_d then
                best, best_d = c, d
            end
        end
        memo[key] = best.hex
        return best.hex
    end
end

-- : ]]]

-- : Public API [[[
--
-- Generate role -> hex for a palette + config. Also exposes the soul and
-- the snap decision, so callers (M.apply) and tests can inspect them.
--
---@param palette osc-colors.Palette
---@param cfg osc-colors.Config
---@return osc-colors.RoleGeneration
function M.generate(palette, cfg)
    local soul = soulmod.extract(palette)
    local opts = (cfg and cfg.soul) or {}
    local semantic_policy = opts.semantic or "sector"

    -- merge user role overrides over the defaults
    local roles = {}
    for name, defaults in pairs(ROLE_DEFAULTS) do
        local override = (opts.roles or {})[name]
        if type(override) == "table" then
            roles[name] = vim.tbl_deep_extend("force", {}, defaults, override)
        else
            roles[name] = defaults
        end
    end

    local hues = assign_hues(soul, roles, semantic_policy)

    local snap = nil
    local tier = palette.capability and palette.capability.tier or "unknown"
    if tier == "256" then
        snap = build_snapper(palette.cube or utils.nominal_cube())
    end

    local out = {}
    for _, name in ipairs(ROLE_ORDER) do
        local r = roles[name]
        local hex = resolve_role(soul, r, hues[name], opts)
        if snap then
            hex = snap(hex)
        end
        out[name] = hex
    end

    return { roles = out, soul = soul, snap = snap }
end

-- : ]]]

-- : Tree application [[[
--
-- Where each role lands in the canonical palette tree. Roles intentionally
-- sharing a color map several paths to one role name (matching the base16
-- statics' collapse, e.g. method == function).

local ROLE_PATHS = {
    keyword = {
        "syntax.keyword.default",
        "syntax.keyword.control.default",
        "syntax.keyword.operator",
        "syntax.keyword.declaration",
    },
    import = { "syntax.keyword.control.import" },
    flow = { "syntax.keyword.control.flow", "syntax.entity.name.label", "syntax.meta.preprocessor" },
    type = { "syntax.entity.name.type", "syntax.entity.name.class", "syntax.storage.type" },
    ["function"] = { 'syntax.entity.name["function"].default', 'syntax.entity.name["function"].constructor' },
    constant = {
        "syntax.constant.default",
        "syntax.constant.language",
        "syntax.constant.numeric.default",
        "syntax.constant.builtin",
        "syntax.markup.raw",
    },
    float = { "syntax.constant.numeric.float" },
    character = { "syntax.constant.character.default" },
    escape = { "syntax.constant.character.escape" },
    string = { "syntax.string.default", "syntax.string.other" },
    regexp = { "syntax.string.regexp" },
    modifier = { "syntax.storage.modifier", 'syntax.entity.other["attribute-name"]' },
    tag = { "syntax.entity.name.tag" },
    namespace = { "syntax.entity.name.namespace" },
    heading = { "syntax.markup.heading" },
    link = { "syntax.markup.link" },
    comment = { "syntax.comment" },
    punctuation = { "syntax.punctuation.separator" },
    punct_section = { "syntax.punctuation.section" },
    variable = { "syntax.variable.default", "syntax.variable.builtin" },
    parameter = { "syntax.variable.parameter" },
    property = { "syntax.variable.other.property" },
}

-- markup.list shares the flow role's color, matching the base16 statics'
-- base0A collapse.
table.insert(ROLE_PATHS.flow, "syntax.markup.list")

-- The gray ramp: base16 slots plus their canonical tree locations. Soul
-- mode leans these toward the dominant hue -- the touch that makes warm
-- themes get warm grays and cool themes cool ones.
local RAMP_PATHS = {
    { slot = "base01", tree = "palette.black.bright" },
    { slot = "base02", tree = "palette.gray.dim" },
    { slot = "base03", tree = "palette.gray.normal" },
    { slot = "base04", tree = "palette.gray.bright" },
    { slot = "base05", tree = "palette.white.normal" },
    { slot = "base06", tree = "palette.white.dim" },
}

local function path_segments(path)
    local segs = {}
    for seg in path:gmatch("[^.]+") do
        local bracket = seg:match('^%["(.+)"%]$')
        table.insert(segs, bracket or seg)
    end
    return segs
end

local function set_path(root, path, value)
    local segs = path_segments(path)
    local cur = root
    for i = 1, #segs - 1 do
        if type(cur[segs[i]]) ~= "table" then
            return false
        end
        cur = cur[segs[i]]
    end
    cur[segs[#segs]] = value
    return true
end

---Apply role-based colors to a *normalized* palette, in place. Extends the
---tree with `semantics`, rewrites the syntax tree's role colors, leans the
---gray ramp toward the dominant hue, and refines the tag-attribute accent
---from the assigned role hues. Idempotent: a palette already carrying the
---soul pass (flag survives colors.normalize) is left untouched.
---
---No-op below truecolor tier is *not* handled here: the 256 tier is handled
---by cube snapping inside generate(), and the base16 mapping is simply this
---function never being called.
---@param palette osc-colors.Palette
---@param cfg osc-colors.Config
---@return osc-colors.Palette
function M.apply(palette, cfg)
    if palette._soul_applied then
        return palette
    end

    local gen = M.generate(palette, cfg)
    local role_hex = gen.roles
    local snap = gen.snap
    local soul = gen.soul

    for role, paths in pairs(ROLE_PATHS) do
        local hex = role_hex[role]
        if hex then
            for _, p in ipairs(paths) do
                set_path(palette, p, hex)
            end
        end
    end

    -- Semantic single source of truth + the existing ui.status surface.
    palette.semantics = {
        error = role_hex.error,
        warning = role_hex.warning,
        info = role_hex.info,
        hint = role_hex.hint,
        success = role_hex.success,
        deprecated = role_hex.deprecated,
        diff = { add = role_hex.diff_add, delete = role_hex.diff_delete, change = role_hex.diff_change },
    }
    if palette.ui and palette.ui.status then
        palette.ui.status.error = role_hex.error
        palette.ui.status.warning = role_hex.warning
        palette.ui.status.info = role_hex.info
        palette.ui.status.success = role_hex.success
    end
    if palette.syntax and palette.syntax.markup then
        palette.syntax.markup.inserted = role_hex.diff_add
        palette.syntax.markup.deleted = role_hex.diff_delete
    end

    -- Gray ramp lean: a whisper of the dominant hue on the neutrals, the
    -- way hand-made themes pick "warm gray" or "cool gray" deliberately.
    -- Achromatic souls lean zero (pure grayscale structure).
    local lean = 0
    if not soul.achromatic then
        lean = math.min(0.018, math.max(soul.chroma_median * 0.06, 0.006))
    end
    for _, entry in ipairs(RAMP_PATHS) do
        local hex = palette[entry.slot]
        if utils.is_hex(hex) then
            local L = select(1, oklch.hex_to_oklch(hex))
            local leaned = oklch.oklch_to_hex(L, lean, soul.hue_mean)
            if snap then
                leaned = snap(leaned)
            end
            palette[entry.slot] = leaned
            set_path(palette, entry.tree, leaned)
        end
    end

    -- Tag-attribute accent: the widest hue gap *between assigned role
    -- hues*, so the accent stays in-family with whatever this soul
    -- actually produced (a generalization of the base16 derive_accent).
    local tag_attr = palette.syntax
        and palette.syntax.entity
        and palette.syntax.entity.other
        and palette.syntax.entity.other["tag-attribute-name"]
    local accent = utils.derive_accent({
        role_hex.keyword,
        role_hex.type,
        role_hex.string,
        role_hex.constant,
        role_hex["function"],
        role_hex.tag,
    }, tag_attr or role_hex.tag)
    if snap then
        accent = snap(accent)
    end
    set_path(palette, 'syntax.entity.other["tag-attribute-name"]', accent)

    palette._soul_applied = true
    return palette
end

-- : ]]]

return M
