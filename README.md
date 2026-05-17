# dotfiles

Personal macOS dotfiles and terminal/editor configuration.

## Support

This repo is intentionally macOS-only. It manages Bash-focused shell dotfiles,
Alacritty, Karabiner-Elements, and VS Code configuration for my local Mac setup.

## Setup

1. Clone this repository.
2. Run `script/bootstrap` to install the vendored Ruby helper environment.
3. Preview the managed files with `script/install --dry-run`.
4. Run `script/install`.
5. Run `source ~/.bashrc` in existing shells, or open a new terminal.

`script/install` reads `install.yml`, creates symlinks or copies managed files,
moves replaced targets into `~/dotfiles_old`, reconciles VS Code extensions to
the tracked VS Code manifests, and writes install state to `.dotfiles/state/`
inside the repo. The state directory is ignored by git.

VS Code settings, keybindings, user tasks, and snippets are symlinked into
`~/Library/Application Support/Code/User`, so edits made through VS Code update
the publishable files tracked in `configs/vsc/`. MCP config is intentionally
local-only by default: `configs/vsc/mcp.json` is ignored by git and only managed
when that private file exists locally. `configs/vsc/extensions.yml` is the
authoritative extension inventory, including the baseline version and whether
the extension is allowed to auto-update. `configs/vsc/policy.yml` is the
machine-readable security policy for managed VS Code settings and selected
extension auto-update storage. The generated `extensions.allowed` setting pins
non-auto-update extensions to the manifest version and allows only stable
updates for the explicit auto-update exceptions.

If a managed file needs to be restored from the latest install state, run
`script/restore`. Use `script/restore --dry-run` to preview restore actions, or
`script/restore --state PATH` to restore from a specific state file.

## Scripts

- `script/bootstrap`: install Ruby helpers from the committed Bundler config and vendored cache.
- `script/install`: install the manifest-managed macOS dotfiles/configs into place and reconcile VS Code extensions to the tracked manifest.
- `script/restore`: restore managed paths from a prior install state file.
- `script/doctor`: check local prerequisites, manifest validity, managed-file health, and install state.
- `script/test`: run RSpec unit tests with 100% Ruby line coverage, plus syntax, config, alias metadata, and cleanup checks.
- `script/vscode`: validate, plan, apply, and doctor VS Code desired state.
- `script/vsc-extension-bulk-install`: compatibility wrapper around `script/vscode`.

## Structure

- `install.yml`: manifest of files managed by `script/install`.
- `dotfiles/`: shell, Git, Ruby, and alias metadata.
- `shell/`: modular Bash startup code and user-facing shell functions.
- `configs/alacritty/`: macOS Alacritty config.
- `configs/karabiner/`: Karabiner-Elements config.
- `configs/vsc/`: VS Code settings, keybindings, tasks, snippets, extension inventory, and policy.
- `lib/dotfiles/`: Ruby helpers used by scripts.
- `spec/`: RSpec unit tests for Ruby helpers and Ruby CLI entrypoints.

## Maintenance

Run `script/test` before publishing changes. The checks are intentionally
local and generic: they validate syntax, structured config, alias metadata, the
install manifest, RSpec coverage, and stale platform-specific paths without
committing private-context scanners into the public repo.
