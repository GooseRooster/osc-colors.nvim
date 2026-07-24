-- osc-colors never loads a palette by name (that's the whole point of the
-- fork), so unlike tinted-nvim's colors_spec.lua (which tested `resolve()`'s
-- require()-based scheme lookup), this only tests `normalize()`: filling in
-- the derived tinted8 tree + legacy base slots from whatever shape a flat
-- OSC-synthesized palette arrives in.

describe("colors", function()
    local colors

    before_each(function()
        package.loaded["osc-colors.colors"] = nil
        colors = require("osc-colors.colors")
    end)

    local base16_palette = {
        variant = "dark",
        base00 = "#000000",
        base01 = "#111111",
        base02 = "#222222",
        base03 = "#333333",
        base04 = "#444444",
        base05 = "#555555",
        base06 = "#666666",
        base07 = "#777777",
        base08 = "#880000",
        base09 = "#ff9900",
        base0A = "#ffff00",
        base0B = "#00ff00",
        base0C = "#00ffff",
        base0D = "#0000ff",
        base0E = "#ff00ff",
        base0F = "#880000",
    }

    describe("normalize", function()
        it("is a no-op on a table with neither legacy slots nor a tree", function()
            local palette = colors.normalize({ variant = "dark" })

            assert.equal("dark", palette.variant)
            assert.is_nil(palette.base00)
        end)

        it("synthesizes the tinted8 tree from legacy base16 slots", function()
            local palette = colors.normalize(vim.deepcopy(base16_palette))

            assert.is_table(palette.palette)
            assert.is_table(palette.ui)
            assert.is_table(palette.syntax)
            assert.equal("#000000", palette.palette.black.normal)
            assert.equal("#880000", palette.palette.red.normal)
            assert.equal("#555555", palette.palette.white.normal)
        end)

        it("collapses bright to normal for base16 (no base12-17 slots)", function()
            local palette = colors.normalize(vim.deepcopy(base16_palette))

            assert.equal(palette.palette.red.normal, palette.palette.red.bright)
            assert.equal(palette.palette.green.normal, palette.palette.green.bright)
        end)

        it("does not synthesize base10-base17 for base16 shape", function()
            local palette = colors.normalize(vim.deepcopy(base16_palette))

            assert.is_nil(palette.base10)
            assert.is_nil(palette.base12)
        end)

        it("keeps distinct bright colors for base24 shape", function()
            local base24 = vim.tbl_extend("force", vim.deepcopy(base16_palette), {
                base12 = "#ff0000",
                base13 = "#ffff00",
                base14 = "#00ff00",
                base15 = "#00ffff",
                base16 = "#0000ff",
                base17 = "#ff00ff",
            })

            local palette = colors.normalize(base24)

            assert.equal("#ff0000", palette.palette.red.bright)
            assert.equal("#00ff00", palette.palette.green.bright)
            assert.is_string(palette.base10)
        end)

        it("synthesizes legacy slots from a tree-only palette", function()
            local tree_only = {
                variant = "dark",
                palette = {
                    black = { normal = "#000000", bright = "#111111" },
                    gray = { dim = "#222222", normal = "#333333", bright = "#444444" },
                    white = { dim = "#666666", normal = "#555555", bright = "#777777" },
                    red = { normal = "#880000", bright = "#880000" },
                    orange = { normal = "#ff9900", bright = "#ff9900" },
                    yellow = { normal = "#ffff00", bright = "#ffff00" },
                    green = { normal = "#00ff00", bright = "#00ff00" },
                    cyan = { normal = "#00ffff", bright = "#00ffff" },
                    blue = { normal = "#0000ff", bright = "#0000ff" },
                    magenta = { normal = "#ff00ff", bright = "#ff00ff" },
                    brown = { normal = "#880000" },
                },
            }

            local palette = colors.normalize(tree_only)

            assert.equal("#000000", palette.base00)
            assert.equal("#880000", palette.base08)
            assert.equal("#555555", palette.base05)
        end)

        it("never overwrites values already present in the input", function()
            local palette = colors.normalize(vim.tbl_extend("force", vim.deepcopy(base16_palette), {
                base08 = "#deadbe",
            }))

            assert.equal("#deadbe", palette.base08)
            assert.equal("#deadbe", palette.palette.red.normal)
        end)

        it("is idempotent", function()
            local once = colors.normalize(vim.deepcopy(base16_palette))
            local twice = colors.normalize(vim.deepcopy(once))

            assert.equal(once.base00, twice.base00)
            assert.equal(once.palette.red.normal, twice.palette.red.normal)
        end)
    end)
end)
