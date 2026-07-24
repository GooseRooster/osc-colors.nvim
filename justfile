test filter="":
    vusted tests/ {{ if filter != "" { "--filter=" + filter } else { "" } }}

test-file file:
    vusted {{ file }}

lint:
    luacheck lua/ tests/

fmt:
    stylua lua/ tests/

fmt-check:
    stylua --check lua/ tests/

check:
    lua-language-server --check lua/ --configpath $(pwd)/.luarc.json

docs:
    lemmy-help lua/osc-colors/init.lua lua/osc-colors/config.lua > doc/osc-colors.txt
    # Runs Neovim in non-interactive batch mode, with no config/state, to
    # generate help tags for doc/
    nvim -N -u NONE -i NONE -n -E -s -V1 -c "helptags $(pwd)/doc" +quit!

list:
    @just --list
