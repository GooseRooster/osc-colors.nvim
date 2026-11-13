describe("soul", function()
    local soul
    local oklch
    local fx = dofile("tests/fixtures/schemes.lua")

    before_each(function()
        soul = require("osc-colors.soul")
        oklch = require("osc-colors.oklch")
    end)

    local function scheme(name, opts)
        return fx.to_palette(fx.schemes[name], opts)
    end

    local function names_of(list)
        local out = {}
        for _, f in ipairs(list) do
            table.insert(out, f.name)
        end
        return out
    end

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
        it("builds one family per chromatic ANSI hue", function()
            local s = soul.extract(scheme("onedark"))
            assert.same({ "red", "green", "yellow", "blue", "magenta", "cyan" }, names_of(s.families))
            assert.equal(6, #s.ranked)
            assert.is_false(s.achromatic)
        end)

        it("ranks families by salience, most characteristic first", function()
            local s = soul.extract(scheme("gruvbox"))
            for i = 2, #s.ranked do
                assert.is_true(s.ranked[i - 1].salience >= s.ranked[i].salience)
            end
            assert.equal(s.ranked[1], s.dominant)
            assert.equal(s.dominant.H, s.dominant_hue)
        end)

        it("judges vividness against the gamut, not raw chroma", function()
            -- gruvbox's red has the highest raw OKLCH chroma, but its yellow
            -- and green sit far closer to their (much lower) gamut ceilings
            local s = soul.extract(scheme("gruvbox"))
            local red, yellow = soul.family(s, "red"), soul.family(s, "yellow")
            assert.is_true(red.C > yellow.C)
            assert.is_true(yellow.rel > red.rel)
            -- and the muted blue is not where gruvbox's soul lives
            assert.is_true(soul.family(s, "blue").salience < yellow.salience)
        end)

        it("treats a same-hue bright as a shade of its family", function()
            local s = soul.extract(scheme("dracula"))
            local red = soul.family(s, "red")
            assert.is_table(red.shade)
            assert.equal("#ff6e6e", red.shade.hex)
            assert.equal(6, #s.families)
        end)

        it("promotes a bright with its own hue to a family of its own", function()
            -- solarized's bright red is its orange and bright magenta its
            -- violet; its other brights are grays and stay out entirely
            local s = soul.extract(scheme("solarized"))
            assert.is_table(soul.family(s, "bright_red"))
            assert.is_table(soul.family(s, "bright_magenta"))
            assert.is_nil(soul.family(s, "bright_green"))
            assert.is_nil(soul.family(s, "bright_blue"))
        end)

        it("works without brights (pre-v3 cache)", function()
            local s = soul.extract(scheme("solarized", { brights = false }))
            assert.equal(6, #s.families)
            assert.is_nil(soul.family(s, "bright_red"))
        end)

        it("reads base24 bright slots when no OSC brights are present", function()
            local p = scheme("dracula", { brights = false })
            p.base12 = "#ff6e6e"
            local s = soul.extract(p)
            assert.equal("#ff6e6e", soul.family(s, "red").shade.hex)
        end)

        it("folds near-identical colors into one family", function()
            local p = scheme("onedark", { brights = false })
            p.base0C = "#e06d76" -- "cyan" that is really the same red
            local s = soul.extract(p)
            assert.equal(5, #s.families)
            local red = soul.family(s, "red")
            assert.equal(red, soul.family(s, "cyan"))
        end)

        it("keeps gray anchors out of the family set", function()
            local p = scheme("nord", { brights = false })
            p.base0E = "#888888"
            local s = soul.extract(p)
            assert.is_nil(soul.family(s, "magenta"))
            assert.equal(6, #s.anchors)
        end)

        it("lets a chromatic bright carry a family whose normal is gray", function()
            local p = scheme("onedark")
            p.base0E = "#888888"
            local s = soul.extract(p)
            assert.equal("#c678dd", soul.family(s, "magenta").hex)
        end)

        it("flags achromatic souls", function()
            local s = soul.extract(monochrome)
            assert.is_true(s.achromatic)
            assert.equal(0, #s.families)
            assert.is_nil(s.dominant)
            assert.equal(0, s.chroma_max)
        end)

        it("records the lightness envelope", function()
            local p = scheme("gruvbox")
            local s = soul.extract(p)
            assert.is_true(math.abs(s.bg_L - select(1, oklch.hex_to_oklch(p.base00))) < 1e-9)
            assert.is_true(math.abs(s.fg_L - select(1, oklch.hex_to_oklch(p.base07))) < 1e-9)
            assert.equal("dark", s.variant)
            assert.equal("light", soul.extract(scheme("github_light")).variant)
        end)

        it("is deterministic for the same input", function()
            local a = soul.extract(scheme("kanagawa"))
            local b = soul.extract(scheme("kanagawa"))
            assert.same(names_of(a.ranked), names_of(b.ranked))
            for i, f in ipairs(a.ranked) do
                assert.equal(f.salience, b.ranked[i].salience)
            end
        end)

        it("falls back to tree paths for tree-only palettes", function()
            local colors = require("osc-colors.colors")
            local p = colors.normalize(scheme("nord"))
            p.base08 = nil
            local s = soul.extract(p)
            assert.is_table(soul.family(s, "red"))
        end)
    end)

    describe("sector_color", function()
        it("keeps the source color when it already lives in the sector", function()
            local s = soul.extract(scheme("gruvbox"))
            local pick = soul.sector_color(s, "red", { 0, 40 })
            local red = soul.family(s, "red")
            assert.equal(red, pick.family)
            assert.equal(red.H, pick.H)
            assert.equal(red.L, pick.L)
        end)

        it("clamps a source just outside the sector to the nearest edge", function()
            -- xterm blue (~264deg) is just past the info sector's 250 edge
            local s = soul.extract(scheme("xterm"))
            local pick = soul.sector_color(s, "blue", { 190, 250 })
            assert.equal("blue", pick.family.name)
            assert.equal(250, pick.H)
        end)

        it("clamps through the wraparound", function()
            local p = scheme("onedark")
            p.base08 = oklch.oklch_to_hex(0.65, 0.15, 350)
            local s = soul.extract(p)
            assert.equal(0, soul.sector_color(s, "red", { 0, 40 }).H)
        end)

        it("borrows the scheme's own in-sector color when the source is far off", function()
            -- a "red" that is really blue: the scheme's actual red-sector
            -- color (its magenta-ish pink) is borrowed instead
            local p = scheme("onedark")
            p.base08 = "#3070ff"
            p.base0E = oklch.oklch_to_hex(0.7, 0.15, 20)
            local s = soul.extract(p)
            local pick = soul.sector_color(s, "red", { 0, 40 })
            assert.equal("magenta", pick.family.name)
        end)

        it("skips families already taken by other semantic roles", function()
            local p = scheme("onedark")
            p.base08 = "#3070ff"
            p.base0E = oklch.oklch_to_hex(0.7, 0.15, 20)
            local s = soul.extract(p)
            local taken = { [soul.family(s, "magenta")] = true }
            local pick = soul.sector_color(s, "red", { 0, 40 }, taken)
            assert.are_not.equal("magenta", pick.family.name)
            assert.is_true(pick.H >= 0 and pick.H <= 40)
        end)

        it("returns nil for an achromatic soul", function()
            assert.is_nil(soul.sector_color(soul.extract(monochrome), "red", { 0, 40 }))
        end)
    end)
end)
