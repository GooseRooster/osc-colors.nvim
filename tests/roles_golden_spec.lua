-- Golden snapshots: soul in -> role map out. The generation algorithm is
-- pure math over the scheme's own colors, so these values are exactly
-- reproducible; any change here means the algorithm (salience, the group
-- search, a role descriptor, the style policy) changed, deliberately or
-- not. When taste-tuning, regenerate this table and let the diff be the
-- review of your adjustment.

describe("roles golden values", function()
    local roles
    local fx = dofile("tests/fixtures/schemes.lua")

    before_each(function()
        roles = require("osc-colors.roles")
    end)

    local cfg = {
        soul = { contrast_target = 4.5, styles = "auto", pin = {}, roles = {} },
    }

    local palettes = {
        gruvbox = fx.to_palette(fx.schemes.gruvbox), -- warm, vivid
        nord = fx.to_palette(fx.schemes.nord), -- cool, muted
        github_light = fx.to_palette(fx.schemes.github_light), -- light background
        monochrome = {
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
        },
    }

    local golden = {
        gruvbox = {
            roles = {
                error = "#fb5f50",
                warning = "#d79832",
                success = "#969728",
                info = "#249da2",
                hint = "#5e9f6d",
                deprecated = "#bc7fb6",
                diff_add = "#969728",
                diff_delete = "#fb5f50",
                diff_change = "#249da2",
                keyword = "#ff5a4b",
                flow = "#fb5364",
                import = "#ff5353",
                modifier = "#ed6c5e",
                ["function"] = "#98971a",
                type = "#d79921",
                namespace = "#d9ae6a",
                tag = "#df942c",
                string = "#5d9da0",
                regexp = "#5c99a5",
                character = "#5b99a4",
                constant = "#689d6a",
                float = "#689d6a",
                escape = "#d79921",
                heading = "#fabd2f",
                link = "#e0932f",
                comment = "#92937c",
                punctuation = "#929283",
                punct_section = "#939481",
                variable = "#bfbfb5",
                parameter = "#b5b5ac",
                property = "#b9b9ad",
            },
            styles = {
                flow = { italic = true },
                import = { italic = true },
                modifier = { italic = true },
                escape = { italic = true },
                heading = { bold = true },
            },
            assignment = {
                keyword = "red",
                ["function"] = "green",
                type = "yellow",
                string = "blue",
                constant = "cyan",
                special = "yellow",
            },
        },
        nord = {
            roles = {
                error = "#de8189",
                warning = "#f6c684",
                success = "#9dc17d",
                info = "#6aa2d9",
                hint = "#5cc9cf",
                deprecated = "#c68bc0",
                diff_add = "#9dc17d",
                diff_delete = "#de8189",
                diff_change = "#6aa2d9",
                keyword = "#88c0d0",
                flow = "#8fcbd4",
                import = "#99d4e0",
                modifier = "#86b1be",
                ["function"] = "#ebcb8b",
                type = "#e17f87",
                namespace = "#d38e92",
                tag = "#df7f93",
                string = "#81a1c1",
                regexp = "#92a8cc",
                character = "#8aa2c6",
                constant = "#a3be8c",
                float = "#a3be8c",
                escape = "#ebcb8b",
                heading = "#f8d898",
                link = "#f3c78d",
                comment = "#a69f93",
                punctuation = "#a29e96",
                punct_section = "#a39e94",
                variable = "#c4c1bc",
                parameter = "#bbb8b3",
                property = "#bfbcb6",
            },
            styles = {
                flow = { italic = true },
                modifier = { italic = true },
                namespace = { italic = true },
                escape = { italic = true },
                heading = { bold = true },
            },
            assignment = {
                keyword = "cyan",
                ["function"] = "yellow",
                type = "red",
                string = "blue",
                constant = "green",
                special = "yellow",
            },
        },
        github_light = {
            roles = {
                error = "#cb2c33",
                warning = "#4d2d00",
                success = "#18622c",
                info = "#0071c3",
                hint = "#007d83",
                deprecated = "#8153da",
                diff_add = "#18622c",
                diff_delete = "#cb2c33",
                diff_change = "#0071c3",
                keyword = "#4d2d00",
                flow = "#3f2900",
                import = "#603e00",
                modifier = "#543a1b",
                ["function"] = "#0969da",
                type = "#1b7c83",
                namespace = "#326a6e",
                tag = "#1e7b89",
                string = "#cf222e",
                regexp = "#c20948",
                character = "#d82d53",
                constant = "#116329",
                float = "#116329",
                escape = "#8250df",
                heading = "#8655d7",
                link = "#9349d4",
                comment = "#82705e",
                punctuation = "#7f7367",
                punct_section = "#7e6f60",
                variable = "#49433c",
                parameter = "#534d46",
                property = "#514840",
            },
            styles = {
                flow = { italic = true },
                modifier = { italic = true },
                heading = { bold = true },
            },
            assignment = {
                keyword = "yellow",
                ["function"] = "blue",
                type = "cyan",
                string = "red",
                constant = "green",
                special = "magenta",
            },
        },
        monochrome = {
            roles = {
                error = "#d48383",
                warning = "#cb8e5b",
                success = "#7ea767",
                info = "#44a7c3",
                hint = "#3fa48c",
                deprecated = "#9577b8",
                diff_add = "#7ea767",
                diff_delete = "#d48383",
                diff_change = "#44a7c3",
                keyword = "#d1d1d1",
                flow = "#dbdbdb",
                import = "#e5e5e5",
                modifier = "#c4c4c4",
                ["function"] = "#c1c1c1",
                type = "#b3b3b3",
                namespace = "#c3c3c3",
                tag = "#b3b3b3",
                string = "#a1a1a1",
                regexp = "#ababab",
                character = "#989898",
                constant = "#949494",
                float = "#949494",
                escape = "#878787",
                heading = "#939393",
                link = "#878787",
                comment = "#808080",
                punctuation = "#7e7e7e",
                punct_section = "#878787",
                variable = "#bababa",
                parameter = "#afafaf",
                property = "#b3b3b3",
            },
            styles = {
                keyword = { italic = true },
                flow = { italic = true },
                import = { italic = true },
                modifier = { italic = true },
                ["function"] = { bold = true },
                type = { bold = true },
                namespace = { italic = true },
                string = { italic = true },
                constant = { bold = true },
                escape = { italic = true },
                heading = { bold = true },
                parameter = { italic = true },
            },
            assignment = {},
        },
    }

    for soul_name, expected in pairs(golden) do
        describe(soul_name, function()
            local gen

            before_each(function()
                gen = roles.generate(palettes[soul_name], cfg)
            end)

            it("matches the pinned role palette", function()
                for role, hex in pairs(expected.roles) do
                    assert.equal(
                        hex,
                        gen.roles[role],
                        string.format("%s/%s drifted from its golden value", soul_name, role)
                    )
                end
            end)

            it("matches the pinned styles", function()
                assert.same(expected.styles, gen.styles)
            end)

            it("matches the pinned group assignment", function()
                assert.same(expected.assignment, gen.assignment)
            end)
        end)
    end
end)
