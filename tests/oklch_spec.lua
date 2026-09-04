describe("oklch", function()
    local oklch

    before_each(function()
        oklch = require("osc-colors.oklch")
    end)

    local function approx(actual, expected, tol, label)
        assert.is_true(
            math.abs(actual - expected) <= (tol or 0.001),
            string.format("%s: expected %s +/- %s, got %s", label or "value", expected, tol or 0.001, actual)
        )
    end

    describe("hex_to_oklch", function()
        it("maps white to L=1, C=0", function()
            local L, C = oklch.hex_to_oklch("#ffffff")
            approx(L, 1.0)
            approx(C, 0.0)
        end)

        it("maps black to L=0, C=0", function()
            local L, C = oklch.hex_to_oklch("#000000")
            approx(L, 0.0)
            approx(C, 0.0)
        end)

        it("matches published reference values for pure red", function()
            -- Björn Ottosson's published OKLCH for #ff0000:
            -- L=0.6279, C=0.2577, H=29.23
            local L, C, H = oklch.hex_to_oklch("#ff0000")
            approx(L, 0.6279, 0.01)
            approx(C, 0.2577, 0.01)
            approx(H, 29.23, 0.5)
        end)

        it("orders grays monotonically by lightness", function()
            local prev = -1
            for _, hex in ipairs({ "#111111", "#444444", "#888888", "#cccccc" }) do
                local L = oklch.hex_to_oklch(hex)
                assert.is_true(L > prev, "lightness should increase across " .. hex)
                prev = L
            end
        end)

        it("gives achromatic colors a zero chroma", function()
            local _, C = oklch.hex_to_oklch("#808080")
            approx(C, 0.0)
        end)
    end)

    describe("oklch_to_hex", function()
        it("round-trips arbitrary in-gamut colors", function()
            for _, hex in ipairs({
                "#000000",
                "#1a1a1a",
                "#ff0000",
                "#00ff00",
                "#0000ff",
                "#ffff00",
                "#ff00ff",
                "#00ffff",
                "#fe8019",
                "#8ec07c",
                "#83a598",
                "#b8bb26",
                "#fabd2f",
            }) do
                local L, C, H = oklch.hex_to_oklch(hex)
                local back = oklch.oklch_to_hex(L, C, H)
                local max_delta = 0
                for i = 2, 7, 2 do
                    local d = math.abs(tonumber(back:sub(i, i + 1), 16) - tonumber(hex:sub(i, i + 1), 16))
                    if d > max_delta then
                        max_delta = d
                    end
                end
                -- full float round-trips drift a couple of 8-bit steps on
                -- near-zero channels; anything larger is a real bug
                assert.is_true(max_delta <= 2, string.format("round-trip of %s gave %s", hex, back))
            end
        end)

        it("clamps out-of-gamut chroma instead of wrapping", function()
            -- Deep chroma at a hue where sRGB can't represent it
            local hex = oklch.oklch_to_hex(0.5, 0.4, 30)
            local L, C = oklch.hex_to_oklch(hex)
            assert.is_true(C < 0.4, "chroma should have been reduced")
            assert.is_true(oklch.in_gamut(L, C, oklch.hex_to_oklch(hex)))
        end)

        it("keeps lightness when clamping chroma", function()
            local hex = oklch.oklch_to_hex(0.7, 0.5, 140)
            local L = oklch.hex_to_oklch(hex)
            approx(L, 0.7, 0.02)
        end)

        it("handles achromatic input (C=0) at any hue", function()
            -- hue is meaningless at C=0; the result must be the same gray
            -- regardless, and lightness must be preserved
            local a = oklch.oklch_to_hex(0.5, 0, 137)
            local b = oklch.oklch_to_hex(0.5, 0, 300)
            assert.equal(a, b)
            approx(oklch.hex_to_oklch(a), 0.5, 0.005)
            -- all channels identical
            assert.equal(a:sub(2, 3), a:sub(4, 5))
            assert.equal(a:sub(4, 5), a:sub(6, 7))
        end)
    end)

    describe("delta_e", function()
        it("is zero for identical colors", function()
            approx(oklch.delta_e("#ff0000", "#ff0000"), 0.0, 1e-9)
        end)

        it("separates red from green more than red from orange", function()
            local far = oklch.delta_e("#ff0000", "#00ff00")
            local near = oklch.delta_e("#ff0000", "#ff8000")
            assert.is_true(far > near)
        end)

        it("treats two grays of similar lightness as close", function()
            assert.is_true(oklch.delta_e("#808080", "#888888") < 0.05)
        end)
    end)

    describe("contrast", function()
        it("gives black/white the maximum 21:1 ratio", function()
            approx(oklch.contrast("#000000", "#ffffff"), 21.0, 0.01)
        end)

        it("is 1 for identical colors", function()
            approx(oklch.contrast("#123456", "#123456"), 1.0, 1e-9)
        end)

        it("is symmetric", function()
            approx(oklch.contrast("#ff0000", "#000000"), oklch.contrast("#000000", "#ff0000"), 1e-9)
        end)
    end)

    describe("in_gamut", function()
        it("accepts ordinary colors", function()
            assert.is_true(oklch.in_gamut(0.5, 0.1, 30))
        end)

        it("rejects impossible chroma", function()
            assert.is_false(oklch.in_gamut(0.5, 0.5, 30))
        end)
    end)
end)
