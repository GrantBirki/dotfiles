# VS Code

VS Code is managed as desired state from files under `configs/vsc/`.

## Managed User Files

These files are symlinked into `~/Library/Application Support/Code/User`:

- `settings.json`
- `keybindings.json`
- `tasks.json`
- `snippets/`

Edits made through VS Code update the tracked repo files directly.

## Extensions

`configs/vsc/extensions.yml` is the authoritative extension manifest. Each entry has:

- `id`
- `version`
- `auto_update`

`script/install` and `script/vscode apply` install missing baseline versions, correct version drift for pinned extensions, keep allowed auto-update drift, and prune extensions not listed in the manifest.

Global extension auto-update is disabled. Selected auto-update storage is configured so only extensions with `auto_update: true` may auto-update.

## Policy

`configs/vsc/policy.yml` is the machine-readable policy manifest for managed settings and selected extension auto-update behavior.

The generated `extensions.allowed` setting pins non-auto-update extensions to their manifest version and allows stable releases only for explicit auto-update exceptions.

## MCP

MCP config can reveal service names, endpoints, local command paths, and tool wiring. For that reason, `configs/vsc/mcp.json` is ignored by git.

The install manifest has an optional private MCP entry. It only becomes active if `configs/vsc/mcp.json` exists locally.

## Commands

Validate manifests:

```bash
script/vscode validate
```

Preview VS Code desired state:

```bash
script/vscode plan
```

Apply VS Code desired state:

```bash
script/vscode apply
```

Check convergence:

```bash
script/vscode doctor
```
