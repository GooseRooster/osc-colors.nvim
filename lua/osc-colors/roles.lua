-- Role-based highlight color generation.
--
-- Where the base16 mapping statically assigns slots ("keywords are base0E,
-- strings are base0B"), soul mapping assigns highlight *roles* to the
-- scheme's own color *families* (soul.lua), chosen by how much the
-- designer invested in each color: the most prominent roles in code get
-- the scheme's most salient colors, and roles that sit side by side get
-- colors that differ. Gruvbox ends up speaking in its reds, yellows and
-- greens and barely touches its muted blue; nord stays in its frost; a
-- scheme whose "green" is really teal gets teal where green would have
-- gone. The same algorithm, genuinely different role maps out.
--
-- Roles come in six *groups* (keyword, function, type, string, constant,
-- special). A group's lead role takes its family's color as-is; the other
-- members are small variations of it (bright shade, lightness/chroma step,
-- a few degrees of hue drift) plus italic/bold where color alone can't
-- tell them apart.
--
-- Semantic exceptions (error/warning/info/success/diff) stay anchored to
-- their conventional hue *sectors* -- red-ish errors are a learned
-- convention with safety weight -- but still use the scheme's own color
-- for the sector whenever it has one.
--
-- Everything here is a pure function of (palette, cfg): deterministic,
-- snapshot-testable, no randomness.

local oklch = require("osc-colors.oklch")
local utils = require("osc-colors.utils")
local soulmod = require("osc-colors.soul")

local M = {}

-- : Role groups & descriptors [[[
--
-- prominence: how much of a typical buffer the group paints (and so how
--   salient a family it deserves)
-- style: applied to the group's lead role when it can't be told apart
--   from a more prominent group by color

local GROUPS = {
    { name = "keyword", lead = "keyword", prominence = 1.0, style = { italic = true } },
    { name = "function", lead = "function", prominence = 0.85, style = { bold = true } },
    { name = "type", lead = "type", prominence = 0.75, style = { bold = true } },
    { name = "string", lead = "string", prominence = 0.65, style = { italic = true } },
    { name = "constant", lead = "constant", prominence = 0.5, style = { bold = true } },
    { name = "special", lead = "escape", prominence = 0.35, style = { italic = true } },
}
M.GROUPS = GROUPS

-- How often two groups sit next to each other in real code -- the more
-- often, the more their colors need to differ. Missing pairs default low.
local ADJACENCY = {
    ["keyword|function"] = 1.0,
    ["keyword|type"] = 0.8,
    ["function|type"] = 0.7,
    ["keyword|string"] = 0.6,
    ["string|constant"] = 0.6,
    ["string|special"] = 0.6, -- escapes live inside strings
    ["function|string"] = 0.5,
    ["keyword|constant"] = 0.5,
    ["type|string"] = 0.5,
    ["type|constant"] = 0.4,
    ["function|constant"] = 0.4,
    ["keyword|special"] = 0.3,
    ["constant|special"] = 0.3,
}
local ADJACENCY_DEFAULT = 0.2

-- Weight of the separation term against prominence x salience, and the
-- score for two groups sharing one family (a penalty, not a ban: a muted
-- scheme with three real colors *should* reuse them).
local SEPARATION_WEIGHT = 0.35
local SHARED_FAMILY_SEP = -0.5
local SEPARATION_HUE = 60 -- hue distance (deg) that counts as fully separated
local SEPARATION_DELTA_E = 0.2 -- or OKLab distance (lightness-separated families)

-- Families beyond this many (by salience) don't enter the search.
local MAX_SEARCH_FAMILIES = 8

-- Two final colors closer than this (OKLab) can't be told apart by color
-- alone; that's where styles get spent in `styles = "auto"`.
local STYLE_DELTA_E = 0.045

-- Role descriptors.
--   group: owning group (lead roles are listed in GROUPS)
--   shade: prefer the family's bright shade (falls back to `lightness`)
--   lightness: OKLCH L step, positive = toward foreground
--   chroma: scale on the family's chroma
--   hue: drift in degrees, steered away from the nearest other group
--   style: candidate text attributes (see assign_styles)
--   always: apply `style` whenever styles are enabled at all
--   tier = "neutral": low-chroma structure tinted toward the dominant hue
--     (weight: position in the bg->fg lightness envelope)
--   sector/source: semantic roles (see soul.sector_color); `like` copies
--     another semantic role
local ROLE_DEFAULTS = {
    error = { sector = { 0, 40 }, source = "red", weight = 0.72 },
    warning = { sector = { 45, 75 }, source = "yellow", weight = 0.72 },
    success = { sector = { 110, 160 }, source = "green", weight = 0.70 },
    info = { sector = { 190, 250 }, source = "blue", weight = 0.70 },
    hint = { sector = { 150, 200 }, source = "cyan", weight = 0.66 },
    deprecated = { sector = { 280, 330 }, source = "magenta", weight = 0.62 },
    diff_add = { like = "success" },
    diff_delete = { like = "error" },
    diff_change = { like = "info" },

    keyword = { group = "keyword" },
    flow = { group = "keyword", hue = 10, lightness = 0.03, style = { italic = true } },
    import = { group = "keyword", shade = true, hue = 6, lightness = 0.06, style = { italic = true } },
    modifier = { group = "keyword", chroma = 0.8, lightness = -0.04, style = { italic = true } },

    ["function"] = { group = "function" },

    type = { group = "type" },
    namespace = { group = "type", chroma = 0.7, lightness = 0.05, style = { italic = true } },
    tag = { group = "type", hue = 8 },

    string = { group = "string" },
    regexp = { group = "string", hue = 12, lightness = 0.03 },
    character = { group = "string", hue = 10, lightness = -0.03 },

    constant = { group = "constant" },
    float = { group = "constant" },

    escape = { group = "special" },
    heading = { group = "special", shade = true, lightness = 0.04, style = { bold = true }, always = true },
    link = { group = "special", hue = 10 },

    comment = { tier = "neutral", weight = 0.42, chroma = 0.3 },
    punctuation = { tier = "neutral", weight = 0.55, chroma = 0.2 },
    punct_section = { tier = "neutral", weight = 0.62, chroma = 0.25 },
    variable = { tier = "neutral", weight = 0.85, chroma = 0.12 },
    parameter = { tier = "neutral", weight = 0.8, chroma = 0.12, style = { italic = true } },
    property = { tier = "neutral", weight = 0.82, chroma = 0.15 },
}

local ROLE_ORDER = {
    -- semantic roles first: they claim families in this order
    "error",
    "warning",
    "success",
    "info",
    "hint",
    "deprecated",
    "diff_add",
    "diff_delete",
    "diff_change",
    "keyword",
    "flow",
    "import",
    "modifier",
    "function",
    "type",
    "namespace",
    "tag",
    "string",
    "regexp",
    "character",
    "constant",
    "float",
    "escape",
    "heading",
    "link",
    "comment",
    "punctuation",
    "punct_section",
    "variable",
    "parameter",
    "property",
}
M.ROLE_ORDER = ROLE_ORDER

-- Grayscale fallback for achromatic souls: lead lightness weights in the
-- bg->fg envelope, so groups still stratify (styles carry the rest).
local ACHROMATIC_WEIGHTS = {
    keyword = 0.95,
    ["function"] = 0.88,
    type = 0.82,
    string = 0.74,
    constant = 0.68,
    special = 0.62,
}

-- : ]]]

-- : Group -> family assignment [[[

local function pair_weight(a, b)
    return ADJACENCY[a .. "|" .. b] or ADJACENCY[b .. "|" .. a] or ADJACENCY_DEFAULT
end

local function separation(f1, f2)
    if f1 == f2 then
        return SHARED_FAMILY_SEP
    end
    local by_hue = soulmod.hue_distance(f1.H, f2.H) / SEPARATION_HUE
    local by_de = oklch.delta_e(f1.hex, f2.hex) / SEPARATION_DELTA_E
    return math.min(1, math.max(by_hue, by_de))
end

---Pick a family per group, maximizing
---  sum(prominence * salience) + SEPARATION_WEIGHT * sum(adjacency * separation)
---by exact branch-and-bound search (families may be reused, at a cost).
---@param soul osc-colors.Soul
---@param pin table<string, string> group name -> family name
---@return table<string, osc-colors.SoulFamily>|nil
local function assign_groups(soul, pin)
    local fams = {}
    for i = 1, math.min(#soul.ranked, MAX_SEARCH_FAMILIES) do
        fams[i] = soul.ranked[i]
    end
    if #fams == 0 then
        return nil
    end

    local G = #GROUPS
    local candidates = {}
    for g, group in ipairs(GROUPS) do
        local pinned = pin[group.name] and soulmod.family(soul, pin[group.name])
        candidates[g] = pinned and { pinned } or fams
    end

    local sep = {}
    local all = {}
    for _, list in ipairs(candidates) do
        for _, f in ipairs(list) do
            all[f] = true
        end
    end
    for f1 in pairs(all) do
        sep[f1] = {}
        for f2 in pairs(all) do
            sep[f1][f2] = separation(f1, f2)
        end
    end

    local weights = {}
    for i = 1, G do
        weights[i] = {}
        for j = 1, G do
            weights[i][j] = pair_weight(GROUPS[i].name, GROUPS[j].name)
        end
    end

    -- remaining[k]: the best any assignment of groups k..G could still add
    local remaining = {}
    remaining[G + 1] = 0
    for k = G, 1, -1 do
        local best_sal = 0
        for _, f in ipairs(candidates[k]) do
            best_sal = math.max(best_sal, f.salience)
        end
        local pairs_bound = 0
        for i = 1, k - 1 do
            pairs_bound = pairs_bound + SEPARATION_WEIGHT * weights[i][k]
        end
        remaining[k] = remaining[k + 1] + GROUPS[k].prominence * best_sal + pairs_bound
    end

    local current, best, best_score = {}, nil, -math.huge
    local function search(k, score)
        if k > G then
            if score > best_score then
                best_score = score
                best = { unpack(current) }
            end
            return
        end
        if score + remaining[k] <= best_score then
            return
        end
        for _, f in ipairs(candidates[k]) do
            local s = score + GROUPS[k].prominence * f.salience
            for i = 1, k - 1 do
                s = s + SEPARATION_WEIGHT * weights[i][k] * sep[current[i]][f]
            end
            current[k] = f
            search(k + 1, s)
        end
        current[k] = nil
    end
    search(1, 0)

    local out = {}
    for g, group in ipairs(GROUPS) do
        out[group.name] = best[g]
    end
    return out
end

-- : ]]]

-- : Color synthesis [[[

local function clamp_l(L)
    return math.max(0.05, math.min(0.98, L))
end

local function envelope_l(soul, weight)
    return clamp_l(soul.bg_L + (soul.fg_L - soul.bg_L) * weight)
end

-- +1 when "toward foreground" means lighter (dark themes), -1 otherwise
local function fg_direction(soul)
    return soul.fg_L >= soul.bg_L and 1 or -1
end

---Render an OKLCH base to hex, stepping lightness toward the foreground
---until the contrast target against the background clears (or the
---envelope runs out).
local function render(soul, L, C, H, target)
    local dir = fg_direction(soul)
    L = clamp_l(L)
    local hex = oklch.oklch_to_hex(L, C, H % 360)
    if not soul.bg then
        return hex
    end
    for _ = 1, 40 do
        if oklch.contrast(hex, soul.bg) >= target then
            break
        end
        local nextL = clamp_l(L + 0.02 * dir)
        if nextL == L then
            break
        end
        L = nextL
        hex = oklch.oklch_to_hex(L, C, H % 360)
    end
    return hex
end

-- Signed hue drift for a member role: steer away from the nearest hue
-- used by another group, so variations never wander into a neighbor.
local function steer(own, others, drift)
    local nearest, nearest_d = nil, math.huge
    for _, h in ipairs(others) do
        local d = soulmod.hue_distance(own, h)
        if d > 0.5 and d < nearest_d then
            nearest, nearest_d = h, d
        end
    end
    if not nearest then
        return drift
    end
    local signed = (own - nearest + 540) % 360 - 180
    return signed >= 0 and math.abs(drift) or -math.abs(drift)
end

local function resolve_semantics(soul, roles, opts, out, chosen)
    local taken = {}
    for _, name in ipairs(ROLE_ORDER) do
        local r = roles[name]
        if r.sector then
            local pick = soulmod.sector_color(soul, r.source, r.sector, taken)
            local L, C, H
            if pick then
                taken[pick.family] = true
                L, C, H = pick.L, math.max(pick.C * 0.95, 0.1), pick.H
            else
                L, C, H = envelope_l(soul, r.weight or 0.7), 0.1, (r.sector[1] + r.sector[2]) / 2
            end
            L = L + (r.lightness or 0) * fg_direction(soul)
            C = C * (r.chroma or 1)
            H = H + (r.hue or 0)
            out[name] = render(soul, L, C, H, opts.contrast_target)
            chosen[name] = pick and pick.family or nil
        end
    end
    for _, name in ipairs(ROLE_ORDER) do
        local r = roles[name]
        if r.like then
            out[name] = out[r.like]
            chosen[name] = chosen[r.like]
        end
    end
end

local function resolve_syntax(soul, roles, assignment, opts, out)
    local dir = fg_direction(soul)
    local group_hues = {}
    if assignment then
        for _, group in ipairs(GROUPS) do
            group_hues[group.name] = assignment[group.name].H
        end
    end

    for _, name in ipairs(ROLE_ORDER) do
        local r = roles[name]
        if r.group then
            local L, C, H
            local lightness = r.lightness or 0
            if assignment then
                local fam = assignment[r.group]
                local base = fam
                if r.shade and fam.shade and oklch.delta_e(fam.shade.hex, fam.hex) >= 0.02 then
                    base = fam.shade
                    lightness = 0
                end
                L, C, H = base.L, base.C, base.H
                if r.hue then
                    local others = {}
                    for g, h in pairs(group_hues) do
                        if g ~= r.group and assignment[g] ~= fam then
                            table.insert(others, h)
                        end
                    end
                    H = H + steer(fam.H, others, r.hue)
                end
            else
                L, C, H = envelope_l(soul, ACHROMATIC_WEIGHTS[r.group]), 0, 0
            end
            L = L + lightness * dir
            C = C * (r.chroma or 1)
            out[name] = render(soul, L, C, H, opts.contrast_target)
        elseif r.tier == "neutral" then
            local C = soul.achromatic and 0 or soul.chroma_median * (r.chroma or 0.2)
            out[name] = render(soul, envelope_l(soul, r.weight or 0.7), C, soul.dominant_hue, opts.contrast_target)
        end
    end
end

-- : ]]]

-- : Styles [[[
--
-- "auto" spends italic/bold exactly where color runs out:
--   * `always` roles (heading bold) whenever styles are on
--   * a group lead that can't be told apart from a more prominent group's
--     lead (shared family, or colors within STYLE_DELTA_E) gets its
--     group's style
--   * a member role that can't be told apart from its lead or from
--     another group's lead gets its own style
--   * achromatic souls: color can't separate anything, so every role with
--     a style candidate gets it
-- "always" applies every candidate; false disables soul styles entirely.
-- User `soul.roles[name].style` wins over all of the above.

local function close(a, b)
    return oklch.delta_e(a, b) < STYLE_DELTA_E
end

local function assign_styles(soul, roles, assignment, out, mode)
    local styles = {}
    if mode == false then
        return styles
    end
    local everything = mode == "always" or soul.achromatic

    local lead_of = {}
    for _, group in ipairs(GROUPS) do
        lead_of[group.name] = group.lead
    end

    for gi, group in ipairs(GROUPS) do
        local need = everything
        for gj = 1, gi - 1 do
            local other = GROUPS[gj]
            local shared = assignment and assignment[group.name] == assignment[other.name]
            if shared or close(out[group.lead], out[other.lead]) then
                need = true
            end
        end
        if need then
            styles[group.lead] = vim.deepcopy(group.style)
        end
    end

    for _, name in ipairs(ROLE_ORDER) do
        local r = roles[name]
        if r.style and not styles[name] and lead_of[r.group] ~= name then
            local need = everything or r.always
            if not need and r.group then
                for _, group in ipairs(GROUPS) do
                    if close(out[name], out[group.lead]) then
                        need = true
                    end
                end
            end
            if need then
                styles[name] = vim.deepcopy(r.style)
            end
        end
    end

    for _, name in ipairs(ROLE_ORDER) do
        local style = roles[name].user_style
        if style == false then
            styles[name] = nil
        elseif type(style) == "table" then
            styles[name] = vim.deepcopy(style)
        end
    end

    return styles
end

-- Highlight groups that paint each role's color directly (links inherit
-- from these). Kept here rather than in the forked highlight builders so
-- the engine files stay untouched; consumed by highlights/init.lua.
local STYLE_TARGETS = {
    keyword = { "Keyword", "Conditional", "Define", "@conditional", "@repeat", "@define", "TSConditional" },
    flow = { "Repeat", "Label", "@label", "TSRepeat", "TSLabel" },
    import = { "Include", "@include", "TSInclude" },
    modifier = { "StorageClass", "@storageclass", "@attribute", "TSAttribute" },
    ["function"] = { "Function", "@method", "@constructor", "TSMethod", "TSConstructor" },
    type = { "Type", "Typedef", "Structure" },
    namespace = { "@namespace", "TSNamespace" },
    tag = { "Tag", "@tag", "TSTag" },
    string = { "String", "@string", "TSString" },
    regexp = { "@string.regexp", "TSStringRegex" },
    character = { "Character", "@character", "TSCharacter" },
    constant = {
        "Constant",
        "Boolean",
        "Number",
        "@constant",
        "@constant.builtin",
        "@boolean",
        "@number",
        "TSConstant",
        "TSBoolean",
        "TSNumber",
    },
    float = { "Float", "@float", "TSFloat" },
    escape = { "Special", "@string.escape", "TSStringEscape" },
    heading = { "@markup.heading", "@text.title", "TSTitle" },
    link = { "@markup.link.url", "@text.uri", "TSURI" },
    parameter = { "@parameter", "TSParameter" },
}

---Merge soul role styles into a built highlight table, in place. Existing
---attributes win ("keep"), so `cfg.styles` and explicit builder styles are
---never overridden; link-only groups are left alone.
---@param hl table<string, table>
---@param role_styles? table<string, table>
function M.style_highlights(hl, role_styles)
    if type(role_styles) ~= "table" then
        return
    end
    for role, style in pairs(role_styles) do
        for _, group in ipairs(STYLE_TARGETS[role] or {}) do
            local spec = hl[group]
            if spec and not spec.link then
                hl[group] = vim.tbl_extend("keep", spec, style)
            end
        end
    end
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
    table.sort(coords, function(x, y)
        return x.idx < y.idx
    end)
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

local function merged_roles(opts)
    local roles = {}
    for name, defaults in pairs(ROLE_DEFAULTS) do
        local override = (opts.roles or {})[name]
        if type(override) == "table" then
            local r = vim.tbl_extend("force", {}, defaults)
            for _, key in ipairs({ "lightness", "chroma", "hue" }) do
                if override[key] ~= nil then
                    r[key] = override[key]
                end
            end
            r.user_style = override.style
            roles[name] = r
        else
            roles[name] = defaults
        end
    end
    return roles
end

---Generate role -> hex (and role -> style) for a palette + config. Also
---exposes the soul, the group -> family assignment and the snap decision,
---so callers (M.apply, health) and tests can inspect them.
---@param palette osc-colors.Palette
---@param cfg osc-colors.Config
---@return osc-colors.RoleGeneration
function M.generate(palette, cfg)
    local soul = soulmod.extract(palette)
    local opts = vim.tbl_extend("force", { contrast_target = 4.5, styles = "auto", pin = {} }, (cfg and cfg.soul) or {})
    local roles = merged_roles(opts)

    local assignment = assign_groups(soul, opts.pin or {})

    local out, semantic_families = {}, {}
    resolve_semantics(soul, roles, opts, out, semantic_families)
    resolve_syntax(soul, roles, assignment, opts, out)

    local snap = nil
    local tier = palette.capability and palette.capability.tier or "unknown"
    if tier == "256" then
        snap = build_snapper(palette.cube or utils.nominal_cube())
    end
    if snap then
        for name, hex in pairs(out) do
            out[name] = snap(hex)
        end
    end

    local styles = assign_styles(soul, roles, assignment, out, opts.styles)

    local families = {}
    if assignment then
        for group, fam in pairs(assignment) do
            families[group] = fam.name
        end
    end

    return { roles = out, styles = styles, soul = soul, assignment = families, snap = snap }
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
    -- markup.list shares the flow role's color, matching the base16
    -- statics' base0A collapse.
    flow = {
        "syntax.keyword.control.flow",
        "syntax.entity.name.label",
        "syntax.meta.preprocessor",
        "syntax.markup.list",
    },
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

-- The gray ramp: base16 slots plus their canonical tree locations. Soul
-- mode leans these toward the dominant family's hue -- the touch that
-- makes warm themes get warm grays and cool themes cool ones.
local RAMP_PATHS = {
    { slot = "base01", tree = "palette.black.bright" },
    { slot = "base02", tree = "palette.gray.dim" },
    { slot = "base03", tree = "palette.gray.normal" },
    { slot = "base04", tree = "palette.gray.bright" },
    { slot = "base05", tree = "palette.white.normal" },
    { slot = "base06", tree = "palette.white.dim" },
}

-- Split 'a.b["c-d"].e' into { "a", "b", "c-d", "e" }. Bracketed keys may
-- follow a name directly (`name["function"]`), not just a dot.
local function path_segments(path)
    local segs = {}
    local i = 1
    while i <= #path do
        local key, stop = path:match('^%["([^"]+)"%]()', i)
        if not key then
            key, stop = path:match("^([^.%[]+)()", i)
        end
        if not key then
            break
        end
        table.insert(segs, key)
        i = stop
        if path:sub(i, i) == "." then
            i = i + 1
        end
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
---tree with `semantics` and `role_styles`, rewrites the syntax tree's role
---colors, leans the gray ramp toward the dominant family's hue, and
---refines the tag-attribute accent from the assigned role hues.
---Idempotent: a palette already carrying the soul pass (flag survives
---colors.normalize) is left untouched.
---
---The 256 tier is handled by cube snapping inside generate(); the base16
---mapping is simply this function never being called.
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

    palette.role_styles = gen.styles

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
            local leaned = oklch.oklch_to_hex(L, lean, soul.dominant_hue)
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
