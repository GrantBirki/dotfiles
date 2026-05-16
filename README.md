# dotfiles

Personal macOS dotfiles and terminal/editor configuration.

## Support

This repo is intentionally macOS-only. It manages Bash-focused shell dotfiles,
Alacritty, Karabiner-Elements, and VS Code configuration for my local Mac setup.

## Setup

1. Clone this repository.
2. Run `script/bootstrap` to install the vendored Ruby helper environment.
3. Preview the managed symlinks with `script/install --dry-run`.
4. Run `script/install`.
5. Run `source ~/.bashrc` in existing shells, or open a new terminal.

`script/install` reads `install.yml`, creates symlinks for managed files, moves
replaced targets into `~/dotfiles_old`, installs the pinned VS Code extension
list, and writes install state to `.dotfiles/state/` inside the repo. The state
directory is ignored by git.

VS Code settings and keybindings are symlinked into
`~/Library/Application Support/Code/User`, so edits made through VS Code update
the files tracked in `configs/vsc/`.

If a managed file needs to be restored from the latest install state, run
`script/restore`. Use `script/restore --dry-run` to preview restore actions, or
`script/restore --state PATH` to restore from a specific state file.

## Scripts

- `script/bootstrap`: install Ruby helpers from the committed Bundler config and vendored cache.
- `script/install`: symlink the manifest-managed macOS dotfiles/configs into place and install pinned VS Code extensions.
- `script/restore`: restore managed paths from a prior install state file.
- `script/doctor`: check local prerequisites, manifest validity, symlink health, and install state.
- `script/test`: run syntax, config, alias metadata, and cleanup checks.
- `script/vsc-extension-bulk-install`: install VS Code extensions from the tracked macOS extension list.

## Structure

- `install.yml`: manifest of files managed by `script/install`.
- `dotfiles/`: shell, Git, Ruby, and alias metadata.
- `shell/`: modular Bash startup code and user-facing shell functions.
- `configs/alacritty/`: macOS Alacritty config.
- `configs/karabiner/`: Karabiner-Elements config.
- `configs/vsc/`: VS Code settings, keybindings, and extensions.
- `lib/dotfiles/`: Ruby helpers used by scripts.

## Maintenance

Run `script/test` before publishing changes. The checks are intentionally
local and generic: they validate syntax, structured config, alias metadata, the
install manifest, and stale platform-specific paths without committing
private-context scanners into the public repo.
