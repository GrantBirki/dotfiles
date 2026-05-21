# AGENTS.md

Guidance for automated agents and human maintainers working in this repository.

This file is intentionally safe for a public repository. Do not add private
machine details, employer details, credentials, hostnames, API tokens, private
keys, or local incident notes here.

## Project Scope

This repository is a personal macOS dotfiles repo. It manages the user's shell,
Git, Ruby, Alacritty, Karabiner-Elements, and VS Code configuration for a Mac
development environment.

The repository is intentionally macOS-only. Do not reintroduce Linux, Windows,
Codespaces, WSL, or multi-platform local-dev branches unless the repository
owner explicitly asks for that direction. The current design assumes macOS and
keeps filenames generic because macOS is now the only supported platform.

The repo is public. Treat every committed byte as public-facing.

## Core Principles

- Prefer boring, inspectable shell and Ruby stdlib over dependencies.
- Do not add Ruby gems unless they are clearly necessary and approved by the
  repo owner.
- Keep install behavior idempotent and previewable with `--dry-run`.
- Keep private or work-specific local behavior out of committed files.
- Keep config paths simple now that macOS is the only supported platform.
- Prefer symlinks for managed files so local edits through normal apps can sync
  back to this repo. Use copies only for tools that rewrite symlinks or maintain
  runtime-only fields, such as Karabiner-Elements.
- Keep supply-chain automation conservative: pinned versions, cooldowns, small
  PRs, and manual review.

## Important Files And Directories

- `install.yml`: The canonical manifest for files managed by `script/install`.
- `script/install`: Installs manifest-managed files and reconciles VS Code
  extensions to the tracked manifest.
- `script/restore`: Restores files from a previous install state file.
- `script/doctor`: Checks local command availability, manifest validity, managed-file
  health, and install state.
- `script/test`: The repo-native validation entrypoint. Run this before pushing.
- `script/test-check`: Ruby validation helper called by `script/test` for
  JSONC, YAML, supply-chain, workflow, fixture, and public-safety checks.
- `script/manifest`: Ruby helper for validating and printing `install.yml`.
- `lib/dotfiles/manifest.rb`: Manifest parser and validation logic.
- `lib/dotfiles/installer.rb`: Ruby implementation behind `script/install`.
- `lib/dotfiles/restorer.rb`: Ruby implementation behind `script/restore`.
- `lib/dotfiles/doctor.rb`: Ruby implementation behind `script/doctor`.
- `lib/dotfiles/runtime.rb`: Small shared runtime helpers for command checks,
  path selection, timestamps, and restrained color formatting.
- `lib/dotfiles/test_checks.rb`: Test-time validators used by
  `script/test-check`. Keep validation logic here rather than embedding Ruby in
  Bash scripts.
- `script/vscode`: Strict VS Code desired-state manager with `validate`, `plan`,
  `apply`, and `doctor` subcommands.
- `script/vsc-extension-bulk-install`: Compatibility wrapper around
  `script/vscode`.
- `local-bin/git-secretive-ssh`: Git-only SSH transport wrapper that forces
  Secretive-backed public-key auth and disables disk-key/password fallbacks.
- `local-bin/git-secretive-ssh-keygen`: Git SSH signing wrapper that runs
  `ssh-keygen` with Secretive's agent socket and refuses non-managed signing
  key files for signing operations.
- `lib/dotfiles/vscode.rb`: VS Code manifest parser, planner, applier, and
  validation logic.
- `dotfiles/`: Shell, Git, Ruby, profile, and alias metadata.
- `shell/`: Modular Bash startup files.
- `shell/functions/`: User-facing Bash functions loaded by `.bash_aliases`.
- `configs/alacritty/`: Alacritty config. The active file is
  `configs/alacritty/alacritty.toml`.
- `configs/karabiner/`: Karabiner-Elements config.
- `configs/vsc/`: VS Code settings, keybindings, user tasks, snippets,
  extension inventory, and policy manifests. `configs/vsc/mcp.json` is
  intentionally ignored unless the owner explicitly decides to publish a reviewed
  MCP baseline.
- `.github/dependabot.yml`: Dependabot config with cooldowns and constrained PR
  volume.
- `.github/workflows/test.yml`: CI workflow that runs `script/bootstrap` and
  `script/test`.

## Installation Model

`script/install` is the main install entrypoint. It reads `install.yml` and
installs repo-managed files into the user's home directory.

Managed files currently include:

- `~/.bashrc`
- `~/.bash_aliases`
- `~/.bash_logout`
- `~/.profile`
- `~/.rubocop.yml`
- `~/.irbrc`
- `~/.gitconfig`
- `~/.local/bin/git-secretive-ssh`
- `~/.local/bin/git-secretive-ssh-keygen`
- Optionally `~/.config/git/secretive_git_key.pub` when the ignored local
  source `configs/git/secretive_git_key.pub` exists.
- Optionally `~/.config/git/allowed_signers` when the ignored local source
  `configs/git/allowed_signers` exists.
- `~/.config/karabiner/karabiner.json`
- `~/.config/alacritty/alacritty.toml`
- `~/Library/Application Support/Code/User/settings.json`
- `~/Library/Application Support/Code/User/keybindings.json`
- `~/Library/Application Support/Code/User/tasks.json`
- `~/Library/Application Support/Code/User/snippets`
- Optionally `~/Library/Application Support/Code/User/mcp.json` when the ignored
  local source `configs/vsc/mcp.json` exists.

Manifest fields:

- `id`: Stable identifier used in logs and state files.
- `source`: Repo-relative source path.
- `target`: Home-relative target path beginning with `~/`.
- `mode`: `symlink` or `copy`.
- `parent`: `create` creates the target parent directory; `require` skips when
  the target parent directory does not already exist.
- `compare`: Optional comparison strategy. Defaults to `exact`. Karabiner uses
  `karabiner` so runtime-managed `devices` and `virtual_hid_keyboard` fields do
  not make `script/doctor` fail.
- `optional`: Optional boolean. Use `true` only for private local config sources
  that must remain absent from normal public checkouts.

`script/install --dry-run` must remain safe and side-effect free. It should show
the install actions it would take and should call the VS Code extension installer
in dry-run mode.

`script/install --skip-vscode-extensions` skips extension management while still
installing manifest-managed files. Use it only when intentionally avoiding
VS Code changes for that run.

The installer writes state to `.dotfiles/state/install-*.tsv`, which is ignored
by git. Do not commit install state.

## Restore Model

`script/restore` uses the latest `.dotfiles/state/install-*.tsv` file by
default. It can also restore from an explicit state file:

```bash
script/restore --state .dotfiles/state/install-YYYYMMDDHHMMSS.tsv
```

Use `script/restore --dry-run` before restoring. The restore script should avoid
removing unexpected non-managed files and should report conflicts clearly.

## VS Code Management

VS Code settings, keybindings, user tasks, and snippets are symlinked into:

```text
~/Library/Application Support/Code/User/settings.json
~/Library/Application Support/Code/User/keybindings.json
~/Library/Application Support/Code/User/tasks.json
~/Library/Application Support/Code/User/snippets
```

That means edits made through VS Code should update the tracked files under
`configs/vsc/`.

VS Code MCP configuration is treated differently because it can reveal service
names, local command paths, endpoints, and tool wiring. The manifest has an
optional `vscode-mcp-private` entry for `configs/vsc/mcp.json`, but that source
is ignored by git and must not be staged unless the owner explicitly reviews and
approves publishing it. A local ignored MCP file can still be managed by
`script/install`.

Generated VS Code state such as `History`, `globalStorage`, `workspaceStorage`,
storage databases, and provider cache files must remain unmanaged and untracked.

VS Code extensions are tracked in:

```text
configs/vsc/extensions.yml
```

Non-extension VS Code policy is tracked in:

```text
configs/vsc/policy.yml
```

That file is authoritative. Each entry must include:

- `id`: Lowercase VS Code extension id, such as `publisher.extension`.
- `version`: Baseline version to install when the extension is missing.
- `auto_update`: Boolean policy flag.

Running `script/install` or `script/vscode apply` should install baseline
versions, downgrade or upgrade version mismatches for entries with
`auto_update: false`, keep newer installed versions for entries with
`auto_update: true`, uninstall user-installed extensions that are not listed, and
configure VS Code selected extension auto-update storage. `script/vscode plan`
must show the planned installs, version corrections, selected auto-update policy,
settings writes, warnings, and prunes without changing VS Code.

Example:

```yaml
extensions:
  - id: openai.chatgpt
    version: "26.513.21555"
    auto_update: true
```

Do not change `script/vsc-extension-bulk-install` to silently fall back to
unpinned installs. If `code --install-extension publisher.extension@version`
fails, that should be visible. The strict behavior is intentional because this
repo installs onto the user's primary machine.

VS Code settings should match `configs/vsc/policy.yml`. Global extension
auto-update stays disabled while update checks stay enabled. The selected
allowlist in `configs/vsc/extensions.yml` is applied to VS Code's local global
storage so only entries with `auto_update: true` can auto-update. The generated
`extensions.allowed` setting should allow only the manifest version for
non-auto-update extensions and stable releases for deliberate auto-update
exceptions. Extension recommendations, feedback, telemetry beyond
errors, and experiments should stay disabled. If Settings Sync is enabled in VS
Code, keep the Extensions sync resource disabled in the VS Code UI; there is no
committed wildcard extension sync ignore list in this repo.

Real VS Code apply must back up `state.vscdb` before writing selected
auto-update storage and must fail if VS Code is still running.

To refresh extension inventory manually:

```bash
code --list-extensions --show-versions
```

Convert the output into `configs/vsc/extensions.yml` entries and set
`auto_update` deliberately for each extension. Do not restore old extensions just
because they existed historically.

## Shell Layout

`dotfiles/.bashrc` is the interactive Bash entrypoint. It resolves
`DOTFILES_ROOT`, loads modules from `shell/`, and then loads `~/.bash_aliases`.

Top-level shell modules:

- `shell/path.bash`
- `shell/history.bash`
- `shell/homebrew.bash`
- `shell/completion.bash`
- `shell/prompt.bash`
- `shell/input.bash`
- `shell/ssh-gpg.bash`
- `shell/editor.bash`
- `shell/languages.bash`

User-facing command-like functions live in `shell/functions/` and are loaded by
`dotfiles/.bash_aliases`.

`shell/ssh-gpg.bash` must not start `/usr/bin/ssh-agent`. The supported Git
baseline is Secretive-backed SSH only. Keep any disk-key SSH usage behind the
explicit `ssh-with-key` helper for one-off non-Git legacy hosts.

`dotfiles/.gitconfig` must keep Git transport and signing on the Secretive
wrappers. Do not reintroduce classic GPG signing, direct private-key signing, or
default SSH identity discovery for Git operations.

When adding an alias or user-facing function:

1. Define the alias in `dotfiles/.bash_aliases` or the function in
   `shell/functions/`.
2. If it is user-facing, add it to `ALIASES_TRACKED_FUNCTIONS` when applicable.
3. Document it in `dotfiles/.aliases.yml`.
4. Run `script/test`.

Internal helper functions should be prefixed with `_` unless there is a strong
reason not to.

## Ruby And Dependencies

Ruby exists here to support local helper scripts, not to turn this repo into a
Ruby application.

The current preference is:

- Put repo orchestration in Ruby when it can be unit-tested. `script/install`,
  `script/restore`, `script/doctor`, `script/manifest`, `script/vscode`, and
  `script/vsc-extension-bulk-install` are Ruby entrypoints.
- Keep Bash for shell startup/configuration and for `script/test` orchestration
  where it is intentionally exercising shell behavior.
- Do not embed Ruby programs in Bash scripts with heredocs, `ruby -e`, or
  similar inline snippets when the logic can live in a dedicated Ruby file.
  Put that code in `lib/dotfiles/` or a Ruby `script/` entrypoint and cover it
  with RSpec.
- Use Ruby stdlib whenever possible.
- Keep `Gemfile` minimal.
- Keep `rspec` as the only top-level development gem unless the owner approves
  another dependency.
- Keep `.bundle/config` committed.
- Keep `vendor/cache/` populated with committed gem archives for every locked
  gem.
- Keep installed gems out of git via `vendor/gems/`.
- Use `script/bootstrap` as the helper environment bootstrap entrypoint.

Do not add gems for simple YAML, JSON, path, or shell tasks. Ruby stdlib already
covers those needs in this repo.

RSpec tests live under `spec/`. The coverage gate uses Ruby's built-in
`Coverage` module in `spec/spec_helper.rb`; do not add SimpleCov unless the
owner explicitly asks for a second testing dependency. Ruby library files and
Ruby CLI entrypoints should stay at 100% line coverage.

## Dependabot And Supply-Chain Posture

Dependabot is intentionally scoped to the real dependency surfaces in this repo:

- `bundler`
- `github-actions`

Do not add ecosystems to `.github/dependabot.yml` unless corresponding manifests
exist and the repo truly needs Dependabot to manage that surface.

The config should keep cooldowns. The current posture is to use
`cooldown.default-days: 45` so routine version updates wait before entering this
core machine-bootstrap repo.

`open-pull-requests-limit: 1` is intentional. This repo should not receive a
large stream of automated dependency PRs.

GitHub Actions should remain pinned to full commit SHAs with same-line version
comments where possible. If an action is updated, verify the new SHA and keep the
comment accurate.

## Public Safety Rules

This is a public repo. Before committing or pushing, inspect changes for:

- Credentials, tokens, private keys, session files, cookies, or auth config.
- Private hostnames, private URLs, private IPs, or internal service names.
- Employer-specific helpers, paths, prompts, socket names, or identity switching.
- Machine-local absolute paths that are not already part of the intentional
  public config.
- Generated state under `.dotfiles/`, `vendor/gems/`, `bin/`, or local cache
  directories.
- Old platform-specific config that no longer applies.

Do not add a committed scanner that includes private organization or employer
names as literal search terms. Keep committed validation generic and public-safe.
One-off local scans before publishing are fine, but do not encode private context
into the repository.

## Validation

Run this before committing:

```bash
script/test
git diff --check
script/manifest validate
script/install --dry-run
```

For VS Code extension changes, also run:

```bash
script/vscode validate
script/vscode plan
script/vsc-extension-bulk-install --dry-run
```

For local install health, run:

```bash
script/doctor
```

`script/doctor` may report expected issues on a machine that has not run
`script/install` yet or still points at older symlink targets. Do not treat that
as a repo failure without reading the specific issue lines.

## Common Failure Modes

### Broken Symlink After Rename

When a managed file is renamed, existing symlinks on the machine may still point
at the old repo path. The visible symptom is usually an app falling back to
defaults.

Example: if `configs/alacritty/alacritty.toml` is renamed, check:

```bash
readlink ~/.config/alacritty/alacritty.toml
```

Then run:

```bash
script/install --dry-run
script/install
```

or fix the symlink directly if the owner explicitly asks for a live repair.

### Karabiner Rewrites Its Config

Karabiner-Elements rewrites `~/.config/karabiner/karabiner.json` and can replace
a symlink with a regular file while adding runtime-managed fields. For that
reason the Karabiner manifest entry uses `mode: copy` and `compare: karabiner`,
not `mode: symlink`. Do not change it back to a symlink unless Karabiner behavior
changes and the repeated `script/install` / `script/doctor` loop proves stable.

### VS Code Extension Drift

The extension installer is strict by design. If a baseline version cannot be
installed, do not automatically strip the version and install latest. Investigate
whether the version was removed, renamed, or incorrectly recorded. If dry-run
reports an installed extension that is not in `configs/vsc/extensions.yml`, the
normal fix is to let the installer prune it or deliberately add a manifest entry.

If `script/vscode plan` reports `configure VS Code storage`, quit VS Code before
running `script/install` or `script/vscode apply`; the applier intentionally
refuses to write `state.vscdb` while VS Code is running.

### Manifest Drift

If `script/manifest validate` fails, fix `install.yml` or the referenced source
files. Do not bypass manifest validation in `script/install`.

### CI Missing Local Tools

`script/test` should run on GitHub Actions without assuming local-only tools such
as `rg`. If optional local tools improve output, keep portable fallbacks.

## Editing Guidelines

- Prefer `apply_patch` for manual file edits.
- Keep edits scoped to the requested behavior.
- Do not reformat large config files just because they were touched.
- Preserve executable bits on scripts under `script/`.
- Avoid destructive commands and avoid changing files in the user's home
  directory unless the user explicitly asks for a live machine change.
- When moving files, update `install.yml`, docs, tests, and scripts in the same
  change.
- When deleting stale files, add or update generic dead-path checks in
  `script/test` when useful.

## PR Guidance

Keep PRs focused and explain the operational impact. For this repo, a useful PR
description usually covers:

- What platform/config surface changed.
- Whether install/restore behavior changed.
- Whether supply-chain or dependency behavior changed.
- Which validations passed.

Do not include private context in PR titles, branch names, commit messages, or
descriptions.
