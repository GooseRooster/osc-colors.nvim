describe("capability", function()
    local capability
    local ESC, ST = "\027", "\027\\"

    before_each(function()
        capability = require("osc-colors.capability")
    end)

    describe("probe_batch", function()
        it("queries the RGB and Tc caps over DCS", function()
            local batch = capability.probe_batch()
            assert.is_truthy(batch:find("P%+q524742", 1, false)) -- hex("RGB")
            assert.is_truthy(batch:find("P%+q5463", 1, false)) -- hex("Tc")
            assert.equal(2, select(2, batch:gsub(ESC .. "P%+q", "")))
        end)
    end)

    describe("parse_dcs", function()
        it("parses an xterm-style success reply naming one cap", function()
            local r = capability.parse_dcs(ESC .. "P1+r524742" .. ST)
            assert.is_table(r)
            assert.is_true(r.caps.RGB)
        end)

        it("parses a joined multi-cap success reply", function()
            local r = capability.parse_dcs(ESC .. "P1+r524742;5463" .. ST)
            assert.is_true(r.caps.RGB)
            assert.is_true(r.caps.Tc)
        end)

        it("parses a valued cap reply and keeps the name", function()
            -- Co = hex("Co") = 436f, value "256" hex-encoded
            local r = capability.parse_dcs(ESC .. "P1+r436f=323536" .. ST)
            assert.is_true(r.caps.Co)
        end)

        it("parses a kitty-style named failure reply", function()
            local r = capability.parse_dcs(ESC .. "P0+r524742" .. ST)
            assert.is_table(r)
            assert.equal("RGB", r.unsupported)
            assert.is_nil(next(r.caps))
        end)

        it("ignores a bare xterm-style failure reply (unattributable)", function()
            assert.is_nil(capability.parse_dcs(ESC .. "P0+r" .. ST))
        end)

        it("ignores non-XTGETTCAP sequences", function()
            assert.is_nil(capability.parse_dcs(ESC .. "]11;rgb:1a1a/1a1a/1a1a" .. ST))
            assert.is_nil(capability.parse_dcs(ESC .. "Ptmux;" .. ESC .. "]4;1;?" .. ST))
        end)
    end)

    describe("absorb", function()
        it("records probed caps and marks the probe answered", function()
            local state = { caps = {}, answered = false }
            capability.absorb(state, capability.parse_dcs(ESC .. "P1+r524742" .. ST))
            assert.is_true(state.caps.RGB)
            assert.is_true(state.answered)
        end)

        it("marks a named RGB/Tc failure as answered without confirming caps", function()
            local state = { caps = {}, answered = false }
            capability.absorb(state, capability.parse_dcs(ESC .. "P0+r524742" .. ST))
            assert.is_nil(state.caps.RGB)
            assert.is_true(state.answered)
        end)

        it("ignores replies naming caps outside the RGB/Tc probe", function()
            -- e.g. a reply to Neovim's own XTGETTCAP traffic for `Ms`
            local state = { caps = {}, answered = false }
            capability.absorb(state, capability.parse_dcs(ESC .. "P1+r4d73=1b5d35323b3f" .. ST))
            assert.is_false(state.answered)
            assert.equal(0, vim.tbl_count(state.caps))
        end)
    end)

    describe("classify", function()
        it("truecolor when XTGETTCAP confirms RGB", function()
            local r = capability.classify({ xtgettcap = { RGB = true }, xtgettcap_answered = true })
            assert.equal("truecolor", r.tier)
            assert.is_truthy(r.evidence.reason:find("RGB"))
        end)

        it("truecolor when XTGETTCAP confirms Tc", function()
            local r = capability.classify({ xtgettcap = { Tc = true }, xtgettcap_answered = true })
            assert.equal("truecolor", r.tier)
        end)

        it("truecolor from COLORTERM=truecolor", function()
            local r = capability.classify({ colorterm = "truecolor" })
            assert.equal("truecolor", r.tier)
        end)

        it("truecolor from COLORTERM=24bit", function()
            local r = capability.classify({ colorterm = "24bit" })
            assert.equal("truecolor", r.tier)
        end)

        it("truecolor from $TERM ending in -direct", function()
            local r = capability.classify({ term = "xterm-direct" })
            assert.equal("truecolor", r.tier)
        end)

        it("256 when XTGETTCAP answered but no RGB/Tc confirmed (probed negative)", function()
            local r = capability.classify({ xtgettcap_answered = true, term = "xterm-256color" })
            assert.equal("256", r.tier)
        end)

        it("unknown when nothing answers and no env signal exists", function()
            local r = capability.classify({ term = "xterm-256color" })
            assert.equal("unknown", r.tier)
        end)

        it("unknown for no signals at all", function()
            local r = capability.classify({})
            assert.equal("unknown", r.tier)
        end)

        it("probed truecolor wins over a missing/absent COLORTERM", function()
            local r = capability.classify({ xtgettcap = { RGB = true }, colorterm = nil, term = "screen" })
            assert.equal("truecolor", r.tier)
        end)

        it("records the raw signals in evidence", function()
            local r = capability.classify({ colorterm = "truecolor", term = "xterm-256color" })
            assert.equal("truecolor", r.evidence.signals.colorterm)
            assert.equal("xterm-256color", r.evidence.signals.term)
        end)
    end)

    describe("describe", function()
        it("summarizes tier and reason", function()
            local s = capability.describe({ tier = "truecolor", evidence = { reason = "env:COLORTERM=truecolor" } })
            assert.is_truthy(s:find("^truecolor "))
        end)

        it("handles a missing capability gracefully", function()
            assert.is_truthy(capability.describe(nil):find("unknown"))
        end)
    end)
end)
