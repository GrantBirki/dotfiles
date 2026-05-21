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
- `~/.local/bin/git-secretive-ssh`
- `~/.local/bin/git-secretive-ssh-keygen`
- optionally `~/.config/git/secretive_git_key.pub` when the ignored local source exists
- optionally `~/.config/git/allowed_signers` when the ignored local source exists
- `~/.config/karabiner/karabiner.json`
- `~/.config/alacritty/alacritty.toml`
- `~/Library/Application Support/Code/User/settings.json`
- `~/Library/Application Support/Code/User/keybindings.json`
- `~/Library/Application Support/Code/User/tasks.json`
- `~/Library/Application Support/Code/User/snippets`

Karabiner is copied instead of symlinked because Karabiner rewrites its live config. The manifest uses a Karabiner-aware comparison that ignores runtime-managed fields.

## Git SSH

Git is configured to use Secretive-backed SSH for fetch, push, commit signing, and tag signing. The managed Git config points all Git SSH transport through `~/.local/bin/git-secretive-ssh` and all Git SSH signing through `~/.local/bin/git-secretive-ssh-keygen`.

The local public signing key and allowed signers file are intentionally ignored:

```text
configs/git/secretive_git_key.pub
configs/git/allowed_signers
```

When those files exist locally, `script/install` symlinks them into `~/.config/git/`. Do not commit them to this public repo.

Normal shells use Secretive's SSH agent socket when it is available and do not start Apple's `ssh-agent`. For old non-Git hosts that still require a disk private key, use the explicit one-off helper:

```bash
ssh-with-key ~/.ssh/legacy_key user@example.com
```

That helper clears `SSH_AUTH_SOCK` for the one command and does not add the disk key to an agent.

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
