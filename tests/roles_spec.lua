describe("roles", function()
    local roles
    local oklch
    local utils
    local soulmod
    local fx = dofile("tests/fixtures/schemes.lua")

    local cfg = {
        capabilities = { undercurl = false, terminal_colors = true },
        soul = { contrast_target = 4.5, styles = "auto", pin = {}, roles = {} },
    }

    local function scheme(name, opts)
        return fx.to_palette(fx.schemes[name], opts)
    end

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

    local function hue_of(hex)
        return select(3, oklch.hex_to_oklch(hex))
    end

    local function with_soul(overrides)
        local c = vim.deepcopy(cfg)
        c.soul = vim.tbl_extend("force", c.soul, overrides)
        return c
    end

    before_each(function()
        roles = require("osc-colors.roles")
        oklch = require("osc-colors.oklch")
        utils = require("osc-colors.utils")
        soulmod = require("osc-colors.soul")
    end)

    describe("generate", function()
        it("produces a hex color for every role", function()
            local gen = roles.generate(scheme("gruvbox"), cfg)
            for _, name in ipairs(roles.ROLE_ORDER) do
                assert.is_true(utils.is_hex(gen.roles[name]), name .. " should resolve to a hex color")
            end
        end)

        it("assigns every role group to one of the scheme's families", function()
            local gen = roles.generate(scheme("gruvbox"), cfg)
            for _, group in ipairs(roles.GROUPS) do
                assert.is_table(soulmod.family(gen.soul, gen.assignment[group.name]), group.name)
            end
        end)

        it("is deterministic for the same input", function()
            local a = roles.generate(scheme("tokyonight"), cfg)
            local b = roles.generate(scheme("tokyonight"), cfg)
            assert.same(a.roles, b.roles)
            assert.same(a.styles, b.styles)
            assert.same(a.assignment, b.assignment)
        end)

        it("builds lead roles from the scheme's own colors", function()
            -- a lead's hue is its family's hue (contrast lifts only move L)
            for _, name in ipairs(fx.names()) do
                local gen = roles.generate(scheme(name), cfg)
                for _, group in ipairs(roles.GROUPS) do
                    local fam = soulmod.family(gen.soul, gen.assignment[group.name])
                    local d = soulmod.hue_distance(hue_of(gen.roles[group.lead]), fam.H)
                    assert.is_true(
                        d < 8,
                        string.format("%s/%s drifted %.1fdeg from its family %s", name, group.lead, d, fam.name)
                    )
                end
            end
        end)

        it("gives different schemes genuinely different role maps", function()
            -- the whole point: no family may own a role across most schemes
            local names = fx.names()
            for _, group in ipairs({ "keyword", "function", "type", "string" }) do
                local tally = {}
                for _, name in ipairs(names) do
                    local fam = roles.generate(scheme(name), cfg).assignment[group]
                    local base = fam:gsub("^bright_", "")
                    tally[base] = (tally[base] or 0) + 1
                end
                for fam, count in pairs(tally) do
                    assert.is_true(
                        count <= #names / 2,
                        string.format("%s lands on %s in %d of %d schemes", group, fam, count, #names)
                    )
                end
                assert.is_true(vim.tbl_count(tally) >= 4, group .. " should spread over at least 4 families")
            end
        end)

        it("puts the most prominent groups on salient families", function()
            -- gruvbox's muted blue/magenta must not carry keywords or functions
            local gen = roles.generate(scheme("gruvbox"), cfg)
            for _, group in ipairs({ "keyword", "function" }) do
                local fam = gen.assignment[group]
                assert.is_true(fam ~= "blue" and fam ~= "magenta", group .. " landed on muted " .. fam)
            end
        end)

        it("separates the groups that sit side by side", function()
            for _, name in ipairs(fx.names()) do
                local a = roles.generate(scheme(name), cfg).assignment
                assert.are_not.equal(a.keyword, a["function"], name .. ": keyword and function share a family")
                assert.are_not.equal(a.keyword, a.type, name .. ": keyword and type share a family")
            end
        end)

        it("anchors semantic roles in their conventional sectors", function()
            local sectors = {
                error = { 0, 40 },
                warning = { 45, 75 },
                success = { 110, 160 },
                info = { 190, 250 },
                hint = { 150, 200 },
                deprecated = { 280, 330 },
            }
            for _, name in ipairs(fx.names()) do
                local gen = roles.generate(scheme(name), cfg)
                for role, sector in pairs(sectors) do
                    local h = hue_of(gen.roles[role])
                    local d = h >= sector[1] and h <= sector[2] and 0
                        or math.min(soulmod.hue_distance(h, sector[1]), soulmod.hue_distance(h, sector[2]))
                    assert.is_true(d < 6, string.format("%s/%s hue %.0f outside its sector", name, role, h))
                end
                assert.equal(gen.roles.error, gen.roles.diff_delete)
                assert.equal(gen.roles.success, gen.roles.diff_add)
                assert.equal(gen.roles.info, gen.roles.diff_change)
            end
        end)

        it("uses the scheme's own red for errors", function()
            local gen = roles.generate(scheme("gruvbox"), cfg)
            local red = soulmod.family(gen.soul, "red")
            assert.is_true(soulmod.hue_distance(hue_of(gen.roles.error), red.H) < 3)
        end)

        it("keeps info and hint apart even when one family could serve both", function()
            for _, name in ipairs(fx.names()) do
                local gen = roles.generate(scheme(name), cfg)
                assert.are_not.equal(gen.roles.info, gen.roles.hint, name)
            end
        end)

        it("honors the contrast target for text roles", function()
            for _, name in ipairs(fx.names()) do
                local p = scheme(name)
                local gen = roles.generate(p, cfg)
                for _, role in ipairs({ "keyword", "string", "type", "comment", "error", "variable" }) do
                    local c = oklch.contrast(gen.roles[role], p.base00)
                    assert.is_true(c >= 4.4, string.format("%s/%s contrast %.2f", name, role, c))
                end
            end
        end)

        it("works on light schemes", function()
            local p = scheme("github_light")
            local gen = roles.generate(p, cfg)
            local bg_L = select(1, oklch.hex_to_oklch(p.base00))
            for _, role in ipairs({ "keyword", "function", "type", "string" }) do
                assert.is_true(select(1, oklch.hex_to_oklch(gen.roles[role])) < bg_L - 0.2, role)
            end
        end)

        it("degrades achromatic souls to lightness structure", function()
            local gen = roles.generate(monochrome, cfg)
            for _, name in ipairs(roles.ROLE_ORDER) do
                local r_is_semantic = name == "error"
                    or name == "warning"
                    or name == "success"
                    or name == "info"
                    or name == "hint"
                    or name == "deprecated"
                    or name:match("^diff_")
                if not r_is_semantic then
                    local _, C = oklch.hex_to_oklch(gen.roles[name])
                    assert.is_true(C < 0.02, name .. " should be achromatic, chroma " .. C)
                end
            end
            -- semantic roles keep a chroma floor so errors still read as errors
            assert.is_true(select(2, oklch.hex_to_oklch(gen.roles.error)) >= 0.09)
            local kw_L = select(1, oklch.hex_to_oklch(gen.roles.keyword))
            local cm_L = select(1, oklch.hex_to_oklch(gen.roles.comment))
            assert.is_true(kw_L > cm_L, "keyword should out-pop comment even in grayscale")
        end)

        it("snaps to the terminal's real cube on the 256 tier", function()
            local palette = scheme("gruvbox", { tier = "256" })
            palette.cube = { [16] = "#ff5f00", [244] = "#808080" }
            local gen = roles.generate(palette, cfg)
            assert.is_function(gen.snap)
            for name, hex in pairs(gen.roles) do
                assert.is_true(
                    hex == "#ff5f00" or hex == "#808080",
                    name .. " should snap to a cube entry, got " .. hex
                )
            end
        end)

        it("falls back to the nominal cube on the 256 tier without a queried cube", function()
            local palette = scheme("gruvbox", { tier = "256" })
            local gen = roles.generate(palette, cfg)
            assert.is_function(gen.snap)
            local values = {}
            for _, hex in pairs(utils.nominal_cube()) do
                values[hex] = true
            end
            for name, hex in pairs(gen.roles) do
                assert.is_true(values[hex], name .. " should snap to a nominal cube entry, got " .. hex)
            end
        end)

        it("applies per-role tweaks", function()
            local base = roles.generate(scheme("gruvbox"), cfg)
            local over = roles.generate(scheme("gruvbox"), with_soul({ roles = { keyword = { chroma = 0.4 } } }))
            assert.are_not.equal(base.roles.keyword, over.roles.keyword)
            assert.equal(base.roles.string, over.roles.string)
        end)

        it("honors pinned groups", function()
            local gen = roles.generate(scheme("gruvbox"), with_soul({ pin = { string = "green" } }))
            assert.equal("green", gen.assignment.string)
        end)

        it("ignores a pin naming a family the scheme doesn't have", function()
            local base = roles.generate(scheme("gruvbox"), cfg)
            local gen = roles.generate(scheme("gruvbox"), with_soul({ pin = { string = "bright_cyan" } }))
            assert.equal(base.assignment.string, gen.assignment.string)
        end)

        it("uses the bright shade for shade roles when it differs", function()
            local gen = roles.generate(scheme("dracula"), cfg)
            local fam = soulmod.family(gen.soul, gen.assignment.keyword)
            assert.are_not.equal(gen.roles.keyword, gen.roles.import)
            assert.is_true(
                oklch.delta_e(gen.roles.import, fam.shade.hex) < oklch.delta_e(gen.roles.import, fam.hex),
                "import should sit on the keyword family's bright shade"
            )
        end)
    end)

    describe("styles", function()
        it("always bolds headings", function()
            local gen = roles.generate(scheme("dracula"), cfg)
            assert.same({ bold = true }, gen.styles.heading)
        end)

        it("styles a group lead that shares its family with a more prominent group", function()
            -- find a scheme where special reuses another group's family
            for _, name in ipairs(fx.names()) do
                local gen = roles.generate(scheme(name), cfg)
                for _, group in ipairs(roles.GROUPS) do
                    if group.name ~= "special" and gen.assignment[group.name] == gen.assignment.special then
                        assert.is_table(gen.styles.escape, name .. ": shared special lead should be styled")
                    end
                end
            end
        end)

        it("leaves well-separated group leads unstyled", function()
            local gen = roles.generate(scheme("dracula"), cfg)
            assert.is_nil(gen.styles.keyword)
            assert.is_nil(gen.styles["function"])
            assert.is_nil(gen.styles.type)
        end)

        it("styles everything an achromatic soul can't color apart", function()
            local gen = roles.generate(monochrome, cfg)
            for _, role in ipairs({ "function", "type", "string", "flow", "modifier", "parameter" }) do
                assert.is_table(gen.styles[role], role)
            end
        end)

        it("applies every candidate with styles = 'always'", function()
            local gen = roles.generate(scheme("dracula"), with_soul({ styles = "always" }))
            for _, role in ipairs({ "function", "type", "flow", "import", "modifier", "namespace", "parameter" }) do
                assert.is_table(gen.styles[role], role)
            end
        end)

        it("disables soul styles with styles = false", function()
            local gen = roles.generate(monochrome, with_soul({ styles = false }))
            assert.same({}, gen.styles)
        end)

        it("lets a per-role style override win", function()
            local gen = roles.generate(
                scheme("dracula"),
                with_soul({ roles = { heading = { style = false }, keyword = { style = { underline = true } } } })
            )
            assert.is_nil(gen.styles.heading)
            assert.same({ underline = true }, gen.styles.keyword)
        end)

        it("merges role styles into highlight groups without overriding existing attributes", function()
            local hl = {
                Keyword = { fg = "#ffffff", italic = false },
                ["@markup.heading"] = { fg = "#ffffff" },
                Type = { link = "Normal" },
            }
            roles.style_highlights(hl, {
                keyword = { italic = true },
                heading = { bold = true },
                type = { bold = true },
            })
            assert.is_false(hl.Keyword.italic)
            assert.is_true(hl["@markup.heading"].bold)
            assert.is_nil(hl.Type.bold)
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

        it("rewrites the syntax tree and adds semantics + styles", function()
            local p = normalized(scheme("gruvbox"))
            roles.apply(p, cfg)

            assert.is_true(utils.is_hex(p.syntax.keyword.default))
            assert.is_true(utils.is_hex(p.semantics.error))
            assert.equal(p.semantics.error, p.ui.status.error)
            assert.equal(p.semantics.diff.add, p.syntax.markup.inserted)
            assert.is_table(p.role_styles)
            assert.same({ bold = true }, p.role_styles.heading)
        end)

        it("writes every role into the tree, including bracketed paths", function()
            local raw = scheme("rosepine")
            local gen = roles.generate(raw, cfg)
            local p = normalized(raw)
            roles.apply(p, cfg)
            local sx = p.syntax
            assert.equal(gen.roles["function"], sx.entity.name["function"].default)
            assert.equal(gen.roles["function"], sx.entity.name["function"].constructor)
            assert.equal(gen.roles.modifier, sx.entity.other["attribute-name"])
            assert.equal(gen.roles.keyword, sx.keyword.default)
            assert.equal(gen.roles.type, sx.entity.name.type)
            assert.equal(gen.roles.string, sx.string.default)
            assert.equal(gen.roles.constant, sx.constant.default)
            assert.equal(gen.roles.escape, sx.constant.character.escape)
            assert.equal(gen.roles.parameter, sx.variable.parameter)
            assert.are_not.equal(raw.base0D, sx.entity.name["function"].default)
        end)

        it("leans the gray ramp toward the dominant family's hue", function()
            local p = normalized(scheme("gruvbox"))
            local before = p.base03
            roles.apply(p, cfg)
            assert.are_not.equal(before, p.base03)
            assert.equal(p.base03, p.palette.gray.normal)
        end)

        it("leaves an achromatic soul's ramp perfectly neutral", function()
            local p = normalized(monochrome)
            local before = p.base03
            roles.apply(p, cfg)
            assert.equal(before, p.base03)
        end)

        it("is idempotent (no double-lean)", function()
            local p = normalized(scheme("gruvbox"))
            roles.apply(p, cfg)
            local once = p.base03
            roles.apply(p, cfg)
            assert.equal(once, p.base03)
        end)

        it("survives a re-normalize without losing soul values", function()
            local p = normalized(scheme("gruvbox"))
            roles.apply(p, cfg)
            local p2 = colors.normalize(p)
            assert.equal(p.syntax.keyword.default, p2.syntax.keyword.default)
            assert.equal(p.semantics.error, p2.semantics.error)
            assert.same(p.role_styles, p2.role_styles)
        end)

        it("marks the palette so a second pass is a no-op even after normalize", function()
            local p = normalized(scheme("gruvbox"))
            roles.apply(p, cfg)
            local leaned = p.base03
            local p2 = colors.normalize(p)
            roles.apply(p2, cfg)
            assert.equal(leaned, p2.base03)
        end)

        it("keeps base16 mode colors when apply is never called", function()
            local raw = scheme("gruvbox")
            local q = colors.normalize(vim.deepcopy(raw))
            assert.equal(q.syntax.keyword.default, raw.base0E)
            assert.equal(q.semantics.error, raw.base08)
            assert.is_nil(q.role_styles)
        end)

        it("does not switch base16 mode into base24 when brights are present", function()
            local raw = scheme("dracula")
            local q = colors.normalize(vim.deepcopy(raw))
            assert.is_nil(q.base12)
            assert.equal(raw.base08, q.palette.red.bright)
        end)
    end)
end)
