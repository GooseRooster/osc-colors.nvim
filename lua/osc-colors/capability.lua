-- Terminal color-capability probing.
--
-- osc-colors paints with real RGB hex, so the one capability question that
-- matters is whether the host terminal faithfully renders 24-bit color
-- ("truecolor"), only renders an indexed 256-color palette, or is unknown.
-- The classic signal, $COLORTERM, is exactly the thing that dies in the
-- environments this plugin exists for -- containers strip it, SSH only
-- forwards it when both ends cooperate, multiplexers mangle the picture. So
-- env vars are treated as hints, never the decision-maker, and the
-- transport-agnostic authority is XTGETTCAP: a DCS query the *terminal*
-- answers through the same PTY that already carries the OSC 4/10/11 round
-- trip (Neovim's TermResponse event delivers DCS replies alongside OSC).
--
-- Decision matrix (first match wins):
--   1. XTGETTCAP confirms RGB or Tc   -> truecolor (probed; strongest)
--   2. $COLORTERM = truecolor|24bit   -> truecolor (env; strong when present)
--   3. $TERM ends in -direct          -> truecolor
--   4. XTGETTCAP answered, no RGB/Tc  -> 256 (a probed negative from a
--      terminal honest enough to implement the query at all)
--   5. anything else                  -> unknown
--
-- "unknown" is deliberately *not* downgraded to 256: a 256-only terminal
-- handed SGR 38;2;R;G;B approximates it to its cube and degrades gently,
-- while wrongly snapping a truecolor terminal to cube indices needlessly
-- loses fidelity. Unknown therefore means "assume truecolor", preserving
-- osc-colors' status-quo behavior of painting RGB unconditionally.

local M = {}

-- ASCII-hex encodings of the terminfo capability names we probe ("RGB",
-- "Tc"), as XTGETTCAP requires.
local CAP_RGB, CAP_TC = "524742", "5463"
local ESC, ST = "\027", "\027\\"

local function hexdecode(s)
    return (s:gsub("%x%x", function(h)
        return string.char(tonumber(h, 16))
    end))
end

-- : Query construction [[[
--
-- One DCS +q per capability, so replies map unambiguously to a single cap
-- (kitty answers per-cap anyway; xterm-style semicolon-joined replies are
-- parsed defensively too -- see parse_dcs).
--
-- Deliberately NOT wrapped in tmux passthrough when $TMUX is set: tmux
-- answers XTGETTCAP for itself, and tmux -- not the outer terminal -- is
-- the authority on what actually gets rendered through the multiplexer
-- layer. A passthrough-wrapped probe is silently dropped entirely when
-- tmux's allow-passthrough is off, which would turn the probe into a no-op
-- instead of a question answered by the rendering truth.
function M.probe_batch()
    return ESC .. "P+q" .. CAP_RGB .. ST .. ESC .. "P+q" .. CAP_TC .. ST
end

-- : ]]]

-- : Reply parsing [[[
--
-- XTGETTCAP replies come as DCS strings:
--   success:  ESC P 1 + r <hex> [ ; <hex> ... ] ESC \   (xterm joins caps)
--   failure:  ESC P 0 + r ESC \                            (xterm: no name)
--             ESC P 0 + r <hex> ESC \                      (kitty: named)
-- A success reply may carry a `=<hex>` value after a cap (string caps);
-- RGB/Tc are boolean-ish, so a bare cap name means "supported".
--
-- Returns `{ caps = { [name] = true } }`, `{ caps = {}, unsupported = name }`,
-- or nil when the sequence isn't attributable to our probe. A bare xterm
-- failure (`P0+r` with no cap name) is deliberately *not* recognized: it
-- cannot be attributed to this probe rather than any other client's
-- XTGETTCAP traffic (Neovim itself queries caps like `Ms` on recent
-- versions), and miscounting it here could downgrade a truecolor terminal.
function M.parse_dcs(sequence)
    local rest = sequence:match("P1%+r([^%c]*)")
    if rest then
        local caps = {}
        for part in rest:gmatch("[^;]+") do
            local cap_hex = part:match("^(%x+)")
            if cap_hex then
                caps[hexdecode(cap_hex)] = true
            end
        end
        if next(caps) == nil then
            return nil
        end
        return { caps = caps }
    end
    local fail = sequence:match("P0%+r([^%c]*)")
    if fail and fail:match("^%x+$") then
        return { caps = {}, unsupported = hexdecode(fail) }
    end
    return nil
end

--- Fold a parse_dcs result into a probe-state table
--- `{ caps = { [name] = true }, answered = bool }`. Replies naming
--- capabilities outside our RGB/Tc probe are ignored, for the attribution
--- reason described on parse_dcs.
---@param state { caps: table<string, boolean>, answered: boolean }
---@param dcs table parse_dcs result
---@return { caps: table<string, boolean>, answered: boolean }
function M.absorb(state, dcs)
    if dcs.caps then
        for name in pairs(dcs.caps) do
            if name == "RGB" or name == "Tc" then
                state.caps[name] = true
                state.answered = true
            end
        end
    end
    if dcs.unsupported == "RGB" or dcs.unsupported == "Tc" then
        state.answered = true
    end
    return state
end

-- : ]]]

-- : Tier decision [[[
--
-- Pure function over collected signals, so the whole matrix is unit-testable
-- without a live terminal.

---@param signals table collected signals: `xtgettcap` (confirmed caps), `xtgettcap_answered`, `colorterm`, `term`
---@return { tier: "truecolor"|"256"|"unknown", evidence: { reason: string, signals: table } }
function M.classify(signals)
    local caps = signals.xtgettcap or {}
    local colorterm = (signals.colorterm or ""):lower()
    local term = signals.term or ""

    local reason, tier
    if caps.RGB or caps.Tc then
        reason = "xtgettcap:" .. (caps.RGB and "RGB" or "Tc")
        tier = "truecolor"
    elseif colorterm == "truecolor" or colorterm == "24bit" then
        reason = "env:COLORTERM=" .. colorterm
        tier = "truecolor"
    elseif term:match("%-direct$") then
        reason = "env:TERM=" .. term
        tier = "truecolor"
    elseif signals.xtgettcap_answered then
        reason = "xtgettcap:negative (answered, no RGB/Tc)"
        tier = "256"
    else
        reason = "no positive signal (assuming truecolor)"
        tier = "unknown"
    end

    return {
        tier = tier,
        evidence = {
            reason = reason,
            signals = {
                xtgettcap = caps,
                xtgettcap_answered = signals.xtgettcap_answered == true,
                colorterm = signals.colorterm,
                term = signals.term,
            },
        },
    }
end

-- : ]]]

-- : Helpers for callers [[[
--
-- Environment snapshot, read once per refresh round by osc.lua and fed into
-- classify() alongside whatever the XTGETTCAP probe actually answered.
function M.env_signals()
    return {
        colorterm = vim.env.COLORTERM,
        term = vim.env.TERM,
    }
end

--- Human-readable summary for :checkhealth and debug output.
---@param capability { tier: string, evidence?: { reason?: string } }
---@return string
function M.describe(capability)
    if not capability or not capability.tier then
        return "unknown (no probe result)"
    end
    local reason = capability.evidence and capability.evidence.reason or "no evidence recorded"
    return string.format("%s (%s)", capability.tier, reason)
end

-- : ]]]

return M
