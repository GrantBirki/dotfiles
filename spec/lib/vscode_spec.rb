# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/dotfiles/vscode"

RSpec.describe Dotfiles::VSCode::Extension do
  it "formats an install spec" do
    extension = described_class.new(id: "publisher.extension", version: "1.2.3", auto_update: false)

    expect(extension.spec).to eq("publisher.extension@1.2.3")
  end

  it "formats an unpinned install spec for any-version extensions" do
    extension = described_class.new(id: "publisher.extension", version: "any", auto_update: true)

    expect(extension.spec).to eq("publisher.extension")
  end
end

RSpec.describe Dotfiles::VSCode::Manager do
  def extensions_data
    [
      { "id" => "fixed.extension", "version" => "1.0.0", "auto_update" => false },
      { "id" => "drifty.extension", "version" => "2.0.0", "auto_update" => true },
      { "id" => "missing.extension", "version" => "3.0.0", "auto_update" => false }
    ]
  end

  def policy_data
    {
      "settings" => {
        "extensions.autoUpdate" => false,
        "telemetry.telemetryLevel" => "error"
      },
      "generated_settings" => {
        "extensions.allowed" => "extensions"
      },
      "selected_auto_update" => {
        "allow_from_extension_manifest" => true,
        "deny_all_others" => true,
        "require_vscode_closed" => true,
        "backup_before_write" => true
      },
      "settings_sync" => {
        "extensions" => "warn-only"
      },
      "unmanaged_user_files" => {
        "warn" => ["tasks.json"],
        "warn_if_nonempty" => ["mcp.json", "snippets"]
      }
    }
  end

  def desired_settings
    {
      "extensions.autoUpdate" => false,
      "telemetry.telemetryLevel" => "error",
      "extensions.allowed" => {
        "fixed.extension" => ["1.0.0"],
        "drifty.extension" => "stable",
        "missing.extension" => ["3.0.0"]
      }
    }
  end

  def write_vscode_files(dir, extensions: extensions_data, policy: policy_data, settings: desired_settings)
    paths = {
      extensions: File.join(dir, "extensions.yml"),
      policy: File.join(dir, "policy.yml"),
      settings: File.join(dir, "settings.json"),
      user_dir: File.join(dir, "User")
    }
    FileUtils.mkdir_p(paths.fetch(:user_dir))
    File.write(paths.fetch(:extensions), { "extensions" => extensions }.to_yaml)
    File.write(paths.fetch(:policy), policy.to_yaml)
    File.write(paths.fetch(:settings), "#{JSON.pretty_generate(settings)}\n")
    paths
  end

  def manager_for(paths, installed_extensions_file: nil, prune: true)
    described_class.new(
      extensions_path: paths.fetch(:extensions),
      policy_path: paths.fetch(:policy),
      settings_path: paths.fetch(:settings),
      user_dir: paths.fetch(:user_dir),
      installed_extensions_file: installed_extensions_file,
      prune: prune
    )
  end

  def successful_status
    instance_double(Process::Status, success?: true)
  end

  def failed_status
    instance_double(Process::Status, success?: false)
  end

  it "uses the documented default VS Code User directory" do
    expect(described_class.default_user_dir).to end_with("Library/Application Support/Code/User")
  end

  it "validates matching manifests and settings" do
    Dir.mktmpdir do |dir|
      manager = manager_for(write_vscode_files(dir))

      expect(manager.validate!).to eq(true)
      expect(manager.extensions.map(&:id)).to eq(["fixed.extension", "drifty.extension", "missing.extension"])
      expect(manager.policy.fetch("settings_sync")).to eq("extensions" => "warn-only")
    end
  end

  it "allows non-strict validation when tracked settings drift" do
    Dir.mktmpdir do |dir|
      paths = write_vscode_files(dir, settings: {})
      manager = manager_for(paths)

      expect(manager.validate!(strict_settings: false)).to eq(true)
      expect do
        manager.validate!
      end.to raise_error(Dotfiles::VSCode::Error, /settings\.json does not match policy/)
    end
  end

  it "generates pinned and stable extension allowlist settings" do
    Dir.mktmpdir do |dir|
      manager = manager_for(write_vscode_files(dir))

      expect(manager.desired_settings.fetch("extensions.allowed")).to eq(
        "fixed.extension" => ["1.0.0"],
        "drifty.extension" => "stable",
        "missing.extension" => ["3.0.0"]
      )
    end
  end

  it "allows any-version auto-update extensions and installs them unpinned when missing" do
    Dir.mktmpdir do |dir|
      paths = write_vscode_files(
        dir,
        extensions: [{ "id" => "openai.chatgpt", "version" => "any", "auto_update" => true }],
        settings: {
          "extensions.autoUpdate" => false,
          "telemetry.telemetryLevel" => "error",
          "extensions.allowed" => { "openai.chatgpt" => "stable" }
        }
      )
      installed = File.join(dir, "installed.txt")
      File.write(installed, "")
      actions = manager_for(paths, installed_extensions_file: installed).actions

      expect(actions).to include(
        a_hash_including(
          "type" => "extension",
          "action" => "install",
          "id" => "openai.chatgpt",
          "version" => "any",
          "spec" => "openai.chatgpt"
        )
      )
      expect(manager_for(paths, installed_extensions_file: installed).desired_settings.fetch("extensions.allowed"))
        .to eq("openai.chatgpt" => "stable")
    end
  end

  it "keeps installed any-version auto-update extensions at their current version" do
    Dir.mktmpdir do |dir|
      paths = write_vscode_files(
        dir,
        extensions: [{ "id" => "openai.chatgpt", "version" => "any", "auto_update" => true }],
        settings: {
          "extensions.autoUpdate" => false,
          "telemetry.telemetryLevel" => "error",
          "extensions.allowed" => { "openai.chatgpt" => "stable" }
        }
      )
      installed = File.join(dir, "installed.txt")
      File.write(installed, "openai.chatgpt@26.519.32039\n")

      expect(manager_for(paths, installed_extensions_file: installed).actions).to include(
        a_hash_including(
          "type" => "extension",
          "action" => "keep_auto_update",
          "id" => "openai.chatgpt",
          "current_version" => "26.519.32039",
          "version" => "any"
        )
      )
    end
  end

  it "plans installs, corrections, auto-update keeps, prunes, storage policy, and warnings" do
    Dir.mktmpdir do |dir|
      paths = write_vscode_files(dir)
      installed = File.join(dir, "installed.txt")
      File.write(installed, [
        "fixed.extension@0.9.0",
        "drifty.extension@2.5.0",
        "extra.extension@1.0.0"
      ].join("\n"))
      File.write(File.join(paths.fetch(:user_dir), "mcp.json"), "{}")
      File.write(File.join(paths.fetch(:user_dir), "tasks.json"), "{}")
      FileUtils.mkdir_p(File.join(paths.fetch(:user_dir), "snippets"))
      File.write(File.join(paths.fetch(:user_dir), "snippets", "ruby.json"), "{}")

      actions = manager_for(paths, installed_extensions_file: installed).actions

      expect(actions).to include(
        a_hash_including("type" => "extension", "action" => "update", "id" => "fixed.extension"),
        a_hash_including("type" => "extension", "action" => "keep_auto_update", "id" => "drifty.extension"),
        a_hash_including("type" => "extension", "action" => "install", "id" => "missing.extension"),
        a_hash_including("type" => "extension", "action" => "prune", "id" => "extra.extension"),
        a_hash_including("type" => "storage", "action" => "configure", "key" => Dotfiles::VSCode::SELECTED_AUTO_UPDATE_KEY),
        a_hash_including("type" => "storage", "action" => "configure", "key" => Dotfiles::VSCode::DISABLED_AUTO_UPDATE_KEY),
        a_hash_including("type" => "warning", "action" => "warn", "message" => /mcp\.json/),
        a_hash_including("type" => "warning", "action" => "warn", "message" => /tasks\.json/),
        a_hash_including("type" => "warning", "action" => "warn", "message" => /snippets/)
      )
    end
  end

  it "does not warn for empty local-only VS Code files" do
    Dir.mktmpdir do |dir|
      paths = write_vscode_files(dir)
      FileUtils.touch(File.join(paths.fetch(:user_dir), "mcp.json"))
      FileUtils.mkdir_p(File.join(paths.fetch(:user_dir), "snippets"))

      warnings = manager_for(paths).send(:unmanaged_user_file_warnings)

      expect(warnings).to eq([])
    end
  end

  it "does not prune untracked extensions when pruning is disabled" do
    Dir.mktmpdir do |dir|
      paths = write_vscode_files(dir)
      installed = File.join(dir, "installed.txt")
      File.write(installed, "extra.extension@1.0.0\n")

      actions = manager_for(paths, installed_extensions_file: installed, prune: false).actions

      expect(actions).not_to include(a_hash_including("action" => "prune"))
    end
  end

  it "warns instead of comparing extensions when inventory is unavailable" do
    Dir.mktmpdir do |dir|
      manager = manager_for(write_vscode_files(dir))
      allow(manager).to receive(:command?).with("code").and_return(false)

      expect(manager.actions).to include(
        "type" => "warning",
        "action" => "warn",
        "message" => "code CLI not found or extension inventory unavailable; validated manifest without live drift comparison"
      )
    end
  end

  it "plans storage keep actions when selected auto-update storage already matches" do
    Dir.mktmpdir do |dir|
      manager = manager_for(write_vscode_files(dir))
      allow(manager).to receive(:current_storage_array)
        .with(Dotfiles::VSCode::SELECTED_AUTO_UPDATE_KEY)
        .and_return(["drifty.extension"])
      allow(manager).to receive(:current_storage_array)
        .with(Dotfiles::VSCode::DISABLED_AUTO_UPDATE_KEY)
        .and_return(["fixed.extension", "missing.extension"])

      expect(manager.actions).to include(
        "type" => "storage",
        "action" => "keep",
        "key" => Dotfiles::VSCode::SELECTED_AUTO_UPDATE_KEY,
        "desired" => ["drifty.extension"],
        "current" => ["drifty.extension"]
      )
    end
  end

  it "disables storage actions when the policy opts out" do
    Dir.mktmpdir do |dir|
      policy = policy_data
      policy["selected_auto_update"]["allow_from_extension_manifest"] = false
      manager = manager_for(write_vscode_files(dir, policy: policy))

      expect(manager.send(:storage_actions)).to eq([])
    end
  end

  it "parses JSONC settings with line comments, block comments, and trailing commas" do
    Dir.mktmpdir do |dir|
      paths = write_vscode_files(dir)
      File.write(paths.fetch(:settings), <<~JSONC)
        {
          // line comment
          "extensions.autoUpdate": false,
          /* block
             comment */
          "telemetry.telemetryLevel": "error",
          "extensions.allowed": {
            "fixed.extension": ["1.0.0"],
            "drifty.extension": "stable",
            "missing.extension": ["3.0.0"],
          },
        }
      JSONC

      expect(manager_for(paths).validate!).to eq(true)
    end
  end

  it "parses escaped characters inside JSONC strings" do
    Dir.mktmpdir do |dir|
      paths = write_vscode_files(dir)
      File.write(paths.fetch(:settings), <<~JSON)
        {
          "quoted": "a \\"quote\\" and slash \\\\"
        }
      JSON

      expect(manager_for(paths).send(:parse_jsonc, paths.fetch(:settings))).to eq(
        "quoted" => "a \"quote\" and slash \\"
      )
    end
  end

  it "treats a missing settings file as empty current settings" do
    Dir.mktmpdir do |dir|
      paths = write_vscode_files(dir)
      FileUtils.rm_f(paths.fetch(:settings))

      expect(manager_for(paths).send(:current_settings)).to eq({})
    end
  end

  it "reports invalid JSON settings" do
    Dir.mktmpdir do |dir|
      paths = write_vscode_files(dir)
      File.write(paths.fetch(:settings), "{")

      expect do
        manager_for(paths).validate!
      end.to raise_error(Dotfiles::VSCode::Error, /invalid VS Code settings JSON/)
    end
  end

  it "reports unterminated block comments in JSONC settings" do
    Dir.mktmpdir do |dir|
      paths = write_vscode_files(dir)
      File.write(paths.fetch(:settings), "{ /* never closed")

      expect do
        manager_for(paths).validate!
      end.to raise_error(Dotfiles::VSCode::Error, /unterminated block comment/)
    end
  end

  it "applies successfully when there are no pending actions" do
    Dir.mktmpdir do |dir|
      paths = write_vscode_files(dir)
      installed = File.join(dir, "installed.txt")
      File.write(installed, [
        "fixed.extension@1.0.0",
        "drifty.extension@2.0.0",
        "missing.extension@3.0.0"
      ].join("\n"))
      manager = manager_for(paths, installed_extensions_file: installed)
      allow(manager).to receive(:current_storage_array)
        .with(Dotfiles::VSCode::SELECTED_AUTO_UPDATE_KEY)
        .and_return(["drifty.extension"])
      allow(manager).to receive(:current_storage_array)
        .with(Dotfiles::VSCode::DISABLED_AUTO_UPDATE_KEY)
        .and_return(["fixed.extension", "missing.extension"])

      expect(manager.apply).to eq(true)
    end
  end

  it "raises when apply cannot converge" do
    Dir.mktmpdir do |dir|
      manager = manager_for(write_vscode_files(dir))
      pending = [{ "type" => "extension", "action" => "install", "id" => "missing.extension", "spec" => "missing.extension@3.0.0" }]
      allow(manager).to receive(:actions).and_return([], pending)
      allow(manager).to receive(:apply_settings)
      allow(manager).to receive(:apply_extensions)
      allow(manager).to receive(:apply_storage)

      expect { manager.apply }.to raise_error(Dotfiles::VSCode::Error, /still has pending actions/)
    end
  end

  it "doctor actions convert validation errors to issues" do
    manager = described_class.new(extensions_path: "/tmp/nope", policy_path: "/tmp/nope", settings_path: "/tmp/nope")

    expect(manager.doctor_actions).to contain_exactly(
      a_hash_including("type" => "issue", "action" => "error", "message" => /manifest not found/)
    )
  end

  it "writes settings updates" do
    Dir.mktmpdir do |dir|
      paths = write_vscode_files(dir, settings: {})
      manager = manager_for(paths)

      expect do
        manager.send(:apply_settings, [
          { "type" => "setting", "action" => "write", "key" => "telemetry.telemetryLevel", "desired" => "error" }
        ])
      end.to output(/Updated VS Code settings policy/).to_stdout

      expect(JSON.parse(File.read(paths.fetch(:settings)))).to eq("telemetry.telemetryLevel" => "error")
      expect { manager.send(:apply_settings, []) }.not_to output.to_stdout
    end
  end

  it "applies extension installs, updates, and prunes through the code CLI" do
    Dir.mktmpdir do |dir|
      manager = manager_for(write_vscode_files(dir))
      allow(manager).to receive(:command?).with("code").and_return(true)
      expect(manager).to receive(:run_code!).with("--install-extension", "fixed.extension@1.0.0", "--force")
      expect(manager).to receive(:run_code!).with("--install-extension", "missing.extension@3.0.0", "--force")
      expect(manager).to receive(:uninstall_extension!).with("extra.extension").and_return(:uninstalled)

      expect do
        manager.send(:apply_extensions, [
          { "type" => "extension", "action" => "keep", "id" => "drifty.extension", "spec" => "drifty.extension@2.0.0" },
          { "type" => "extension", "action" => "install", "id" => "fixed.extension", "spec" => "fixed.extension@1.0.0" },
          { "type" => "extension", "action" => "update", "id" => "missing.extension", "spec" => "missing.extension@3.0.0" },
          { "type" => "extension", "action" => "prune", "id" => "extra.extension" }
        ])
      end.to output(/Installed VS Code extension baseline: fixed\.extension@1\.0\.0.*Uninstalled VS Code extension not in manifest: extra\.extension/m).to_stdout
      expect(manager.send(:apply_extensions, [])).to be_nil
    end
  end

  it "treats already-absent prune targets as converged" do
    Dir.mktmpdir do |dir|
      manager = manager_for(write_vscode_files(dir))
      allow(manager).to receive(:command?).with("code").and_return(true)
      expect(manager).to receive(:uninstall_extension!).with("extra.extension").and_return(:absent)

      expect do
        manager.send(:apply_extensions, [
          { "type" => "extension", "action" => "prune", "id" => "extra.extension" }
        ])
      end.to output(/VS Code extension already absent: extra\.extension/).to_stdout
    end
  end

  it "requires the code CLI before mutating extensions" do
    Dir.mktmpdir do |dir|
      manager = manager_for(write_vscode_files(dir))
      allow(manager).to receive(:command?).with("code").and_return(false)

      expect do
        manager.send(:apply_extensions, [{ "type" => "extension", "action" => "install", "spec" => "fixed.extension@1.0.0" }])
      end.to raise_error(Dotfiles::VSCode::Error, /'code' CLI not found/)
    end
  end

  it "applies selected auto-update storage only when needed" do
    Dir.mktmpdir do |dir|
      manager = manager_for(write_vscode_files(dir))
      expect(manager.send(:apply_storage, [])).to be_nil
      expect(manager).to receive(:ensure_vscode_closed!)
      expect(manager).to receive(:backup_storage!)
      expect(manager).to receive(:write_storage_arrays)

      manager.send(:apply_storage, [{ "type" => "storage", "action" => "configure" }])
    end
  end

  it "refuses selected auto-update storage writes while VS Code is running" do
    Dir.mktmpdir do |dir|
      manager = manager_for(write_vscode_files(dir))
      allow(manager).to receive(:command?).with("pgrep").and_return(true)
      allow(manager).to receive(:system)
        .with("pgrep", "-x", "Code", out: File::NULL, err: File::NULL)
        .and_return(true)

      expect { manager.send(:ensure_vscode_closed!) }.to raise_error(Dotfiles::VSCode::Error, /VS Code is running/)
    end
  end

  it "allows selected auto-update storage checks when pgrep is absent or Code is closed" do
    Dir.mktmpdir do |dir|
      manager = manager_for(write_vscode_files(dir))
      allow(manager).to receive(:command?).with("pgrep").and_return(false)
      expect(manager.send(:ensure_vscode_closed!)).to be_nil

      allow(manager).to receive(:command?).with("pgrep").and_return(true)
      allow(manager).to receive(:system)
        .with("pgrep", "-x", "Code", out: File::NULL, err: File::NULL)
        .and_return(false)
      expect(manager.send(:ensure_vscode_closed!)).to be_nil
    end
  end

  it "backs up an existing VS Code storage database" do
    Dir.mktmpdir do |dir|
      manager = manager_for(write_vscode_files(dir))
      db = File.join(dir, "state.vscdb")
      File.write(db, "sqlite")
      allow(manager).to receive(:storage_db).and_return(db)
      backup_glob = File.join(Dotfiles::VSCode::ROOT, ".dotfiles/state/vscode-state.vscdb.*.bak")
      before = Dir[backup_glob]

      expect { manager.send(:backup_storage!) }.to output(/Backed up VS Code global storage/).to_stdout

      created = Dir[backup_glob] - before
      expect(created.length).to eq(1)
      expect(File.read(created.first)).to eq("sqlite")
      FileUtils.rm_f(created)
      allow(manager).to receive(:storage_db).and_return(File.join(dir, "missing.vscdb"))
      expect { manager.send(:backup_storage!) }.not_to output.to_stdout
    end
  end

  it "writes selected auto-update storage with sqlite3" do
    Dir.mktmpdir do |dir|
      manager = manager_for(write_vscode_files(dir))
      db = File.join(dir, "globalStorage/state.vscdb")
      allow(manager).to receive(:storage_db).and_return(db)
      allow(manager).to receive(:command?).with("sqlite3").and_return(true)
      expect(Open3).to receive(:capture3)
        .with("sqlite3", db, include("extensions.autoUpdate", "extensions.donotAutoUpdate"))
        .and_return(["", "", successful_status])

      expect(manager.send(:write_storage_arrays)).to be_nil
    end
  end

  it "reports sqlite3 absence and write failures" do
    Dir.mktmpdir do |dir|
      manager = manager_for(write_vscode_files(dir))
      allow(manager).to receive(:command?).with("sqlite3").and_return(false)
      expect { manager.send(:write_storage_arrays) }.to raise_error(Dotfiles::VSCode::Error, /sqlite3 is required/)

      allow(manager).to receive(:command?).with("sqlite3").and_return(true)
      allow(manager).to receive(:storage_db).and_return(File.join(dir, "state.vscdb"))
      expect(Open3).to receive(:capture3).and_return(["stdout failure", "", failed_status])
      expect { manager.send(:write_storage_arrays) }.to raise_error(Dotfiles::VSCode::Error, /stdout failure/)

      expect(Open3).to receive(:capture3).and_return(["", "stderr failure", failed_status])
      expect { manager.send(:write_storage_arrays) }.to raise_error(Dotfiles::VSCode::Error, /stderr failure/)
    end
  end

  it "reads selected auto-update storage arrays" do
    Dir.mktmpdir do |dir|
      manager = manager_for(write_vscode_files(dir))
      db = File.join(dir, "state.vscdb")
      File.write(db, "")
      allow(manager).to receive(:storage_db).and_return(db)
      allow(manager).to receive(:command?).with("sqlite3").and_return(true)
      expect(Open3).to receive(:capture3)
        .with("sqlite3", db, "SELECT value FROM ItemTable WHERE key = 'extensions.autoUpdate';")
        .and_return(["[\"Z.Extension\",\"a.extension\"]\n", "", successful_status])

      expect(manager.send(:current_storage_array, Dotfiles::VSCode::SELECTED_AUTO_UPDATE_KEY)).to eq(["a.extension", "z.extension"])
    end
  end

  it "returns nil for absent, unreadable, or invalid storage arrays" do
    Dir.mktmpdir do |dir|
      manager = manager_for(write_vscode_files(dir))
      allow(manager).to receive(:storage_db).and_return(File.join(dir, "missing.vscdb"))
      expect(manager.send(:current_storage_array, "missing")).to be_nil

      db = File.join(dir, "state.vscdb")
      File.write(db, "")
      allow(manager).to receive(:storage_db).and_return(db)
      allow(manager).to receive(:command?).with("sqlite3").and_return(false)
      expect(manager.send(:current_storage_array, "no-sqlite")).to be_nil

      allow(manager).to receive(:command?).with("sqlite3").and_return(true)
      expect(Open3).to receive(:capture3).and_return(["not-json", "", successful_status])
      expect(manager.send(:current_storage_array, "bad-json")).to be_nil
    end
  end

  it "reads installed inventory from a fixture file or the code CLI" do
    Dir.mktmpdir do |dir|
      paths = write_vscode_files(dir)
      installed = File.join(dir, "installed.txt")
      File.write(installed, "z.extension@1\na.extension@2\n\n")
      expect(manager_for(paths, installed_extensions_file: installed).send(:installed_inventory)).to eq(
        ["a.extension@2", "z.extension@1"]
      )

      manager = manager_for(paths)
      allow(manager).to receive(:command?).with("code").and_return(true)
      expect(Open3).to receive(:capture3)
        .with("code", "--list-extensions", "--show-versions")
        .and_return(["b.extension@1\n", "", successful_status])
      expect(manager.send(:installed_inventory)).to eq(["b.extension@1"])

      failing = manager_for(paths)
      allow(failing).to receive(:command?).with("code").and_return(true)
      expect(Open3).to receive(:capture3).and_return(["", "nope", failed_status])
      expect(failing.send(:installed_inventory)).to be_nil
    end
  end

  it "reports code CLI failures" do
    Dir.mktmpdir do |dir|
      manager = manager_for(write_vscode_files(dir))
      expect(Open3).to receive(:capture3).with("code", "--version").and_return(["ok", "", successful_status])
      expect(manager.send(:run_code!, "--version")).to eq(true)

      expect(Open3).to receive(:capture3).with("code", "--bad").and_return(["stdout bad", "", failed_status])
      expect { manager.send(:run_code!, "--bad") }.to raise_error(Dotfiles::VSCode::Error, /stdout bad/)

      expect(Open3).to receive(:capture3).with("code", "--worse").and_return(["", "stderr bad", failed_status])
      expect { manager.send(:run_code!, "--worse") }.to raise_error(Dotfiles::VSCode::Error, /stderr bad/)
    end
  end

  it "uninstalls extensions and tolerates already absent prune targets" do
    Dir.mktmpdir do |dir|
      manager = manager_for(write_vscode_files(dir))
      expect(Open3).to receive(:capture3)
        .with("code", "--uninstall-extension", "extra.extension")
        .and_return(["", "", successful_status])
      expect(manager.send(:uninstall_extension!, "extra.extension")).to eq(:uninstalled)

      expect(Open3).to receive(:capture3)
        .with("code", "--uninstall-extension", "missing.extension")
        .and_return(["", "Extension 'missing.extension' is not installed.", failed_status])
      expect(manager.send(:uninstall_extension!, "missing.extension")).to eq(:absent)

      expect(Open3).to receive(:capture3)
        .with("code", "--uninstall-extension", "broken.extension")
        .and_return(["stdout failure", "", failed_status])
      expect { manager.send(:uninstall_extension!, "broken.extension") }.to raise_error(
        Dotfiles::VSCode::Error,
        /stdout failure/
      )
    end
  end

  it "formats every action type" do
    Dir.mktmpdir do |dir|
      manager = manager_for(write_vscode_files(dir))
      text = manager.format_actions([
        { "type" => "extension", "action" => "install", "spec" => "a.b@1" },
        { "type" => "extension", "action" => "update", "id" => "a.b", "current_version" => "0", "version" => "1" },
        { "type" => "extension", "action" => "prune", "id" => "a.b" },
        { "type" => "extension", "action" => "keep_auto_update", "id" => "a.b", "current_version" => "2", "version" => "1" },
        { "type" => "extension", "action" => "keep", "spec" => "a.b@1" },
        { "type" => "setting", "action" => "write", "key" => "x", "desired" => true },
        { "type" => "setting", "action" => "keep", "key" => "x" },
        { "type" => "storage", "action" => "configure", "key" => "x", "desired" => [] },
        { "type" => "storage", "action" => "keep", "key" => "x" },
        { "type" => "warning", "action" => "warn", "message" => "careful" },
        { "type" => "issue", "action" => "error", "message" => "broken" },
        { "type" => "unknown", "action" => "mystery" }
      ])

      expect(text).to include(
        "install extension baseline: a.b@1",
        "update extension to baseline: a.b 0 -> 1",
        "prune extension not in manifest: a.b",
        "keep auto-update extension: a.b current=2 baseline=1",
        "keep extension: a.b@1",
        "write setting: x -> true",
        "keep setting: x",
        "configure VS Code storage: x -> []",
        "keep VS Code storage: x",
        "warn: careful",
        "issue: broken",
        "unknown: mystery"
      )
    end
  end

  it "classifies terminal actions and escapes SQL string literals" do
    Dir.mktmpdir do |dir|
      manager = manager_for(write_vscode_files(dir))

      expect(manager.send(:terminal_action?, "action" => "keep")).to eq(true)
      expect(manager.send(:terminal_action?, "action" => "keep_auto_update")).to eq(true)
      expect(manager.send(:terminal_action?, "action" => "warn")).to eq(true)
      expect(manager.send(:terminal_action?, "action" => "install")).to eq(false)
      expect(manager.send(:sql_literal, "a'b")).to eq("a''b")
      expect(manager.send(:command?, "definitely-not-a-dotfiles-command")).to eq(false)
    end
  end

  context "schema validation" do
    it "reports extension manifest errors" do
      Dir.mktmpdir do |dir|
        paths = write_vscode_files(dir)
        expect do
          manager_for(paths.merge(extensions: File.join(dir, "missing.yml"))).extensions
        end.to raise_error(Dotfiles::VSCode::Error, /manifest not found/)

        invalid_cases = [
          [{}, /missing required `extensions` key/],
          [{ "extensions" => "nope" }, /`extensions` must be an array/],
          [{ "extensions" => ["bad"] }, /extensions\[0\] must be a mapping/],
          [{ "extensions" => [extensions_data.first.merge("extra" => true)] }, /unknown keys: extra/],
          [{ "extensions" => [extensions_data.first.merge("id" => "BAD")] }, /invalid id/],
          [{ "extensions" => [extensions_data.first.merge("version" => "")] }, /invalid version/],
          [{ "extensions" => [extensions_data.first.merge("auto_update" => nil)] }, /must set auto_update/],
          [{ "extensions" => [extensions_data.first.merge("version" => "any")] }, /version `any` only when auto_update is true/],
          [{ "extensions" => [extensions_data.first, extensions_data.first] }, /duplicate VS Code extension id/]
        ]

        invalid_cases.each do |payload, message|
          File.write(paths.fetch(:extensions), payload.to_yaml)
          expect { manager_for(paths).extensions }.to raise_error(Dotfiles::VSCode::Error, message)
        end
      end
    end

    it "reports policy manifest errors" do
      Dir.mktmpdir do |dir|
        paths = write_vscode_files(dir)
        expect do
          manager_for(paths.merge(policy: File.join(dir, "missing.yml"))).policy
        end.to raise_error(Dotfiles::VSCode::Error, /policy not found/)

        invalid_cases = [
          [["not-a-map"], /policy must be a mapping/],
          [policy_data.merge("extra" => true), /unknown keys: extra/],
          [policy_data.tap { |payload| payload.delete("settings") }, /missing required `settings` key/],
          [policy_data.merge("settings" => []), /`settings` must be a mapping/],
          [policy_data.merge("generated_settings" => []), /`generated_settings` must be a mapping/],
          [policy_data.merge("generated_settings" => { "x" => "y" }), /unsupported generated/],
          [policy_data.merge("selected_auto_update" => []), /`selected_auto_update` must be a mapping/],
          [policy_data.merge("selected_auto_update" => policy_data.fetch("selected_auto_update").merge("deny_all_others" => nil)), /deny_all_others/],
          [policy_data.merge("settings_sync" => []), /`settings_sync` must be a mapping/],
          [policy_data.merge("settings_sync" => { "extensions" => "sync" }), /settings_sync\.extensions/],
          [policy_data.merge("unmanaged_user_files" => []), /`unmanaged_user_files` must be a mapping/],
          [policy_data.merge("unmanaged_user_files" => { "warn" => "mcp.json" }), /warn must be an array/],
          [policy_data.merge("unmanaged_user_files" => { "warn" => [1] }), /warn entries must be strings/],
          [policy_data.merge("unmanaged_user_files" => { "warn_if_nonempty" => "mcp.json" }), /warn_if_nonempty must be an array/],
          [policy_data.merge("unmanaged_user_files" => { "warn_if_nonempty" => [1] }), /warn_if_nonempty entries must be strings/]
        ]

        invalid_cases.each do |payload, message|
          File.write(paths.fetch(:policy), payload.to_yaml)
          expect { manager_for(paths).policy }.to raise_error(Dotfiles::VSCode::Error, message)
        end
      end
    end
  end
end
