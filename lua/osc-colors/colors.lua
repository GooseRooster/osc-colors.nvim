-- Palette shape normalizer.
-- osc-colors never loads a palette by name — the OSC layer always hands over
-- a complete flat base00-base0F table it just synthesized from the live
-- terminal. This module's only job is filling in the derived tinted8 tree
-- (palette/ui/syntax) and the legacy base slots from whichever shape is
-- present, so the highlight-building engine (ported from tinted-nvim, which
-- DOES support named base16/base24/tinted8 schemes) sees the same consistent
-- palette shape it always expects.

local M = {}

-- Synthesize the tinted8-shaped tree (palette/ui/syntax) from a base16/24
-- palette's legacy base00-baseXX slots. Mirrors the per-key fills in
-- templates/base16.lua.mustache and templates/base24.lua.mustache exactly.
-- Existing tree values (e.g. partial overrides from user-defined schemes) are
-- preserved via deep-merge with "keep" semantics. No-op when there's no
-- legacy slot to synthesize from.
local function synthesize_tree(palette, system)
    if not palette.base00 then
        return palette
    end

    -- Auto-detect base24 by presence of bright slots when no explicit system is given.
    local is_base24 = (system == "base24") or (system == nil and palette.base12 ~= nil)
    local s = palette

    local synthesized = {}
    synthesized.palette = {
        black = { normal = s.base00, bright = s.base01 },
        -- base04 is spec-designated "Light Gray", not a white variant — it lives in gray.bright.
        gray = { dim = s.base02, normal = s.base03, bright = s.base04 },
        -- base06 ("Lighter White") occupies the white.dim slot. Name vs. luminance
        -- is a slot-identifier convention here, not a strict semantic claim.
        white = { dim = s.base06, normal = s.base05, bright = s.base07 },
        red = { normal = s.base08, bright = is_base24 and s.base12 or s.base08 },
        orange = { normal = s.base09, bright = s.base09 },
        yellow = { normal = s.base0A, bright = is_base24 and s.base13 or s.base0A },
        green = { normal = s.base0B, bright = is_base24 and s.base14 or s.base0B },
        cyan = { normal = s.base0C, bright = is_base24 and s.base15 or s.base0C },
        blue = { normal = s.base0D, bright = is_base24 and s.base16 or s.base0D },
        magenta = { normal = s.base0E, bright = is_base24 and s.base17 or s.base0E },
        brown = { normal = s.base0F },
    }

    synthesized.ui = {
        global = {
            background = { normal = s.base00 },
            foreground = { normal = s.base05 },
        },
        cursor = {
            background = { normal = s.base05 },
            foreground = { normal = s.base00 },
        },
        gutter = { foreground = s.base02 },
        border = { normal = s.base03 },
        chrome = {
            background = { normal = s.base02, dark = s.base01 },
            foreground = { normal = s.base05, dark = s.base04 },
        },
        selection = { background = s.base01 },
        highlight = {
            line = { background = s.base01 },
            text = { background = s.base02 },
            search = { background = s.base01, foreground = s.base0A },
        },
        status = {
            error = s.base08,
            warning = s.base09,
            info = s.base0A,
            success = is_base24 and s.base14 or s.base0B,
        },
    }

    synthesized.syntax = {
        comment = s.base03,
        string = {
            default = s.base0B,
            regexp = s.base0B,
            other = s.base0B,
        },
        constant = {
            default = s.base09,
            character = { default = s.base08, escape = s.base0C },
            language = s.base09,
            numeric = { default = s.base09, float = s.base09 },
        },
        entity = {
            name = {
                class = s.base0A,
                type = s.base0A,
                ["function"] = { default = s.base0D, constructor = s.base0D },
                label = s.base0A,
                namespace = s.base08,
                tag = s.base0A,
            },
            other = {
                ["attribute-name"] = s.base0A,
            },
        },
        keyword = {
            default = s.base0E,
            control = { default = s.base0E, import = s.base0D, flow = s.base0A },
            operator = s.base0E,
            declaration = s.base0E,
        },
        storage = { type = s.base0E, modifier = s.base0A },
        variable = {
            default = s.base05,
            parameter = s.base05,
            other = { property = s.base05 },
        },
        punctuation = { separator = s.base0F, section = s.base0F },
        markup = {
            default = s.base05,
            heading = s.base0D,
            raw = s.base09,
            link = s.base09,
            list = s.base0A,
            inserted = s.base0B,
            deleted = s.base08,
        },
        meta = { preprocessor = s.base0A },
    }

    -- "keep" mode: existing values in `palette` win over synthesized ones.
    -- This ensures user-defined schemes with a partial palette/ui/syntax tree
    -- keep their explicit overrides, with only missing leaves filled in.
    return vim.tbl_deep_extend("keep", palette, synthesized)
end

-- For palettes that have the tinted8 tree but lack legacy baseXX slots
-- (e.g. a newly-regenerated tinted8-shape file or a tinted8-native scheme),
-- synthesize the legacy slots from the tree so backwards-compatible consumers
-- (terminal.lua, aliases.lua, user overrides) keep working.
-- Each slot is only filled if missing; nil-safe against partial trees.
local function ensure_legacy_slots(palette, system)
    if not palette.palette then
        return palette
    end

    local p = palette.palette
    local out = vim.tbl_extend("force", {}, palette)
    local function fill(slot, color_name, variant)
        if out[slot] ~= nil then
            return
        end
        local color = p[color_name]
        if color and color[variant] then
            out[slot] = color[variant]
        end
    end

    fill("base00", "black", "normal")
    fill("base01", "black", "bright")
    fill("base02", "gray", "dim")
    fill("base03", "gray", "normal")
    fill("base04", "gray", "bright")
    fill("base05", "white", "normal")
    fill("base06", "white", "dim")
    fill("base07", "white", "bright")
    fill("base08", "red", "normal")
    fill("base09", "orange", "normal")
    fill("base0A", "yellow", "normal")
    fill("base0B", "green", "normal")
    fill("base0C", "cyan", "normal")
    fill("base0D", "blue", "normal")
    fill("base0E", "magenta", "normal")
    fill("base0F", "brown", "normal")

    -- Base24 extended slots: only fill for systems that semantically have brights.
    -- For base16 schemes we deliberately skip these so the cterm map doesn't gain
    -- duplicate hex entries (which would make hex→cterm lookup non-deterministic).
    if system ~= "base16" then
        fill("base10", "black", "normal")
        fill("base11", "black", "bright")
        fill("base12", "red", "bright")
        fill("base13", "yellow", "bright")
        fill("base14", "green", "bright")
        fill("base15", "cyan", "bright")
        fill("base16", "blue", "bright")
        fill("base17", "magenta", "bright")
    end
    return out
end

-- Public: idempotently normalize any palette shape to the canonical dual form
-- (legacy base slots + tinted8 tree). Existing values are never overwritten;
-- only missing keys are filled. Callers that construct palettes outside
-- M.resolve (e.g. tests) can call this to ensure the shape downstream code expects.
---@param palette osc-colors.Palette
---@return osc-colors.Palette
function M.normalize(palette)
    -- Heuristic system detection from palette shape, used only to decide
    -- whether base10-base17 should be synthesized.
    local detected
    if palette.base17 ~= nil or palette.base12 ~= nil then
        detected = "base24"
    elseif palette.base00 ~= nil then
        detected = "base16"
    else
        detected = "tinted8"
    end
    palette = synthesize_tree(palette, detected)
    palette = ensure_legacy_slots(palette, detected)
    return palette
end

return M
