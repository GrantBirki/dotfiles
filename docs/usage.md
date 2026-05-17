# Usage

This repo is intentionally macOS-only. It manages a single public baseline for local shell, terminal, keyboard, Git, Ruby, and VS Code configuration.

## Install

Bootstrap the vendored Ruby helper environment:

```bash
script/bootstrap
```

Preview changes before touching local files:

```bash
script/install --dry-run
```

Apply the managed config:

```bash
script/install
script/doctor
```

Open a new shell, or reload the current one:

```bash
source ~/.bashrc
```

## Managed Files

`script/install` reads `install.yml`, creates symlinks or copies managed files, moves replaced targets into `~/dotfiles_old`, reconciles VS Code desired state, and writes install state under `.dotfiles/state/`.

The manifest currently manages:

- `~/.bashrc`
- `~/.bash_aliases`
- `~/.bash_logout`
- `~/.profile`
- `~/.rubocop.yml`
- `~/.irbrc`
- `~/.gitconfig`
- `~/.config/karabiner/karabiner.json`
- `~/.config/alacritty/alacritty.toml`
- `~/Library/Application Support/Code/User/settings.json`
- `~/Library/Application Support/Code/User/keybindings.json`
- `~/Library/Application Support/Code/User/tasks.json`
- `~/Library/Application Support/Code/User/snippets`

Karabiner is copied instead of symlinked because Karabiner rewrites its live config. The manifest uses a Karabiner-aware comparison that ignores runtime-managed fields.

## Restore

Preview a restore from the latest install state:

```bash
script/restore --dry-run
```

Restore from the latest install state:

```bash
script/restore
```

Restore from a specific state file:

```bash
script/restore --state .dotfiles/state/install-YYYYMMDDHHMMSS.tsv
```
