-- OKLab/OKLCH color math.
--
-- The perceptual foundation for everything osc-colors derives beyond the
-- 16 queried ANSI slots. OKLab is chosen over HSL/Lab because its lightness
-- predictions hold across hues: deriving shades/tints via its L axis stays
-- cohesive instead of producing the yellow-brightening artifacts HSL ramps
-- suffer from. All formulas are Björn Ottosson's reference implementation
-- (https://bottosson.github.io/posts/oklab/), sRGB-gamut only.

local M = {}

local CUBE_3 = 1 / 3

-- LuaJIT's math.atan takes a single argument (no atan2 form), so angles in
-- the left half-plane need manual quadrant correction.
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

-- : sRGB <-> linear [[[
--
-- https://en.wikipedia.org/wiki/SRGB#Transfer_function

local function srgb_channel_to_linear(v)
    -- v in 0..255
    local c = v / 255
    if c <= 0.04045 then
        return c / 12.92
    end
    return ((c + 0.055) / 1.055) ^ 2.4
end

local function linear_channel_to_srgb(c)
    if c <= 0.0031308 then
        return 12.92 * c
    end
    return 1.055 * c ^ (1 / 2.4) - 0.055
end

-- : ]]]

-- : hex <-> OKLab [[[
--
-- Intermediate long-form LMS cube roots keep the matrices exactly as
-- published; everything here is deterministic float math.

local function hex_to_linear(hex)
    local r = srgb_channel_to_linear(tonumber(hex:sub(2, 3), 16))
    local g = srgb_channel_to_linear(tonumber(hex:sub(4, 5), 16))
    local b = srgb_channel_to_linear(tonumber(hex:sub(6, 7), 16))
    return r, g, b
end

---Convert `#rrggbb` to OKLab. Returns L (0-1), a, b (roughly -0.4..0.4).
---@param hex string
---@return number L
---@return number a
---@return number b
function M.hex_to_oklab(hex)
    local r, g, b = hex_to_linear(hex)
    local l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    local m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    local s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    local l_ = l ^ CUBE_3
    local m_ = m ^ CUBE_3
    local s_ = s ^ CUBE_3
    return 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        1.9779984951 * l_ - 2.4285932050 * m_ + 0.4505937099 * s_,
        0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_
end

---Convert OKLab to `#rrggbb`, clamping into the sRGB gamut.
---@param L number 0-1
---@param a number
---@param b number
---@return string hex
function M.oklab_to_hex(L, a, b)
    local l_ = L + 0.3963377774 * a + 0.2158037573 * b
    local m_ = L - 0.1055613458 * a - 0.0638541728 * b
    local s_ = L - 0.0894841775 * a - 1.2914855480 * b
    local l = l_ ^ 3
    local m = m_ ^ 3
    local s = s_ ^ 3
    local r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    local g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    local b2 = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

    local function to255(c)
        if c < 0 then
            c = 0
        elseif c > 1 then
            c = 1
        end
        return math.floor(linear_channel_to_srgb(c) * 255 + 0.5)
    end

    return string.format("#%02x%02x%02x", to255(r), to255(g), to255(b2))
end

-- : ]]]

-- : OKLCH [[[
--
-- Cylindrical OKLab: L (lightness, 0-1), C (chroma, >= 0), H (hue, degrees
-- 0-360; undefined/0 for achromatic colors).

---Convert `#rrggbb` to OKLCH.
---@param hex string
---@return number L 0-1
---@return number C >= 0
---@return number H degrees, 0-360
function M.hex_to_oklch(hex)
    local L, a, b = M.hex_to_oklab(hex)
    local C = math.sqrt(a * a + b * b)
    local H = math.deg(atan2(b, a)) % 360
    return L, C, H
end

---True when the OKLCH color is inside the sRGB gamut. A small epsilon
---absorbs float drift for colors reconstructed *from* hex (a pure blue
---sits exactly on the boundary and would otherwise flunk its own
---round-trip); oklab_to_hex clamps residual overshoot per channel anyway.
local GAMUT_EPS = 1e-4

function M.in_gamut(L, C, H)
    local h = math.rad(H)
    local a = C * math.cos(h)
    local b = C * math.sin(h)
    local l_ = L + 0.3963377774 * a + 0.2158037573 * b
    local m_ = L - 0.1055613458 * a - 0.0638541728 * b
    local s_ = L - 0.0894841775 * a - 1.2914855480 * b
    local l, m, s = l_ ^ 3, m_ ^ 3, s_ ^ 3
    local r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    local g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    local b2 = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    return r >= -GAMUT_EPS
        and r <= 1 + GAMUT_EPS
        and g >= -GAMUT_EPS
        and g <= 1 + GAMUT_EPS
        and b2 >= -GAMUT_EPS
        and b2 <= 1 + GAMUT_EPS
end

---Reduce chroma (binary search) until the color is in the sRGB gamut, and
---return the adjusted hex. Chroma is preserved when already in gamut.
---@param L number 0-1
---@param C number
---@param H number degrees
---@return string hex
function M.oklch_to_hex(L, C, H)
    if C <= 0 or M.in_gamut(L, C, H) then
        local h = math.rad(H)
        return M.oklab_to_hex(L, C * math.cos(h), C * math.sin(h))
    end
    local lo, hi = 0, C
    for _ = 1, 24 do
        local mid = (lo + hi) / 2
        if M.in_gamut(L, mid, H) then
            lo = mid
        else
            hi = mid
        end
    end
    local h = math.rad(H)
    return M.oklab_to_hex(L, lo * math.cos(h), lo * math.sin(h))
end

-- : ]]]

-- : Difference & contrast [[[
--
-- OKLab Euclidean distance is a solid perceptual ΔE for palette work;
-- WCAG relative-luminance contrast is kept for accessibility targets on
-- text-vs-background roles.

---Perceptual distance between two hex colors (0 = identical).
function M.delta_e(hex_a, hex_b)
    local l1, a1, b1 = M.hex_to_oklab(hex_a)
    local l2, a2, b2 = M.hex_to_oklab(hex_b)
    return math.sqrt((l1 - l2) ^ 2 + (a1 - a2) ^ 2 + (b1 - b2) ^ 2)
end

---WCAG relative luminance of a hex color (0-1).
function M.luminance(hex)
    local r = srgb_channel_to_linear(tonumber(hex:sub(2, 3), 16))
    local g = srgb_channel_to_linear(tonumber(hex:sub(4, 5), 16))
    local b = srgb_channel_to_linear(tonumber(hex:sub(6, 7), 16))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
end

---WCAG contrast ratio between two hex colors (1-21).
function M.contrast(hex_a, hex_b)
    local la, lb = M.luminance(hex_a), M.luminance(hex_b)
    if la < lb then
        la, lb = lb, la
    end
    return (la + 0.05) / (lb + 0.05)
end

-- : ]]]

return M
