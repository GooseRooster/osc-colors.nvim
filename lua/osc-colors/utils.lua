local M = {}

local function clamp(value, min, max)
    if value < min then
        return min
    end
    if value > max then
        return max
    end
    return value
end

local function to_rgb(hex)
    local r = tonumber(hex:sub(2, 3), 16)
    local g = tonumber(hex:sub(4, 5), 16)
    local b = tonumber(hex:sub(6, 7), 16)
    return r, g, b
end

local function to_hex(r, g, b)
    return string.format("#%02x%02x%02x", r, g, b)
end

function M.blend(fg, bg, amount)
    if fg:lower() == "none" then
        return "NONE"
    end
    if bg:lower() == "none" then
        return fg
    end

    local a = clamp(amount or 0, 0, 1)
    local fr, fg_, fb = to_rgb(fg)
    local br, bg_, bb = to_rgb(bg)

    local r = math.floor((fr * (1 - a)) + (br * a) + 0.5)
    local g = math.floor((fg_ * (1 - a)) + (bg_ * a) + 0.5)
    local b = math.floor((fb * (1 - a)) + (bb * a) + 0.5)

    return to_hex(r, g, b)
end

function M.darken(hex, amount, bg)
    return M.blend(hex, bg, amount)
end

function M.lighten(hex, amount, bg)
    return M.blend(hex, bg, amount)
end

-- : HSL color math [[[
-- Used to algorithmically derive extra accent tones from a scheme's own
-- hues (e.g. for treesitter roles like `@tag.attribute` that have no
-- dedicated base16 slot), rather than statically reusing an existing color
-- that already carries a different meaning elsewhere.

---@param r number 0-255
---@param g number 0-255
---@param b number 0-255
---@return number h 0-360
---@return number s 0-1
---@return number l 0-1
function M.rgb_to_hsl(r, g, b)
    r, g, b = r / 255, g / 255, b / 255
    local max, min = math.max(r, g, b), math.min(r, g, b)
    local h, s
    local l = (max + min) / 2

    if max == min then
        h, s = 0, 0
    else
        local d = max - min
        s = l > 0.5 and d / (2 - max - min) or d / (max + min)
        if max == r then
            h = (g - b) / d + (g < b and 6 or 0)
        elseif max == g then
            h = (b - r) / d + 2
        else
            h = (r - g) / d + 4
        end
        h = h * 60
    end

    return h, s, l
end

local function hue_to_rgb(p, q, t)
    if t < 0 then
        t = t + 1
    end
    if t > 1 then
        t = t - 1
    end
    if t < 1 / 6 then
        return p + (q - p) * 6 * t
    end
    if t < 1 / 2 then
        return q
    end
    if t < 2 / 3 then
        return p + (q - p) * (2 / 3 - t) * 6
    end
    return p
end

---@param h number 0-360
---@param s number 0-1
---@param l number 0-1
---@return number r 0-255
---@return number g 0-255
---@return number b 0-255
function M.hsl_to_rgb(h, s, l)
    h = (h % 360) / 360
    if s == 0 then
        local v = l * 255
        return v, v, v
    end

    local q = l < 0.5 and (l * (1 + s)) or (l + s - l * s)
    local p = 2 * l - q
    local r = hue_to_rgb(p, q, h + 1 / 3)
    local g = hue_to_rgb(p, q, h)
    local b = hue_to_rgb(p, q, h - 1 / 3)

    return r * 255, g * 255, b * 255
end

---Rotate a hex color's hue by a fixed number of degrees, preserving its
---saturation and lightness.
---@param hex string
---@param degrees number
---@return string
function M.rotate_hue(hex, degrees)
    local r, g, b = to_rgb(hex)
    local h, s, l = M.rgb_to_hsl(r, g, b)
    local nr, ng, nb = M.hsl_to_rgb(h + degrees, s, l)
    return to_hex(math.floor(nr + 0.5), math.floor(ng + 0.5), math.floor(nb + 0.5))
end

---Derive a new accent tone that doesn't collide with any of a scheme's
---existing hues, by finding the widest gap on the hue wheel between them and
---placing the new tone at its midpoint (at the average saturation/lightness
---of the inputs). This is a generalization of how base09 (orange) is already
---hand-derived from red/yellow in `osc.lua`.
---
---Falls back to `fallback_hex` (expected to be one of the existing hues
---already in use) when the input hues are too close together or too
---desaturated for a derived tone to read as reliably distinct -- e.g. a
---near-monochrome terminal theme.
---@param hexes string[] existing hues to derive a new tone from (need >= 2)
---@param fallback_hex string color to return if a safe derived tone isn't possible
---@param opts? { min_saturation?: number, min_gap?: number }
---@return string
function M.derive_accent(hexes, fallback_hex, opts)
    opts = opts or {}
    local min_saturation = opts.min_saturation or 0.2
    local min_gap = opts.min_gap or 30

    if #hexes < 2 then
        return fallback_hex
    end

    local hues, sat_sum, light_sum = {}, 0, 0
    for _, hex in ipairs(hexes) do
        local r, g, b = to_rgb(hex)
        local h, s, l = M.rgb_to_hsl(r, g, b)
        table.insert(hues, h)
        sat_sum = sat_sum + s
        light_sum = light_sum + l
    end

    local avg_saturation = sat_sum / #hues
    local avg_lightness = light_sum / #hues
    if avg_saturation < min_saturation then
        return fallback_hex
    end

    table.sort(hues)

    local best_gap, best_mid = -1, nil
    for i, h in ipairs(hues) do
        local nxt = hues[i + 1] or (hues[1] + 360)
        local gap = nxt - h
        if gap > best_gap then
            best_gap = gap
            best_mid = h + gap / 2
        end
    end

    if best_gap < min_gap then
        return fallback_hex
    end

    local r, g, b = M.hsl_to_rgb(best_mid, avg_saturation, avg_lightness)
    return to_hex(math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5))
end

-- : ]]]

function M.assert_property(table, property, error_message)
    if rawget(table, property) == nil then
        error(error_message)
    end
end

---@param color any
---@return boolean
function M.is_hex(color)
    return type(color) == "string" and color:match("^#%x%x%x%x%x%x$") ~= nil
end

---Traverse a dotted path inside a palette table.
---@param palette table
---@param path string Dotted path like "palette.red.normal"
---@return string|nil
function M.lookup(palette, path)
    local cur = palette
    for part in path:gmatch("[^.]+") do
        if type(cur) ~= "table" then
            return nil
        end
        cur = cur[part]
    end
    if type(cur) == "string" then
        return cur
    end
    return nil
end

---Build reverse lookup from hex color to ANSI cterm index.
---The cterm_map keys are canonical palette tree paths (e.g. "palette.red.normal").
---@param palette osc-colors.Palette
---@param cterm_map table<string, integer|nil>
---@return table<string, integer>
function M.build_hex_to_cterm_map(palette, cterm_map)
    local out = {}

    for path, cterm in pairs(cterm_map or {}) do
        if type(cterm) == "number" then
            local color = M.lookup(palette, path)
            if M.is_hex(color) and out[color:lower()] == nil then
                out[color:lower()] = cterm
            end
        end
    end

    return out
end

return M
