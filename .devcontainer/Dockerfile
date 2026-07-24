# Dev environment for osc-colors.nvim: Neovim + the Lua test/lint/format/doc
# tooling the justfile expects (vusted, luacheck, stylua, lemmy-help), without
# requiring a local Nix/Lua/Rust toolchain.
#
# Based on the Rust devcontainer image purely for its preinstalled, already
# PATH-wired cargo/rustup -- stylua, lemmy-help, and just are Rust binaries
# with no prebuilt-binary story stable enough to hardcode a release URL for
# here, so `cargo install` is the least brittle way to get them.
FROM mcr.microsoft.com/devcontainers/rust:1

ARG NVIM_VERSION=stable

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
        lua5.1 \
        liblua5.1-0-dev \
        luarocks \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# Neovim: prebuilt release tarball, no build deps needed.
RUN curl -fsSL "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-x86_64.tar.gz" \
        -o /tmp/nvim.tar.gz \
    && tar -xzf /tmp/nvim.tar.gz -C /opt \
    && ln -s /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim \
    && rm /tmp/nvim.tar.gz

# vusted (runs busted specs inside a real Neovim) and luacheck are Luarocks
# packages -- the same tools the old Nix flake pulled from
# pkgs.luajitPackages.*.
RUN luarocks install busted \
    && luarocks install vusted \
    && luarocks install luacheck

USER vscode

# stylua (formatter), lemmy-help (vimdoc generator), just (command runner) --
# `just` duplicates the base image's apt availability in some Debian
# releases, but installing all three the same way keeps this Dockerfile from
# depending on which one happens to be packaged upstream this month.
RUN cargo install --locked stylua \
    && cargo install --locked --features cli lemmy-help \
    && cargo install --locked just
