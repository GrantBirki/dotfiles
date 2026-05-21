# Development

This repo uses lightweight Ruby helpers and shell scripts that follow the Scripts to Rule Them All pattern.

## Scripts

- `script/bootstrap`: install Ruby helpers from committed Bundler config and vendored gems.
- `script/install`: install managed files and reconcile VS Code desired state.
- `script/restore`: restore managed paths from a prior install state file.
- `script/doctor`: check local prerequisites, manifest validity, managed-file health, VS Code convergence, and install state.
- `script/test`: run the full local validation suite.
- `script/vscode`: validate, plan, apply, and doctor VS Code desired state.
- `script/vsc-extension-bulk-install`: compatibility wrapper around `script/vscode`.

## Ruby

Ruby is used for repo orchestration because it is easier to unit test than larger Bash scripts. The main implementation files live in `lib/dotfiles/`.

RSpec tests live under `spec/`. The suite enforces 100% line coverage for Ruby library files and Ruby CLI entrypoints using Ruby's built-in `Coverage` module.

## Testing

Run:

```bash
script/test
```

The test script validates Ruby syntax, shell syntax, structured config, alias metadata, install manifests, VS Code desired state, Secretive-only Git policy, public-repo safety checks, stale platform paths, and RSpec coverage.

## Public Repo Safety

Do not commit private host overlays, local state, install logs, generated VS Code storage, MCP server definitions, Secretive Git key files, credentials, keys, tokens, employer-specific references, or machine-specific artifacts.
