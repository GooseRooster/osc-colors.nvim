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

# devcontainers/features/common-utils:2 has a regression where it creates
# (or recreates) ~/.local and ~/.config as root-owned after install, which
# breaks anything that subsequently tries to mkdir under them -- notably
# chezmoi (`chezmoi init` fails with "permission denied" on ~/.local/share/chezmoi),
# cargo, and any tool that lazy-creates XDG dirs. The fix has to run here in
# post-create: the Feature runs between the Dockerfile and us, so a Dockerfile
# chown would just be clobbered. Idempotent; ignores paths that don't exist yet.
sudo chown -R "$(id -u):$(id -g)" "$HOME/.local" "$HOME/.config" 2>/dev/null || true

# Toolchain (Neovim, vusted, luacheck, stylua, lemmy-help, just) is baked into
# the Dockerfile -- nothing to restore per-repo. `just list` doubles as a
# sanity check that everything landed on PATH.
just list
