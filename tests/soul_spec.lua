describe("soul", function()
    local soul
    local oklch

    before_each(function()
        soul = require("osc-colors.soul")
        oklch = require("osc-colors.oklch")
    end)

    -- Gruvbox-flavored: warm hues, dark background
    local warm_dark = {
        base00 = "#282828",
        base07 = "#ebdbb2",
        base08 = "#fb4934", -- red ~29deg
        base09 = "#fe8019", -- orange
        base0A = "#fabd2f", -- yellow
        base0B = "#b8bb26", -- green
        base0C = "#8ec07c", -- aqua
        base0D = "#83a598", -- blue
        base0E = "#d3869b", -- purple
        base0F = "#d65d0e",
    }

    -- Nord-flavored: cool hues, muted chroma
    local cool_muted = {
        base00 = "#2e3440",
        base07 = "#eceff4",
        base08 = "#bf616a", -- red
        base09 = "#d08770", -- orange
        base0A = "#ebcb8b", -- yellow
        base0B = "#a3be8c", -- green
        base0C = "#88c0d0", -- cyan
        base0D = "#81a1c1", -- blue
        base0E = "#b48ead", -- magenta
        base0F = "#a3be8c",
    }

    local monochrome = {
        base00 = "#111111",
        base07 = "#dddddd",
        base08 = "#666666",
        base09 = "#777777",
        base0A = "#888888",
        base0B = "#999999",
        base0C = "#aaaaaa",
        base0D = "#bbbbbb",
        base0E = "#cccccc",
        base0F = "#555555",
    }

    describe("extract", function()
        it("computes the circular hue mean without ring wraparound nonsense", function()
            local s = soul.extract(warm_dark)
            -- gruvbox hues: red 29, orange ~41, yellow ~90, green ~100,
            -- aqua ~130, blue ~250, purple ~330 -- chroma-weighted mass
            -- should sit in the warm arc, nowhere near 180 or 240
            assert.is_true(s.hue_mean < 140 or s.hue_mean > 300, "hue mean should be warm-ish, got " .. s.hue_mean)
            assert.is_true(s.hue_kappa > 0, "kappa should be positive for a colorful scheme")
        end)

        it("detects warm vs cool bias", function()
            local warm = soul.extract(warm_dark)
            local cool = soul.extract(cool_muted)
            assert.is_true(warm.warm_bias > cool.warm_bias, "gruvbox-ish should lean warmer than nord-ish")
        end)

        it("flags achromatic souls", function()
            local s = soul.extract(monochrome)
            assert.is_true(s.achromatic)
            assert.is_true(s.chroma_max < 0.01)
        end)

        it("records the lightness envelope", function()
            local s = soul.extract(warm_dark)
            local bg_L = select(1, oklch.hex_to_oklch("#282828"))
            local fg_L = select(1, oklch.hex_to_oklch("#ebdbb2"))
            assert.is_true(math.abs(s.bg_L - bg_L) < 1e-9)
            assert.is_true(math.abs(s.fg_L - fg_L) < 1e-9)
        end)

        it("is deterministic for the same input", function()
            local a = soul.extract(warm_dark)
            local b = soul.extract(warm_dark)
            assert.equal(a.hue_mean, b.hue_mean)
            assert.equal(a.hue_kappa, b.hue_kappa)
            assert.equal(a.warm_bias, b.warm_bias)
        end)

        it("handles antipodal hues without NaN", function()
            -- two anchors on opposite sides of the wheel: kappa ~ 0
            local s = soul.extract({
                base00 = "#000000",
                base07 = "#ffffff",
                base08 = "#ff0000",
                base09 = "#ff0000",
                base0A = "#00ff00",
                base0B = "#00ffff",
                base0C = "#00ffff",
                base0D = "#0000ff",
                base0E = "#ff0000",
                base0F = "#ff00ff",
            })
            assert.is_number(s.hue_mean)
            assert.is_false(s.hue_mean ~= s.hue_mean, "hue mean must not be NaN")
            assert.is_number(s.hue_kappa)
            assert.is_true(s.hue_kappa < 0.7, "antipodal hues should yield low concentration")
        end)
    end)

    describe("sector_hue", function()
        it("keeps an anchor hue that already lives in the sector", function()
            local s = soul.extract(warm_dark)
            local red_hue = select(3, oklch.hex_to_oklch("#fb4934")) -- ~29deg
            local hue = soul.sector_hue(s, "base08", { 0, 40 })
            assert.is_true(math.abs(hue - red_hue) < 1.0)
        end)

        it("clamps an off-sector anchor to the nearest sector edge", function()
            -- a theme whose "red" anchor is actually cyan (H~201): nearest
            -- edge is the *low* one, through the wraparound
            local s = soul.extract({
                base00 = "#000000",
                base07 = "#ffffff",
                base08 = "#00c8d2", -- cyan-ish "red"
                base09 = "#00c8d2",
                base0A = "#00c8d2",
                base0B = "#00c8d2",
                base0C = "#00c8d2",
                base0D = "#00c8d2",
                base0E = "#00c8d2",
                base0F = "#00c8d2",
            })
            local hue = soul.sector_hue(s, "base08", { 0, 40 })
            assert.equal(0, hue) -- nearest edge via wraparound

            -- a green anchor (H~100) is nearest the *high* edge
            local green = oklch.oklch_to_hex(0.7, 0.15, 100)
            local s2 = soul.extract({
                base00 = "#000000",
                base07 = "#ffffff",
                base08 = green,
                base09 = green,
                base0A = green,
                base0B = green,
                base0C = green,
                base0D = green,
                base0E = green,
                base0F = green,
            })
            assert.equal(40, soul.sector_hue(s2, "base08", { 0, 40 }))
        end)

        it("falls back to the sector midpoint when the anchor is missing", function()
            local s = soul.extract({ base00 = "#000000", base07 = "#ffffff" })
            local hue = soul.sector_hue(s, "base08", { 0, 40 })
            assert.equal(20, hue)
        end)
    end)
end)
