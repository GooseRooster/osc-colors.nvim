describe("highlights", function()
    local highlights

    before_each(function()
        package.loaded["osc-colors.highlights"] = nil
        package.loaded["osc-colors.highlights.core"] = nil
        package.loaded["osc-colors.highlights.syntax"] = nil
        package.loaded["osc-colors.highlights.treesitter"] = nil
        package.loaded["osc-colors.highlights.lsp"] = nil
        package.loaded["osc-colors.highlights.diagnostics"] = nil
        highlights = require("osc-colors.highlights")
    end)

    local test_palette = {
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

    local default_cfg = {
        capabilities = {
            undercurl = false,
            terminal_colors = true,
        },
        ui = {
            transparent = false,
            dim_inactive = false,
        },
        styles = {
            comments = { italic = true },
            keywords = {},
            functions = {},
            variables = {},
            types = {},
        },
        highlights = {
            integrations = {},
            use_lazy_specs = false,
            overrides = function()
                return {}
            end,
        },
    }

    describe("build", function()
        it("returns a table of highlight groups", function()
            local result = highlights.build(test_palette, default_cfg)
            assert.is_table(result)
        end)

        it("includes core highlight groups", function()
            local result = highlights.build(test_palette, default_cfg)
            assert.is_table(result.Normal)
            assert.is_table(result.Visual)
            assert.is_table(result.Cursor)
        end)

        it("includes syntax highlight groups", function()
            local result = highlights.build(test_palette, default_cfg)
            assert.is_table(result.Comment)
            assert.is_table(result.String)
            assert.is_table(result.Function)
        end)

        describe("real-cube cterm backfill", function()
            it("snaps unmatched hexes to the nearest queried cube slot", function()
                local palette = vim.deepcopy(test_palette)
                palette.capability = { tier = "256" }
                palette.cube = {
                    [16] = "#ff0000", -- a red the base16 slots don't use
                    [17] = "#00ff00",
                    [196] = "#ff5f00",
                    [244] = "#808080",
                }
                local result = highlights.build(palette, default_cfg)

                -- Every fg/bg that resolves to a hex must now carry a cterm
                -- index even when it isn't an exact palette slot match.
                local with_cterm, without_cterm = 0, 0
                for _, spec in pairs(result) do
                    if type(spec.fg) == "string" and spec.fg:sub(1, 1) == "#" then
                        if spec.ctermfg then
                            with_cterm = with_cterm + 1
                        else
                            without_cterm = without_cterm + 1
                        end
                    end
                end
                assert.is_true(with_cterm > 0)
                assert.equal(0, without_cterm)
            end)

            it("prefers an exact palette-slot match over a cube snap", function()
                local palette = vim.deepcopy(test_palette)
                -- disambiguate from base08 so the cterm map isn't ambiguous
                palette.base0F = "#884400"
                palette.capability = { tier = "256" }
                palette.cube = {
                    [196] = "#ff5f00", -- near-miss to base08's #880000
                }
                local result = highlights.build(palette, default_cfg)

                -- Debug = base08 = #880000 = ANSI red (slot 1) via aliases.cterm
                assert.equal(1, result.Debug.ctermfg)
            end)

            it("does no nearest-matching when there is no cube", function()
                local result = highlights.build(test_palette, default_cfg)
                -- without a cube, only exact palette-slot matches carry cterm;
                -- a mid-ramp gray like base03 (#333333) maps to ANSI 8
                assert.equal(8, result.Comment.ctermfg)
            end)
        end)

        describe("treesitter capture fallback coverage", function()
            -- Regression coverage for the bug class where a capture name a
            -- modern grammar actually emits (e.g. razor/c_sharp/html/jsx) was
            -- never explicitly defined here, so it silently fell back (per
            -- Neovim's "more specific -> more generic" capture rule) onto a
            -- less specific, differently-colored group instead of the
            -- intended, already-computed color.

            it("gives markup tags, attributes, and delimiters distinct colors", function()
                local result = highlights.build(test_palette, default_cfg)

                assert.is_string(result["@tag"].fg)
                assert.is_string(result["@tag.attribute"].fg)
                assert.is_string(result["@tag.delimiter"].fg)

                assert.not_equal(result["@tag"].fg, result["@tag.attribute"].fg)
                assert.not_equal(result["@tag"].fg, result["@tag.delimiter"].fg)
                assert.not_equal(result["@tag.attribute"].fg, result["@tag.delimiter"].fg)
            end)

            it("links @tag.builtin so plain HTML tags stay distinct from components", function()
                local result = highlights.build(test_palette, default_cfg)
                assert.equal("Special", result["@tag.builtin"].link)
            end)

            it("keeps access/storage modifiers distinct from plain keywords", function()
                local result = highlights.build(test_palette, default_cfg)
                assert.equal("@storageclass", result["@keyword.modifier"].link)
                assert.not_equal(result["Keyword"].fg, result["@storageclass"].fg)
            end)

            it("keeps preprocessor directives distinct from plain keywords", function()
                local result = highlights.build(test_palette, default_cfg)
                assert.equal("@preproc", result["@keyword.directive"].link)
                assert.equal("@define", result["@keyword.directive.define"].link)
            end)

            it("keeps conditional/repeat keywords wired to their intended color", function()
                local result = highlights.build(test_palette, default_cfg)
                assert.equal("@conditional", result["@keyword.conditional"].link)
                assert.equal("@keyword.conditional", result["@keyword.conditional.ternary"].link)
                assert.equal("@repeat", result["@keyword.repeat"].link)
            end)

            it("keeps modern method captures wired to the same color as legacy @method", function()
                local result = highlights.build(test_palette, default_cfg)
                assert.equal("@method", result["@function.method"].link)
                assert.equal("@method.call", result["@function.method.call"].link)
            end)

            it("fixes the @string.regex/@string.regexp naming mismatch", function()
                local result = highlights.build(test_palette, default_cfg)
                assert.is_string(result["@string.regexp"].fg)
                assert.equal("@string.regexp", result["@string.regex"].link)
            end)
        end)

        it("resolves hex colors directly", function()
            local cfg = vim.tbl_deep_extend("force", default_cfg, {
                highlights = {
                    overrides = function()
                        return {
                            TestGroup = { fg = "#ff0000", bg = "#00ff00" },
                        }
                    end,
                },
            })
            local result = highlights.build(test_palette, cfg)
            assert.equal("#ff0000", result.TestGroup.fg)
            assert.equal("#00ff00", result.TestGroup.bg)
        end)

        it("resolves color aliases", function()
            local cfg = vim.tbl_deep_extend("force", default_cfg, {
                highlights = {
                    overrides = function()
                        return {
                            TestGroup = { fg = "red", bg = "background" },
                        }
                    end,
                },
            })
            local result = highlights.build(test_palette, cfg)
            assert.equal("#880000", result.TestGroup.fg)
            assert.equal("#000000", result.TestGroup.bg)
        end)

        it("resolves NONE color", function()
            local cfg = vim.tbl_deep_extend("force", default_cfg, {
                highlights = {
                    overrides = function()
                        return {
                            TestGroup = { fg = "none", bg = "NONE" },
                        }
                    end,
                },
            })
            local result = highlights.build(test_palette, cfg)
            assert.equal("NONE", result.TestGroup.fg)
            assert.equal("NONE", result.TestGroup.bg)
        end)

        it("preserves link specs", function()
            local cfg = vim.tbl_deep_extend("force", default_cfg, {
                highlights = {
                    overrides = function()
                        return {
                            TestGroup = { link = "Normal" },
                        }
                    end,
                },
            })
            local result = highlights.build(test_palette, cfg)
            assert.equal("Normal", result.TestGroup.link)
        end)

        it("applies darken transform", function()
            local cfg = vim.tbl_deep_extend("force", default_cfg, {
                highlights = {
                    overrides = function()
                        return {
                            TestGroup = { fg = { darken = "#ffffff", amount = 0.5 } },
                        }
                    end,
                },
            })
            local result = highlights.build(test_palette, cfg)
            assert.is_string(result.TestGroup.fg)
            assert.not_equal("#ffffff", result.TestGroup.fg)
        end)

        it("applies lighten transform", function()
            local cfg = vim.tbl_deep_extend("force", default_cfg, {
                highlights = {
                    overrides = function()
                        return {
                            TestGroup = { fg = { lighten = "#000000", amount = 0.5 } },
                        }
                    end,
                },
            })
            local result = highlights.build(test_palette, cfg)
            assert.is_string(result.TestGroup.fg)
            assert.not_equal("#000000", result.TestGroup.fg)
        end)

        it("adds cterm colors for base aliases", function()
            local cfg = vim.tbl_deep_extend("force", default_cfg, {
                highlights = {
                    overrides = function()
                        return {
                            TestGroup = { fg = "red", bg = "background" },
                        }
                    end,
                },
            })
            local result = highlights.build(test_palette, cfg)
            assert.is_number(result.TestGroup.ctermfg)
            assert.is_number(result.TestGroup.ctermbg)
        end)

        it("preserves style attributes", function()
            local cfg = vim.tbl_deep_extend("force", default_cfg, {
                highlights = {
                    overrides = function()
                        return {
                            TestGroup = { fg = "#ff0000", bold = true, italic = true },
                        }
                    end,
                },
            })
            local result = highlights.build(test_palette, cfg)
            assert.is_true(result.TestGroup.bold)
            assert.is_true(result.TestGroup.italic)
        end)

        it("errors on invalid color alias", function()
            local cfg = vim.tbl_deep_extend("force", default_cfg, {
                highlights = {
                    overrides = function()
                        return {
                            TestGroup = { fg = "invalid_color" },
                        }
                    end,
                },
            })
            assert.has_error(function()
                highlights.build(test_palette, cfg)
            end)
        end)

        it("user overrides take precedence", function()
            local cfg = vim.tbl_deep_extend("force", default_cfg, {
                highlights = {
                    overrides = function()
                        return {
                            Normal = { fg = "#123456" },
                        }
                    end,
                },
            })
            local result = highlights.build(test_palette, cfg)
            assert.equal("#123456", result.Normal.fg)
        end)
    end)

    describe("mini integration", function()
        local function build_with_mini()
            local cfg = vim.tbl_deep_extend("force", default_cfg, {
                highlights = {
                    integrations = { mini = true },
                },
            })
            return highlights.build(test_palette, cfg)
        end

        it("is off by default", function()
            local result = highlights.build(test_palette, default_cfg)
            assert.is_nil(result.MiniStatuslineModeNormal)
        end)

        it("defines statusline mode colors distinct per mode", function()
            local result = build_with_mini()
            assert.is_string(result.MiniStatuslineModeInsert.bg)
            assert.is_string(result.MiniStatuslineModeVisual.bg)
            assert.not_equal(result.MiniStatuslineModeInsert.bg, result.MiniStatuslineModeVisual.bg)
        end)

        it("gives trailing whitespace a visible background", function()
            local result = build_with_mini()
            assert.is_string(result.MiniTrailspace.bg)
        end)

        it("gives mini.icons groups distinct colors", function()
            local result = build_with_mini()
            assert.not_equal(result.MiniIconsRed.fg, result.MiniIconsBlue.fg)
            assert.not_equal(result.MiniIconsGreen.fg, result.MiniIconsYellow.fg)
        end)

        it("links diff overlay groups to the core Diff* groups", function()
            local result = build_with_mini()
            assert.equal("DiffAdd", result.MiniDiffOverAdd.link)
            assert.equal("DiffText", result.MiniDiffOverChange.link)
            assert.equal("DiffDelete", result.MiniDiffOverDelete.link)
        end)
    end)

    describe("apply", function()
        it("sets highlight groups via nvim_set_hl", function()
            local hl_defs = {
                TestApplyGroup = { fg = "#ff0000", bg = "#000000" },
            }
            highlights.apply(hl_defs)
            local hl = vim.api.nvim_get_hl(0, { name = "TestApplyGroup" })
            assert.is_table(hl)
        end)
    end)
end)
