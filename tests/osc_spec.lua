-- osc.lua's query/parse/synthesize helpers are module-local by design (they
-- have no reason to be a public API), so these tests exercise them through
-- the public surface: `refresh_async` fed simulated `TermResponse` autocmd
-- events, and `load_cached()`/the resulting cache file.

describe("osc", function()
    local osc
    local scratch_cache_dir

    local function fire(sequence)
        vim.api.nvim_exec_autocmds("TermResponse", { data = { sequence = sequence } })
    end

    -- A full round of replies: bg, fg, then the six ANSI hue queries
    -- osc-colors sends (red, green, yellow, blue, magenta, cyan).
    local function fire_full_round(overrides)
        overrides = overrides or {}
        fire("\027]11;rgb:" .. (overrides.bg or "1a1a/1a1a/1a1a") .. "\027\\")
        fire("\027]10;rgb:" .. (overrides.fg or "ffff/ffff/ffff") .. "\027\\")
        local hues = overrides.hues
            or {
                "\027]4;1;rgb:ff00/0000/0000\027\\", -- red
                "\027]4;2;rgb:0000/ff00/0000\027\\", -- green
                "\027]4;3;rgb:ffff/ff00/0000\027\\", -- yellow
                "\027]4;4;rgb:0000/0000/ff00\027\\", -- blue
                "\027]4;5;rgb:ff00/0000/ff00\027\\", -- magenta
                "\027]4;6;rgb:0000/ffff/ff00\027\\", -- cyan
            }
        for _, seq in ipairs(hues) do
            fire(seq)
        end
    end

    -- `refresh_async`'s success path calls back from inside `vim.schedule`,
    -- so a plain synchronous fire-and-check won't see the result -- the main
    -- loop needs a chance to run the scheduled callback first.
    local function refresh_and_wait(overrides)
        local result, done = "not-yet-called", false
        osc.refresh_async(function(p)
            result = p
            done = true
        end)
        fire_full_round(overrides)
        vim.wait(200, function()
            return done
        end)
        assert.is_true(done, "refresh_async callback never fired")
        return result
    end

    before_each(function()
        scratch_cache_dir = vim.fn.tempname()
        vim.env.XDG_CACHE_HOME = scratch_cache_dir
        -- stdpath("cache") appends "/nvim" to $XDG_CACHE_HOME; osc.lua computes
        -- its cache file path from stdpath("cache") at require-time, so the
        -- directory must exist before that require happens.
        vim.fn.mkdir(vim.fn.stdpath("cache"), "p")

        package.loaded["osc-colors.osc"] = nil
        osc = require("osc-colors.osc")
    end)

    after_each(function()
        vim.fn.delete(scratch_cache_dir, "rf")
        vim.env.XDG_CACHE_HOME = nil
    end)

    describe("load_cached", function()
        it("returns nil when no cache file exists", function()
            assert.is_nil(osc.load_cached())
        end)
    end)

    describe("refresh_async", function()
        it("synthesizes a full base16 palette from OSC replies", function()
            local result = refresh_and_wait()

            assert.is_table(result)
            assert.equal("#1a1a1a", result.base00)
            assert.equal("#ffffff", result.base07)
            assert.equal("#ff0000", result.base08)
            assert.equal("#00ff00", result.base0B)
            assert.equal("#ffff00", result.base0A)
            assert.equal("#0000ff", result.base0D)
            assert.equal("#ff00ff", result.base0E)
            assert.equal("#00ffff", result.base0C)
        end)

        it("derives the grayscale ramp between bg and fg", function()
            local result = refresh_and_wait({ bg = "0000/0000/0000", fg = "ffff/ffff/ffff" })

            assert.equal("#000000", result.base00)
            assert.equal("#ffffff", result.base07)
            -- base03 sits farther from black toward white than base02 does.
            assert.is_true(result.base03 > result.base02)
            assert.is_true(result.base06 > result.base05)
        end)

        it("classifies variant as dark when background luminance is low", function()
            local result = refresh_and_wait({ bg = "0000/0000/0000" })

            assert.equal("dark", result.variant)
        end)

        it("classifies variant as light when background luminance is high", function()
            local result = refresh_and_wait({ bg = "ffff/ffff/ffff", fg = "0000/0000/0000" })

            assert.equal("light", result.variant)
        end)

        it("writes a disk cache readable by load_cached", function()
            refresh_and_wait()

            local cached = osc.load_cached()
            assert.is_table(cached)
            assert.equal("#1a1a1a", cached.base00)
        end)

        it("succeeds on a second, independent round after the first fully completes", function()
            -- Regression test for a bug where a live refresh worked once
            -- per process but silently no-op'd on every later manual
            -- refresh: exercises `refresh_async` twice sequentially on the
            -- *same* module instance (no reload in between), the exact
            -- "second real-world refresh in one session" scenario.
            local first = refresh_and_wait({ bg = "1a1a/1a1a/1a1a" })
            assert.is_table(first)
            assert.equal("#1a1a1a", first.base00)

            local second = refresh_and_wait({ bg = "2b2b/2b2b/2b2b" })
            assert.is_table(second)
            assert.equal("#2b2b2b", second.base00)
            assert.are_not.same(first.base00, second.base00)
        end)

        it("calls back with nil when nothing changed since the cache", function()
            refresh_and_wait()

            package.loaded["osc-colors.osc"] = nil
            osc = require("osc-colors.osc")

            local result = refresh_and_wait()

            assert.is_nil(result)
        end)

        it("calls back with nil on timeout when the terminal never answers", function()
            local result, done = "not-yet-called", false
            osc.refresh_async(function(p)
                result = p
                done = true
            end)

            vim.wait(500, function()
                return done
            end)

            assert.is_true(done)
            assert.is_nil(result)
        end)

        it("ignores a second concurrent call while one is in flight", function()
            local calls = 0
            osc.refresh_async(function()
                calls = calls + 1
            end)
            osc.refresh_async(function()
                calls = calls + 1
            end)
            fire_full_round()
            vim.wait(200, function()
                return calls > 0
            end)

            assert.equal(1, calls)
        end)
    end)

    describe("reply format robustness", function()
        it("parses 8-bit channel replies (rgb:rr/gg/bb)", function()
            local result = refresh_and_wait({ bg = "1a/1a/1a", fg = "ff/ff/ff" })

            assert.is_table(result)
            assert.equal("#1a1a1a", result.base00)
            assert.equal("#ffffff", result.base07)
        end)

        it("parses 1-digit channel replies (rgb:h/h/h)", function()
            local result = refresh_and_wait({ bg = "0/0/0", fg = "f/f/f" })

            assert.is_table(result)
            assert.equal("#000000", result.base00)
            assert.equal("#ffffff", result.base07)
        end)

        it("parses rgba replies, ignoring the alpha channel", function()
            local result, done = "not-yet-called", false
            osc.refresh_async(function(p)
                result = p
                done = true
            end)
            fire("\027]11;rgba:1a1a/1a1a/1a1a/ffff\027\\")
            fire("\027]10;rgba:ffff/ffff/ffff/ffff\027\\")
            for _, seq in ipairs({
                "\027]4;1;rgba:ff00/0000/0000/ffff\027\\",
                "\027]4;2;rgba:0000/ff00/0000/ffff\027\\",
                "\027]4;3;rgba:ffff/ff00/0000/ffff\027\\",
                "\027]4;4;rgba:0000/0000/ff00/ffff\027\\",
                "\027]4;5;rgba:ff00/0000/ff00/ffff\027\\",
                "\027]4;6;rgba:0000/ffff/ff00/ffff\027\\",
            }) do
                fire(seq)
            end
            vim.wait(200, function()
                return done
            end)

            assert.is_table(result)
            assert.equal("#1a1a1a", result.base00)
            assert.equal("#ff0000", result.base08)
        end)

        it("parses #-prefixed color specs", function()
            local result, done = "not-yet-called", false
            osc.refresh_async(function(p)
                result = p
                done = true
            end)
            fire("\027]11;#1a1a1a\027\\")
            fire("\027]10;#ffffff\027\\")
            fire("\027]4;1;#ff0000\027\\")
            fire("\027]4;2;#00ff00\027\\")
            fire("\027]4;3;#ffff00\027\\")
            fire("\027]4;4;#0000ff\027\\")
            fire("\027]4;5;#ff00ff\027\\")
            fire("\027]4;6;#00ffff\027\\")
            vim.wait(200, function()
                return done
            end)

            assert.is_table(result)
            assert.equal("#1a1a1a", result.base00)
            assert.equal("#ffffff", result.base07)
            assert.equal("#ff0000", result.base08)
        end)

        it("parses BEL-terminated replies", function()
            local result, done = "not-yet-called", false
            osc.refresh_async(function(p)
                result = p
                done = true
            end)
            fire("\027]11;rgb:1a1a/1a1a/1a1a\007")
            fire("\027]10;rgb:ffff/ffff/ffff\007")
            fire("\027]4;1;rgb:ff00/0000/0000\007")
            fire("\027]4;2;rgb:0000/ff00/0000\007")
            fire("\027]4;3;rgb:ffff/ff00/0000\007")
            fire("\027]4;4;rgb:0000/0000/ff00\007")
            fire("\027]4;5;rgb:ff00/0000/ff00\007")
            fire("\027]4;6;rgb:0000/ffff/ff00\007")
            vim.wait(200, function()
                return done
            end)

            assert.is_table(result)
            assert.equal("#1a1a1a", result.base00)
        end)

        it("parses a batched multi-pair OSC 4 reply", function()
            local result, done = "not-yet-called", false
            osc.refresh_async(function(p)
                result = p
                done = true
            end)
            fire("\027]11;rgb:1a1a/1a1a/1a1a\027\\")
            fire("\027]10;rgb:ffff/ffff/ffff\027\\")
            fire("\027]4;1;rgb:ff00/0000/0000;2;rgb:0000/ff00/0000\027\\")
            fire("\027]4;3;rgb:ffff/ff00/0000;4;rgb:0000/0000/ff00\027\\")
            fire("\027]4;5;rgb:ff00/0000/ff00;6;rgb:0000/ffff/ff00\027\\")
            vim.wait(200, function()
                return done
            end)

            assert.is_table(result)
            assert.equal("#ff0000", result.base08)
            assert.equal("#00ff00", result.base0B)
            assert.equal("#00ffff", result.base0C)
        end)
    end)

    describe("capability probing", function()
        local saved_colorterm, saved_term

        before_each(function()
            saved_colorterm = vim.env.COLORTERM
            saved_term = vim.env.TERM
            vim.env.COLORTERM = nil
            vim.env.TERM = "xterm-256color"
        end)

        after_each(function()
            vim.env.COLORTERM = saved_colorterm
            vim.env.TERM = saved_term
        end)

        local function fire_dcs_truecolor()
            fire("\027P1+r524742\027\\") -- RGB confirmed
        end

        local function fire_dcs_negative()
            fire("\027P0+r524742\027\\") -- RGB: kitty-style named failure
            fire("\027P0+r5463\027\\") -- Tc: named failure
        end

        it("classifies tier=truecolor when XTGETTCAP confirms RGB during the round", function()
            local result, done = "not-yet-called", false
            osc.refresh_async(function(p)
                result = p
                done = true
            end)
            fire_dcs_truecolor()
            fire_full_round()
            vim.wait(200, function()
                return done
            end)

            assert.is_table(result)
            assert.equal("truecolor", result.capability.tier)
        end)

        it("classifies tier=256 when XTGETTCAP answers negative without env signals", function()
            local result, done = "not-yet-called", false
            osc.refresh_async(function(p)
                result = p
                done = true
            end)
            fire_dcs_negative()
            fire_full_round()
            vim.wait(200, function()
                return done
            end)

            assert.is_table(result)
            assert.equal("256", result.capability.tier)
        end)

        it("classifies tier=unknown when nothing answers and no env signal exists", function()
            local result = refresh_and_wait()

            assert.is_table(result)
            assert.equal("unknown", result.capability.tier)
        end)

        it("classifies tier=truecolor from COLORTERM without any DCS reply", function()
            vim.env.COLORTERM = "truecolor"
            local result = refresh_and_wait()

            assert.is_table(result)
            assert.equal("truecolor", result.capability.tier)
        end)

        it("persists the capability tier in the cache", function()
            local result, done = "not-yet-called", false
            osc.refresh_async(function(p)
                result = p
                done = true
            end)
            fire_dcs_truecolor()
            fire_full_round()
            vim.wait(200, function()
                return done
            end)

            assert.is_table(result)
            local cached = osc.load_cached()
            assert.is_table(cached)
            assert.equal("truecolor", cached.capability.tier)
            assert.equal(2, cached.version)
        end)

        it("repaints when only the capability tier changed", function()
            local first, done1 = nil, false
            osc.refresh_async(function(p)
                first = p
                done1 = true
            end)
            fire_dcs_truecolor()
            fire_full_round()
            vim.wait(200, function()
                return done1
            end)
            assert.is_table(first)
            assert.equal("truecolor", first.capability.tier)

            -- same colors, but this round the terminal no longer confirms
            -- RGB and no env signal exists -> tier unknown -> palette differs
            local second, done2 = nil, false
            osc.refresh_async(function(p)
                second = p
                done2 = true
            end)
            fire_full_round()
            vim.wait(200, function()
                return done2
            end)

            assert.is_table(second)
            assert.equal("unknown", second.capability.tier)
            assert.equal(first.base00, second.base00)
        end)

        it("loads a legacy v1 cache and reports an unknown tier", function()
            local path = vim.fn.stdpath("cache") .. "/osc-colors-palette.lua"
            vim.fn.writefile({
                "return {",
                '  variant = "dark",',
                '  base00 = "#000000",',
                '  base01 = "#111111",',
                '  base02 = "#222222",',
                '  base03 = "#333333",',
                '  base04 = "#444444",',
                '  base05 = "#555555",',
                '  base06 = "#666666",',
                '  base07 = "#777777",',
                '  base08 = "#880000",',
                '  base09 = "#ff9900",',
                '  base0A = "#ffff00",',
                '  base0B = "#00ff00",',
                '  base0C = "#00ffff",',
                '  base0D = "#0000ff",',
                '  base0E = "#ff00ff",',
                '  base0F = "#880000",',
                "}",
            }, path)

            local cached = osc.load_cached()
            assert.is_table(cached)
            assert.equal("#000000", cached.base00)
            assert.equal("unknown", cached.capability.tier)
        end)
    end)

    describe("256-cube query", function()
        local function fire_cube(indices)
            for _, i in ipairs(indices) do
                fire(string.format("\027]4;%d;rgb:%02x00/%02x00/%02x00\027\\", i, i, i, i))
            end
        end

        local function all_cube_slots()
            local all = {}
            for i = 16, 255 do
                table.insert(all, i)
            end
            return all
        end

        it("runs the cube round when the predicate asks for it", function()
            local result, done = "not-yet-called", false
            osc.refresh_async(function(p)
                result = p
                done = true
            end, {
                cube = function()
                    return true
                end,
            })
            fire_full_round()
            fire_cube({ 16, 17, 18, 255 })
            assert.is_true(vim.wait(1000, function()
                return done
            end))

            assert.is_table(result)
            assert.is_table(result.cube)
            assert.equal(4, vim.tbl_count(result.cube))
            assert.equal("#101010", result.cube[16])
            assert.equal("#ffffff", result.cube[255])
        end)

        it("completes without waiting for the timeout once every cube slot answered", function()
            local t0 = vim.uv.hrtime()
            local result, done = "not-yet-called", false
            osc.refresh_async(function(p)
                result = p
                done = true
            end, {
                timeout_ms = 5000,
                cube = function()
                    return true
                end,
            })
            fire_full_round()
            fire_cube(all_cube_slots())
            assert.is_true(vim.wait(1000, function()
                return done
            end))
            local elapsed_ms = (vim.uv.hrtime() - t0) / 1e6

            assert.is_table(result)
            assert.equal(240, vim.tbl_count(result.cube))
            -- finished via cube_complete(), not the 5s timeout
            assert.is_true(elapsed_ms < 4500)
        end)

        it("keeps a partial cube when the cube round times out", function()
            local result, done = "not-yet-called", false
            osc.refresh_async(function(p)
                result = p
                done = true
            end, {
                timeout_ms = 100,
                cube = function()
                    return true
                end,
            })
            fire_full_round()
            fire_cube({ 16, 17 })
            assert.is_true(vim.wait(1000, function()
                return done
            end))

            assert.is_table(result)
            assert.equal(2, vim.tbl_count(result.cube))
        end)

        it("drops an empty cube instead of caching junk", function()
            local result, done = "not-yet-called", false
            osc.refresh_async(function(p)
                result = p
                done = true
            end, {
                timeout_ms = 80,
                cube = function()
                    return true
                end,
            })
            fire_full_round()
            assert.is_true(vim.wait(1000, function()
                return done
            end))

            assert.is_table(result)
            assert.is_nil(result.cube)
        end)

        it("skips the cube round when the predicate declines", function()
            local result, done = "not-yet-called", false
            osc.refresh_async(function(p)
                result = p
                done = true
            end, {
                cube = function()
                    return false
                end,
            })
            fire_full_round()
            assert.is_true(vim.wait(1000, function()
                return done
            end))

            assert.is_table(result)
            assert.is_nil(result.cube)
        end)

        it("skips re-querying the cube when palette and cached cube are unchanged", function()
            local first, done1 = nil, false
            osc.refresh_async(function(p)
                first = p
                done1 = true
            end, {
                cube = function()
                    return true
                end,
            })
            fire_full_round()
            fire_cube(all_cube_slots())
            assert.is_true(vim.wait(1000, function()
                return done1
            end))
            assert.is_table(first)
            assert.is_table(first.cube)

            -- second round: same colors, cache carries the cube -> cube
            -- query skipped, nothing changed -> nil
            local second, done2 = "not-yet-called", false
            osc.refresh_async(function(p)
                second = p
                done2 = true
            end, {
                cube = function()
                    return true
                end,
            })
            fire_full_round()
            assert.is_true(vim.wait(1000, function()
                return done2
            end))

            assert.is_nil(second)
        end)

        it("persists the cube in the cache", function()
            local _, done1 = nil, false
            osc.refresh_async(function(_p)
                done1 = true
            end, {
                cube = function()
                    return true
                end,
            })
            fire_full_round()
            fire_cube({ 16, 200, 255 })
            assert.is_true(vim.wait(1000, function()
                return done1
            end))

            local cached = osc.load_cached()
            assert.is_table(cached.cube)
            assert.equal("#c8c8c8", cached.cube[200])
        end)
    end)
end)
