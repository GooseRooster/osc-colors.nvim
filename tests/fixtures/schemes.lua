-- Reference terminal schemes for soul-mapping tests: bg, fg, ANSI 1-6
-- (red, green, yellow, blue, magenta, cyan) and their ANSI 9-14 brights,
-- exactly as a terminal would answer OSC 10/11/4.
--
-- `to_palette` mirrors osc.lua's synthesize(): the gray ramp, orange and
-- brown are interpolated, brights ride along under `brights`.

local M = {}

M.schemes = {
    gruvbox = {
        bg = "#282828",
        fg = "#ebdbb2",
        normal = { "#cc241d", "#98971a", "#d79921", "#458588", "#b16286", "#689d6a" },
        bright = { "#fb4934", "#b8bb26", "#fabd2f", "#83a598", "#d3869b", "#8ec07c" },
    },
    nord = {
        bg = "#2e3440",
        fg = "#d8dee9",
        normal = { "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#88c0d0" },
        bright = { "#bf616a", "#a3be8c", "#ebcb8b", "#81a1c1", "#b48ead", "#8fbcbb" },
    },
    dracula = {
        bg = "#282a36",
        fg = "#f8f8f2",
        normal = { "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd" },
        bright = { "#ff6e6e", "#69ff94", "#ffffa5", "#d6acff", "#ff92df", "#a4ffff" },
    },
    tokyonight = {
        bg = "#1a1b26",
        fg = "#c0caf5",
        normal = { "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff" },
        bright = { "#f7768e", "#9ece6a", "#e0af68", "#7aa2f7", "#bb9af7", "#7dcfff" },
    },
    catppuccin = {
        bg = "#1e1e2e",
        fg = "#cdd6f4",
        normal = { "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5" },
        bright = { "#f38ba8", "#a6e3a1", "#f9e2af", "#89b4fa", "#f5c2e7", "#94e2d5" },
    },
    solarized = {
        bg = "#002b36",
        fg = "#839496",
        normal = { "#dc322f", "#859900", "#b58900", "#268bd2", "#d33682", "#2aa198" },
        -- solarized's brights are its orange, its base tones, and its violet
        bright = { "#cb4b16", "#586e75", "#657b83", "#839496", "#6c71c4", "#93a1a1" },
    },
    everforest = {
        bg = "#2d353b",
        fg = "#d3c6aa",
        normal = { "#e67e80", "#a7c080", "#dbbc7f", "#7fbbb3", "#d699b6", "#83c092" },
        bright = { "#e67e80", "#a7c080", "#dbbc7f", "#7fbbb3", "#d699b6", "#83c092" },
    },
    kanagawa = {
        bg = "#1f1f28",
        fg = "#dcd7ba",
        normal = { "#c34043", "#76946a", "#c0a36e", "#7e9cd8", "#957fb8", "#6a9589" },
        bright = { "#e82424", "#98bb6c", "#e6c384", "#7fb4ca", "#938aa9", "#7aa89f" },
    },
    rosepine = {
        bg = "#191724",
        fg = "#e0def4",
        normal = { "#eb6f92", "#31748f", "#f6c177", "#9ccfd8", "#c4a7e7", "#ebbcba" },
        bright = { "#eb6f92", "#31748f", "#f6c177", "#9ccfd8", "#c4a7e7", "#ebbcba" },
    },
    onedark = {
        bg = "#282c34",
        fg = "#abb2bf",
        normal = { "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2" },
        bright = { "#e06c75", "#98c379", "#e5c07b", "#61afef", "#c678dd", "#56b6c2" },
    },
    xterm = {
        bg = "#000000",
        fg = "#e5e5e5",
        normal = { "#cd0000", "#00cd00", "#cdcd00", "#0000ee", "#cd00cd", "#00cdcd" },
        bright = { "#ff0000", "#00ff00", "#ffff00", "#5c5cff", "#ff00ff", "#00ffff" },
    },
    github_light = {
        bg = "#ffffff",
        fg = "#24292f",
        normal = { "#cf222e", "#116329", "#4d2d00", "#0969da", "#8250df", "#1b7c83" },
        bright = { "#a40e26", "#1a7f37", "#633c01", "#218bff", "#a475f9", "#3192aa" },
    },
}

local function hex_to_rgb(hex)
    return tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
end

local function lerp(a, b, t)
    local r1, g1, b1 = hex_to_rgb(a)
    local r2, g2, b2 = hex_to_rgb(b)
    return string.format(
        "#%02x%02x%02x",
        math.floor(r1 + (r2 - r1) * t + 0.5),
        math.floor(g1 + (g2 - g1) * t + 0.5),
        math.floor(b1 + (b2 - b1) * t + 0.5)
    )
end

local NAMES = { "red", "green", "yellow", "blue", "magenta", "cyan" }

---Build an osc.lua-shaped palette from a scheme entry.
---@param s table entry of M.schemes
---@param opts? { brights?: boolean, tier?: string }
function M.to_palette(s, opts)
    opts = opts or {}
    local n = s.normal
    local r, g, y, b, m, c = n[1], n[2], n[3], n[4], n[5], n[6]
    local r1, g1, b1 = hex_to_rgb(s.bg)
    local p = {
        variant = (0.299 * r1 + 0.587 * g1 + 0.114 * b1 < 128) and "dark" or "light",
        base00 = s.bg,
        base07 = s.fg,
        base08 = r,
        base09 = lerp(r, y, 0.4),
        base0A = y,
        base0B = g,
        base0C = c,
        base0D = b,
        base0E = m,
        base0F = lerp(r, s.bg, 0.3),
        capability = { tier = opts.tier or "truecolor" },
    }
    for i = 1, 6 do
        p[string.format("base%02X", i)] = lerp(s.bg, s.fg, i / 7)
    end
    if opts.brights ~= false and s.bright then
        p.brights = {}
        for i, name in ipairs(NAMES) do
            p.brights[name] = s.bright[i]
        end
    end
    return p
end

---Sorted scheme names, for deterministic iteration.
function M.names()
    local names = {}
    for k in pairs(M.schemes) do
        table.insert(names, k)
    end
    table.sort(names)
    return names
end

return M
