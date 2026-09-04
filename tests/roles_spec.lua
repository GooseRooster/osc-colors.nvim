describe("roles", function()
    local roles
    local oklch
    local utils

    local cfg = {
        capabilities = { undercurl = false, terminal_colors = true },
        soul = { semantic = "sector", contrast_target = 4.5, chroma_ceiling_scale = 1.0, roles = {} },
    }

    -- Representative souls for golden-ish assertions
    local warm_dark = {
        variant = "dark",
        base00 = "#282828",
        base01 = "#3c3836",
        base02 = "#504945",
        base03 = "#665c54",
        base04 = "#bdae93",
        base05 = "#d5c4a1",
        base06 = "#ebdbb2",
        base07 = "#fbf1c7",
        base08 = "#fb4934",
        base09 = "#fe8019",
        base0A = "#fabd2f",
        base0B = "#b8bb26",
        base0C = "#8ec07c",
        base0D = "#83a598",
        base0E = "#d3869b",
        base0F = "#d65d0e",
        capability = { tier = "truecolor" },
    }

    local cool_muted = {
        variant = "dark",
        base00 = "#2e3440",
        base01 = "#3b4252",
        base02 = "#434c5e",
        base03 = "#4c566a",
        base04 = "#d8dee9",
        base05 = "#e5e9f0",
        base06 = "#eceff4",
        base07 = "#f2f4f8",
        base08 = "#bf616a",
        base09 = "#d08770",
        base0A = "#ebcb8b",
        base0B = "#a3be8c",
        base0C = "#88c0d0",
        base0D = "#81a1c1",
        base0E = "#b48ead",
        base0F = "#a3be8c",
        capability = { tier = "truecolor" },
    }

    local monochrome = {
        variant = "dark",
        base00 = "#111111",
        base01 = "#2a2a2a",
        base02 = "#3d3d3d",
        base03 = "#555555",
        base04 = "#777777",
        base05 = "#999999",
        base06 = "#bbbbbb",
        base07 = "#dddddd",
        base08 = "#666666",
        base09 = "#777777",
        base0A = "#888888",
        base0B = "#999999",
        base0C = "#aaaaaa",
        base0D = "#bbbbbb",
        base0E = "#cccccc",
        base0F = "#555555",
        capability = { tier = "truecolor" },
    }

    before_each(function()
        roles = require("osc-colors.roles")
        oklch = require("osc-colors.oklch")
        utils = require("osc-colors.utils")
    end)

    describe("generate", function()
        it("produces a hex color for every role", function()
            local gen = roles.generate(warm_dark, cfg)
            local names = {
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
                "type",
                "import",
                "heading",
                "function",
                "constant",
                "float",
                "character",
                "escape",
                "string",
                "regexp",
                "flow",
                "modifier",
                "tag",
                "namespace",
                "link",
                "comment",
                "punctuation",
                "punct_section",
                "variable",
                "parameter",
                "property",
            }
            for _, name in ipairs(names) do
                assert.is_true(utils.is_hex(gen.roles[name]), name .. " should resolve to a hex color")
            end
        end)

        it("is deterministic for the same input", function()
            local a = roles.generate(warm_dark, cfg)
            local b = roles.generate(warm_dark, cfg)
            for name, hex in pairs(a.roles) do
                assert.equal(hex, b.roles[name], name .. " should be deterministic")
            end
        end)

        it("anchors errors in the red sector and warnings in the yellow sector", function()
            local gen = roles.generate(warm_dark, cfg)
            local _, _, err_hue = oklch.hex_to_oklch(gen.roles.error)
            local _, _, warn_hue = oklch.hex_to_oklch(gen.roles.warning)
            assert.is_true(err_hue <= 40 or err_hue >= 350, "error hue should be red-sector, got " .. err_hue)
            assert.is_true(warn_hue >= 40 and warn_hue <= 80, "warning hue should be yellow-sector, got " .. warn_hue)
        end)

        it("keeps syntax role hues separated (the harmony trap)", function()
            local gen = roles.generate(warm_dark, cfg)
            local syntax_roles = {
                "keyword",
                "type",
                "import",
                "heading",
                "function",
                "constant",
                "float",
                "character",
                "escape",
                "string",
                "regexp",
                "flow",
                "modifier",
                "tag",
                "namespace",
                "link",
            }
            for i = 1, #syntax_roles do
                for j = i + 1, #syntax_roles do
                    local a = select(3, oklch.hex_to_oklch(gen.roles[syntax_roles[i]]))
                    local b = select(3, oklch.hex_to_oklch(gen.roles[syntax_roles[j]]))
                    local d = math.abs(a - b) % 360
                    if d > 180 then
                        d = 360 - d
                    end
                    assert.is_true(
                        d >= 15,
                        string.format("%s (%.0f) and %s (%.0f) are too close", syntax_roles[i], a, syntax_roles[j], b)
                    )
                end
            end
        end)

        it("honors the contrast target for text roles", function()
            local gen = roles.generate(cool_muted, cfg)
            for _, name in ipairs({ "keyword", "string", "comment", "error" }) do
                local c = oklch.contrast(gen.roles[name], cool_muted.base00)
                assert.is_true(c >= 4.0, name .. " contrast " .. c .. " should be near target")
            end
        end)

        it("degrades achromatic souls to lightness structure", function()
            local gen = roles.generate(monochrome, cfg)
            -- syntax roles should be visually gray: near-zero chroma
            local syntax_names = {
                "keyword",
                "type",
                "import",
                "heading",
                "function",
                "constant",
                "float",
                "character",
                "escape",
                "string",
                "regexp",
                "flow",
                "modifier",
                "tag",
                "namespace",
                "link",
                "comment",
            }
            for _, name in ipairs(syntax_names) do
                local _, C = oklch.hex_to_oklch(gen.roles[name])
                assert.is_true(C < 0.04, name .. " should be near-achromatic, chroma " .. C)
            end
            -- semantic roles deliberately keep a chroma floor so errors
            -- still read as errors even in a grayscale soul
            assert.is_true(select(2, oklch.hex_to_oklch(gen.roles.error)) >= 0.09)
            -- and syntax roles still differentiate by lightness
            local kw_L = select(1, oklch.hex_to_oklch(gen.roles.keyword))
            local cm_L = select(1, oklch.hex_to_oklch(gen.roles.comment))
            assert.is_true(kw_L > cm_L, "keyword should out-pop comment even in grayscale")
        end)

        it("produces different palettes for different souls from the same algorithm", function()
            local warm = roles.generate(warm_dark, cfg)
            local cool = roles.generate(cool_muted, cfg)
            assert.are_not.equal(warm.roles.keyword, cool.roles.keyword)
            assert.are_not.equal(warm.roles.string, cool.roles.string)
        end)

        it("snaps to the terminal's real cube on the 256 tier", function()
            local palette = vim.deepcopy(warm_dark)
            palette.capability = { tier = "256" }
            palette.cube = { [16] = "#ff5f00", [244] = "#808080" }
            local gen = roles.generate(palette, cfg)
            assert.is_function(gen.snap)
            -- every role color must be one of the real cube entries
            for name, hex in pairs(gen.roles) do
                assert.is_true(
                    hex == "#ff5f00" or hex == "#808080",
                    name .. " should snap to a cube entry, got " .. hex
                )
            end
        end)

        it("falls back to the nominal cube on the 256 tier without a queried cube", function()
            local palette = vim.deepcopy(warm_dark)
            palette.capability = { tier = "256" }
            palette.cube = nil
            local gen = roles.generate(palette, cfg)
            assert.is_function(gen.snap)
            local nominal = utils.nominal_cube()
            local values = {}
            for _, hex in pairs(nominal) do
                values[hex] = true
            end
            for name, hex in pairs(gen.roles) do
                assert.is_true(values[hex], name .. " should snap to a nominal cube entry, got " .. hex)
            end
        end)

        it("applies per-role config overrides", function()
            local custom = vim.deepcopy(cfg)
            custom.soul.roles = { keyword = { offset = 200, weight = 0.9 } }
            local base = roles.generate(warm_dark, cfg)
            local over = roles.generate(warm_dark, custom)
            assert.are_not.equal(base.roles.keyword, over.roles.keyword)
        end)

        it("supports the experimental fully-derived semantic policy", function()
            local custom = vim.deepcopy(cfg)
            custom.soul.semantic = "derived"
            local sector = roles.generate(warm_dark, cfg)
            local derived = roles.generate(warm_dark, custom)
            -- derived errors are rotated away from the conventional sector
            assert.are_not.equal(sector.roles.error, derived.roles.error)
        end)
    end)

    describe("apply", function()
        local colors

        before_each(function()
            colors = require("osc-colors.colors")
        end)

        local function normalized(palette)
            return colors.normalize(vim.deepcopy(palette))
        end

        it("rewrites the syntax tree and adds semantics", function()
            local p = normalized(warm_dark)
            roles.apply(p, cfg)

            assert.is_true(utils.is_hex(p.syntax.keyword.default))
            assert.is_true(utils.is_hex(p.semantics.error))
            assert.equal(p.semantics.error, p.ui.status.error)
            assert.equal(p.semantics.diff.add, p.syntax.markup.inserted)
        end)

        it("leans the gray ramp toward the soul's dominant hue", function()
            local p = normalized(warm_dark)
            local before = p.base03
            roles.apply(p, cfg)
            assert.are_not.equal(before, p.base03)
            -- and the tree stays consistent with the slots
            assert.equal(p.base03, p.palette.gray.normal)
        end)

        it("leaves an achromatic soul's ramp perfectly neutral", function()
            local p = normalized(monochrome)
            local before = p.base03
            roles.apply(p, cfg)
            assert.equal(before, p.base03)
        end)

        it("is idempotent (no double-lean)", function()
            local p = normalized(warm_dark)
            roles.apply(p, cfg)
            local once = p.base03
            roles.apply(p, cfg)
            assert.equal(once, p.base03)
        end)

        it("survives a re-normalize without losing soul values", function()
            local p = normalized(warm_dark)
            roles.apply(p, cfg)
            local soul_keyword = p.syntax.keyword.default
            local p2 = colors.normalize(p)
            assert.equal(soul_keyword, p2.syntax.keyword.default)
            assert.equal(p.semantics.error, p2.semantics.error)
        end)

        it("marks the palette so a second pass is a no-op even after normalize", function()
            local p = normalized(warm_dark)
            roles.apply(p, cfg)
            local leaned = p.base03
            local p2 = colors.normalize(p)
            roles.apply(p2, cfg)
            assert.equal(leaned, p2.base03)
        end)

        it("keeps base16 mode colors when apply is never called", function()
            local colors_mod = require("osc-colors.colors")
            local q = colors_mod.normalize(vim.deepcopy(warm_dark))
            -- keyword = base0E in base16 statics
            assert.equal(q.syntax.keyword.default, warm_dark.base0E)
            assert.equal(q.semantics.error, warm_dark.base08)
        end)
    end)
end)
