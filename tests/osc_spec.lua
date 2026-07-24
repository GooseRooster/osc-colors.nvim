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
end)
