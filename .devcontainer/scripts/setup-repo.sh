#!/usr/bin/env bash
# Baseline repo setup -- runs in every dev container (before the optional
# per-developer setup-local.sh).
set -euo pipefail

# Restore /tmp to sticky world-writable (1777). Some devcontainer Feature build
# steps leave /tmp as 0755 root-owned; under rootless-podman keep-id (non-root
# user) that makes /tmp unwritable and breaks any tool that creates temp dirs
# there. Features run after the Dockerfile, so fix it here. The user has
# passwordless sudo (common-utils).
sudo chmod 1777 /tmp

# Toolchain (Neovim, vusted, luacheck, stylua, lemmy-help, just) is baked into
# the Dockerfile -- nothing to restore per-repo. `just list` doubles as a
# sanity check that everything landed on PATH.
just list
