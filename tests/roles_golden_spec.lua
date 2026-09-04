-- Golden snapshots: soul in -> role palette out. The generation algorithm
-- is pure math over the anchors, so these hex values are exactly
-- reproducible; any change here means the algorithm (or a role descriptor)
-- changed, deliberately or not. When tuning defaults, regenerate this table
-- and let the diff be the review of your taste adjustment.

describe("roles golden values", function()
    local roles

    before_each(function()
        roles = require("osc-colors.roles")
    end)

    local cfg = {
        soul = { semantic = "sector", contrast_target = 4.5, chroma_ceiling_scale = 1.0, roles = {} },
    }

    local palettes = {
        warm_dark = {
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
        },
        cool_muted = {
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
        },
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
        warm_dark = {
            error = "#ff88a5",
            warning = "#e2a371",
            success = "#a3bc40",
            info = "#6eb8e7",
            hint = "#47bab9",
            deprecated = "#9d93d8",
            diff_add = "#78c567",
            diff_delete = "#ff876c",
            diff_change = "#58bfd5",
            keyword = "#ffa500",
            type = "#c79aff",
            import = "#deb100",
            heading = "#ffae88",
            ["function"] = "#ff9493",
            constant = "#b4b700",
            float = "#00cab6",
            character = "#e885de",
            escape = "#98a7ff",
            string = "#00bbed",
            regexp = "#5bb0ff",
            flow = "#8bc843",
            modifier = "#4ad176",
            tag = "#00d29b",
            namespace = "#f583bb",
            link = "#00c5d3",
            comment = "#a78f6e",
            punctuation = "#9b8d7a",
            punct_section = "#ac9b83",
            variable = "#d7cdc0",
            parameter = "#ccc2b5",
            property = "#d1c7b9",
        },
        cool_muted = {
            error = "#f69ab6",
            warning = "#e5ad72",
            success = "#79c9a0",
            info = "#6bc2e8",
            hint = "#5ac2b2",
            deprecated = "#9e9de2",
            diff_add = "#93c688",
            diff_delete = "#f69892",
            diff_change = "#5cc8d3",
            keyword = "#ffa98f",
            type = "#9fb6ff",
            import = "#f3ac76",
            heading = "#ffb2ba",
            ["function"] = "#efa3ca",
            constant = "#d8ae6d",
            float = "#8cc696",
            character = "#bcaae9",
            escape = "#85bce7",
            string = "#6cc3bf",
            regexp = "#6ebfd3",
            flow = "#caba70",
            modifier = "#b5c27a",
            tag = "#a2c786",
            namespace = "#cca5d9",
            link = "#77c9ad",
            comment = "#b7a097",
            punctuation = "#ac9e99",
            punct_section = "#b2a19b",
            variable = "#dcd2ce",
            parameter = "#d1c8c4",
            property = "#d5ccc8",
        },
        monochrome = {
            error = "#d48576",
            warning = "#cb8e5c",
            success = "#9c9e52",
            info = "#39abb3",
            hint = "#53a37b",
            deprecated = "#9f74b0",
            diff_add = "#7ca768",
            diff_delete = "#cd7e92",
            diff_change = "#45a6c5",
            keyword = "#9aaaa5",
            type = "#a89a93",
            import = "#94a6a5",
            heading = "#a7b3a8",
            ["function"] = "#9fa496",
            constant = "#8b9ca0",
            float = "#9797a5",
            character = "#a1978c",
            escape = "#a59494",
            string = "#9b909b",
            regexp = "#9f9096",
            flow = "#92a0a8",
            modifier = "#959eaa",
            tag = "#989daa",
            namespace = "#9d998b",
            link = "#9c96a3",
            comment = "#7c7c7c",
            punctuation = "#838383",
            punct_section = "#878787",
            variable = "#bababa",
            parameter = "#afafaf",
            property = "#b3b3b3",
        },
    }

    for soul_name, expected in pairs(golden) do
        describe(soul_name, function()
            it("matches the pinned role palette", function()
                local gen = roles.generate(palettes[soul_name], cfg)
                for role, hex in pairs(expected) do
                    assert.equal(
                        hex,
                        gen.roles[role],
                        string.format("%s/%s drifted from its golden value", soul_name, role)
                    )
                end
            end)
        end)
    end
end)
