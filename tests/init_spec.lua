describe("init", function()
    local oc
    local scratch_cache_dir

    local function reset_modules()
        package.loaded["osc-colors"] = nil
        package.loaded["osc-colors.config"] = nil
        package.loaded["osc-colors.colors"] = nil
        package.loaded["osc-colors.highlights"] = nil
        package.loaded["osc-colors.highlights.core"] = nil
        package.loaded["osc-colors.highlights.syntax"] = nil
        package.loaded["osc-colors.highlights.treesitter"] = nil
        package.loaded["osc-colors.highlights.lsp"] = nil
        package.loaded["osc-colors.highlights.diagnostics"] = nil
        package.loaded["osc-colors.terminal"] = nil
        package.loaded["osc-colors.aliases"] = nil
        package.loaded["osc-colors.osc"] = nil
    end

    local fake_palette = {
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

    before_each(function()
        -- Fresh, empty cache dir per test so setup()'s "paint from cache"
        -- step is deterministic (never finds a leftover palette from another
        -- test's `apply()`/`refresh_async` call).
        scratch_cache_dir = vim.fn.tempname()
        vim.env.XDG_CACHE_HOME = scratch_cache_dir
        vim.fn.mkdir(vim.fn.stdpath("cache"), "p")

        vim.g.colors_name = nil
        reset_modules()
        oc = require("osc-colors")
    end)

    after_each(function()
        vim.fn.delete(scratch_cache_dir, "rf")
        vim.env.XDG_CACHE_HOME = nil
    end)

    describe("setup", function()
        it("can be called with no arguments", function()
            assert.has_no_error(function()
                oc.setup()
            end)
        end)

        it("can be called with custom options", function()
            assert.has_no_error(function()
                oc.setup({ ui = { transparent = true } })
            end)
        end)

        it("does not set a colorscheme when there is no cache and no query has resolved", function()
            oc.setup({ refresh_on = {} }) -- no autocmds, no OSC query fired

            assert.is_nil(vim.g.colors_name)
        end)

        it("creates the OscColorsRefresh command", function()
            oc.setup({ refresh_on = {} })

            local commands = vim.api.nvim_get_commands({})
            assert.is_not_nil(commands.OscColorsRefresh)
        end)

        it("registers an autocmd for each configured refresh_on event", function()
            oc.setup({ refresh_on = { "UIEnter", "FocusGained" } })

            local autocmds = vim.api.nvim_get_autocmds({ group = "osc_colors_refresh" })
            local events = {}
            for _, au in ipairs(autocmds) do
                events[au.event] = true
            end

            assert.is_true(events.UIEnter)
            assert.is_true(events.FocusGained)
        end)
    end)

    describe("apply", function()
        it("no-ops when given nil", function()
            oc.setup({ refresh_on = {} })
            vim.g.colors_name = "something-else"

            oc.apply(nil)

            assert.equal("something-else", vim.g.colors_name)
        end)

        it("sets vim.g.colors_name", function()
            oc.setup({ refresh_on = {} })

            oc.apply(fake_palette)

            assert.equal("osc-colors", vim.g.colors_name)
        end)

        it("sets termguicolors", function()
            vim.o.termguicolors = false
            oc.setup({ refresh_on = {} })

            oc.apply(fake_palette)

            assert.is_true(vim.o.termguicolors)
        end)

        it("sets background to match the palette variant", function()
            vim.o.background = "light"
            oc.setup({ refresh_on = {} })

            oc.apply(fake_palette)

            assert.equal("dark", vim.o.background)
        end)

        it("fires a ColorScheme autocmd", function()
            oc.setup({ refresh_on = {} })

            local fired = false
            vim.api.nvim_create_autocmd("ColorScheme", {
                callback = function()
                    fired = true
                end,
                once = true,
            })

            oc.apply(fake_palette)

            assert.is_true(fired)
        end)

        it("actually sets highlight groups", function()
            oc.setup({ refresh_on = {} })

            oc.apply(fake_palette)

            local hl = vim.api.nvim_get_hl(0, { name = "Normal" })
            assert.is_not_nil(hl.bg)
        end)
    end)

    describe("get_palette / get_palette_aliases", function()
        it("return nil before anything is applied", function()
            oc.setup({ refresh_on = {} })

            assert.is_nil(oc.get_palette())
            assert.is_nil(oc.get_palette_aliases())
        end)

        it("return the resolved palette/aliases after apply", function()
            oc.setup({ refresh_on = {} })

            oc.apply(fake_palette)

            assert.is_table(oc.get_palette())
            assert.equal("#000000", oc.get_palette().base00)

            assert.is_table(oc.get_palette_aliases())
            assert.equal("#880000", oc.get_palette_aliases().red)
        end)
    end)

    describe("refresh", function()
        it("delegates to osc.refresh_async", function()
            local received_callback = nil
            package.preload["osc-colors.osc"] = function()
                return {
                    load_cached = function()
                        return nil
                    end,
                    refresh_async = function(cb)
                        received_callback = cb
                    end,
                }
            end
            reset_modules()
            oc = require("osc-colors")
            oc.setup({ refresh_on = {} })

            oc.refresh()

            package.preload["osc-colors.osc"] = nil

            assert.is_function(received_callback)
            assert.equal(oc.apply, received_callback)
        end)
    end)
end)
