# Dev container

Neovim + the Lua test/lint/format/doc tooling the [justfile](../justfile) expects
(vusted, luacheck, stylua, lemmy-help) -- no local Nix/Lua/Rust toolchain needed.
Open with VS Code ("Reopen in Container") or the devcontainer CLI (`devcontainer
up`). See the repo root [README's Contributing section](../README.md#contributing)
for the `just` commands this container is built for.

## What's baked in
- Non-root `vscode` user under rootless-podman `--userns=keep-id` (workspace stays writable)
- `/tmp` restored to `1777` in post-create (Features can clobber it → breaks tools)
- Homebrew on `PATH` for every `exec` (brew is installed by the personal hook, not a Feature)
- **SSH agent forwarding** -- private keys never enter the container; GitHub's host
  key is pre-seeded so pushing just works
- Gitignored `local/` personalization hook (dotfiles/editor), never committed
- Nested `.gitignore` + `.gitattributes` so the container config is self-contained and LF-safe

## Host prerequisites
- **SSH agent** running with your git key loaded, launched from a shell where
  `SSH_AUTH_SOCK` is set (`ssh-add -l` to check).

## Personalization (optional)
Opt-in and never committed -- see [`local.example/README.md`](local.example/README.md).

## Files
- `devcontainer.json` -- the environment definition
- `Dockerfile` -- Neovim + vusted/luacheck/stylua/lemmy-help/just
- `scripts/setup-repo.sh` -- baseline setup (`/tmp` fix, `just list` sanity check)
- `scripts/setup-local.sh` -- runs your gitignored `local/setup.sh` if present
- `local.example/` -- template for personal setup
- `.gitignore` / `.gitattributes` -- nested, keep the container config self-contained + LF-safe
