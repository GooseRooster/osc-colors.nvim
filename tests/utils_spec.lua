describe("utils", function()
    local utils

    before_each(function()
        package.loaded["osc-colors.utils"] = nil
        utils = require("osc-colors.utils")
    end)

    describe("blend", function()
        it("blends two colors with 0 amount (returns fg)", function()
            local result = utils.blend("#ff0000", "#0000ff", 0)

            assert.equal("#ff0000", result)
        end)

        it("blends two colors with 1 amount (returns bg)", function()
            local result = utils.blend("#ff0000", "#0000ff", 1)

            assert.equal("#0000ff", result)
        end)

        it("blends two colors with 0.5 amount", function()
            local result = utils.blend("#ff0000", "#0000ff", 0.5)

            assert.equal("#800080", result)
        end)

        it("blends black and white", function()
            local result = utils.blend("#000000", "#ffffff", 0.5)

            assert.equal("#808080", result)
        end)

        it("returns NONE when fg is none", function()
            local result = utils.blend("none", "#000000", 0.5)

            assert.equal("NONE", result)
        end)

        it("returns NONE when fg is NONE (uppercase)", function()
            local result = utils.blend("NONE", "#000000", 0.5)

            assert.equal("NONE", result)
        end)

        it("returns fg when bg is none", function()
            local result = utils.blend("#ff0000", "none", 0.5)

            assert.equal("#ff0000", result)
        end)

        it("clamps amount below 0", function()
            local result = utils.blend("#ff0000", "#0000ff", -1)

            assert.equal("#ff0000", result)
        end)

        it("clamps amount above 1", function()
            local result = utils.blend("#ff0000", "#0000ff", 2)

            assert.equal("#0000ff", result)
        end)

        it("handles nil amount as 0", function()
            local result = utils.blend("#ff0000", "#0000ff", nil)

            assert.equal("#ff0000", result)
        end)
    end)

    describe("darken", function()
        it("darkens a color by blending with background", function()
            local result = utils.darken("#ffffff", 0.5, "#000000")

            assert.equal("#808080", result)
        end)

        it("returns original with 0 amount", function()
            local result = utils.darken("#ff0000", 0, "#000000")

            assert.equal("#ff0000", result)
        end)

        it("returns background with 1 amount", function()
            local result = utils.darken("#ff0000", 1, "#000000")

            assert.equal("#000000", result)
        end)
    end)

    describe("lighten", function()
        it("lightens a color by blending with foreground", function()
            local result = utils.lighten("#000000", 0.5, "#ffffff")

            assert.equal("#808080", result)
        end)

        it("returns original with 0 amount", function()
            local result = utils.lighten("#ff0000", 0, "#ffffff")

            assert.equal("#ff0000", result)
        end)

        it("returns foreground with 1 amount", function()
            local result = utils.lighten("#ff0000", 1, "#ffffff")

            assert.equal("#ffffff", result)
        end)
    end)

    describe("rgb_to_hsl / hsl_to_rgb", function()
        it("converts pure red to hsl", function()
            local h, s, l = utils.rgb_to_hsl(255, 0, 0)

            assert.near(0, h, 0.01)
            assert.near(1, s, 0.01)
            assert.near(0.5, l, 0.01)
        end)

        it("converts pure green to hsl", function()
            local h = utils.rgb_to_hsl(0, 255, 0)

            assert.near(120, h, 0.01)
        end)

        it("converts pure blue to hsl", function()
            local h = utils.rgb_to_hsl(0, 0, 255)

            assert.near(240, h, 0.01)
        end)

        it("converts grayscale to zero saturation", function()
            local _, s = utils.rgb_to_hsl(128, 128, 128)

            assert.equal(0, s)
        end)

        it("round-trips rgb -> hsl -> rgb", function()
            local r, g, b = utils.hsl_to_rgb(utils.rgb_to_hsl(200, 80, 40))

            assert.near(200, r, 1)
            assert.near(80, g, 1)
            assert.near(40, b, 1)
        end)

        it("hsl_to_rgb produces gray when saturation is 0", function()
            local r, g, b = utils.hsl_to_rgb(120, 0, 0.5)

            assert.near(r, g, 0.01)
            assert.near(g, b, 0.01)
        end)
    end)

    describe("rotate_hue", function()
        it("rotates red toward green by 120 degrees", function()
            local result = utils.rotate_hue("#ff0000", 120)

            assert.equal("#00ff00", result)
        end)

        it("wraps around 360 degrees back to the original color", function()
            local result = utils.rotate_hue("#ff0000", 360)

            assert.equal("#ff0000", result)
        end)

        it("preserves saturation/lightness, only changing hue", function()
            local rotated = utils.rotate_hue("#3355aa", 45)
            local before_h, before_s, before_l = utils.rgb_to_hsl(0x33, 0x55, 0xaa)
            local r = tonumber(rotated:sub(2, 3), 16)
            local g = tonumber(rotated:sub(4, 5), 16)
            local b = tonumber(rotated:sub(6, 7), 16)
            local after_h, after_s, after_l = utils.rgb_to_hsl(r, g, b)

            assert.near((before_h + 45) % 360, after_h, 0.5)
            assert.near(before_s, after_s, 0.01)
            assert.near(before_l, after_l, 0.01)
        end)
    end)

    describe("derive_accent", function()
        local function hex_to_hsl(hex)
            local r = tonumber(hex:sub(2, 3), 16)
            local g = tonumber(hex:sub(4, 5), 16)
            local b = tonumber(hex:sub(6, 7), 16)
            return utils.rgb_to_hsl(r, g, b)
        end

        it("derives a tone in the widest gap between hues", function()
            -- red (0), green (120), blue (240) -- three equal gaps of 120;
            -- the derived tone should land at one of the gap midpoints
            -- (60/180/300, i.e. yellow/cyan/magenta-ish).
            local result = utils.derive_accent({ "#ff0000", "#00ff00", "#0000ff" }, "#ffffff")
            local h = hex_to_hsl(result)

            assert.not_equal("#ffffff", result)
            local matches_a_gap_midpoint = math.abs(h - 60) < 1 or math.abs(h - 180) < 1 or math.abs(h - 300) < 1
            assert.is_true(matches_a_gap_midpoint)
        end)

        it("does not fall back for two close hues (the opposite side of the wheel is still a wide gap)", function()
            local result = utils.derive_accent({ "#ff0000", "#ff1010" }, "#ffffff")

            assert.not_equal("#ffffff", result)
        end)

        it("falls back when hues evenly saturate the wheel and leave no wide gap", function()
            local hues = {}
            for i = 0, 17 do
                -- 18 hues 20 degrees apart -- no gap wider than the 30-degree
                -- min_gap default, so a distinct new tone can't be placed.
                local r, g, b = utils.hsl_to_rgb(i * 20, 0.8, 0.5)
                table.insert(
                    hues,
                    string.format("#%02x%02x%02x", math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5))
                )
            end
            local result = utils.derive_accent(hues, "#ffffff")

            assert.equal("#ffffff", result)
        end)

        it("falls back when saturation is too low (near-monochrome scheme)", function()
            local result = utils.derive_accent({ "#888888", "#8a8a8a", "#868686" }, "#ffffff")

            assert.equal("#ffffff", result)
        end)

        it("falls back with fewer than 2 input hues", function()
            local result = utils.derive_accent({ "#ff0000" }, "#ffffff")

            assert.equal("#ffffff", result)
        end)

        it("is deterministic for the same input", function()
            local hues = { "#ff0000", "#ffff00", "#00ff00", "#00ffff", "#0000ff", "#ff00ff" }
            local first = utils.derive_accent(hues, "#ffffff")
            local second = utils.derive_accent(hues, "#ffffff")

            assert.equal(first, second)
        end)
    end)
end)
