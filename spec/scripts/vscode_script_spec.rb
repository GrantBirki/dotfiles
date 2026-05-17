# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/dotfiles/vscode"

RSpec.describe "script/vscode" do
  let(:script_path) { File.join(ROOT, "script/vscode") }
  let(:actions) do
    [
      { "type" => "extension", "action" => "keep", "id" => "fixed.extension" },
      { "type" => "warning", "action" => "warn", "message" => "heads up" }
    ]
  end
  let(:manager) do
    instance_double(
      Dotfiles::VSCode::Manager,
      validate!: true,
      actions: actions,
      format_actions: "formatted actions",
      apply: true,
      doctor_actions: actions
    )
  end

  before do
    allow(Dotfiles::VSCode::Manager).to receive(:new).and_return(manager)
  end

  it "prints usage" do
    result = run_script(script_path, ["--help"])

    expect(result).to include(status: 0)
    expect(result.fetch(:stderr)).to include("Usage: script/vscode")
  end

  it "rejects unknown options" do
    result = run_script(script_path, ["--wat"])

    expect(result).to include(status: 2)
    expect(result.fetch(:stderr)).to include("Unknown option: --wat", "Usage: script/vscode")
  end

  it "rejects unsupported output formats" do
    result = run_script(script_path, ["plan", "--format", "yaml"])

    expect(result).to include(status: 2)
    expect(result.fetch(:stderr)).to eq("Unsupported format: yaml\n")
  end

  it "validates manifests" do
    result = run_script(script_path, ["validate"])

    expect(result).to include(status: 0)
    expect(result.fetch(:stdout)).to eq("VS Code configuration OK.\n")
    expect(manager).to have_received(:validate!)
  end

  it "prints a text plan by default" do
    result = run_script(script_path, ["plan"])

    expect(result).to include(status: 0)
    expect(result.fetch(:stdout)).to eq("formatted actions\n")
    expect(manager).to have_received(:format_actions).with(actions)
  end

  it "prints a JSON plan and passes all manager options" do
    expect(Dotfiles::VSCode::Manager).to receive(:new).with(
      extensions_path: "/tmp/extensions.yml",
      policy_path: "/tmp/policy.yml",
      settings_path: "/tmp/settings.json",
      user_dir: "/tmp/User",
      installed_extensions_file: "/tmp/installed.txt",
      prune: false
    ).and_return(manager)

    result = run_script(script_path, [
      "plan",
      "--extensions", "/tmp/extensions.yml",
      "--policy", "/tmp/policy.yml",
      "--settings", "/tmp/settings.json",
      "--user-dir", "/tmp/User",
      "--installed-extensions", "/tmp/installed.txt",
      "--format", "json",
      "--no-prune"
    ])

    expect(result).to include(status: 0)
    expect(JSON.parse(result.fetch(:stdout))).to eq("actions" => actions)
  end

  it "honors environment defaults for user dir and installed extension fixtures" do
    original_user_dir = ENV["DOTFILES_VSCODE_USER_DIR"]
    original_installed = ENV["DOTFILES_VSCODE_INSTALLED_EXTENSIONS_FILE"]
    ENV["DOTFILES_VSCODE_USER_DIR"] = "/env/User"
    ENV["DOTFILES_VSCODE_INSTALLED_EXTENSIONS_FILE"] = "/env/installed.txt"
    expect(Dotfiles::VSCode::Manager).to receive(:new).with(
      extensions_path: Dotfiles::VSCode::DEFAULT_EXTENSIONS_PATH,
      policy_path: Dotfiles::VSCode::DEFAULT_POLICY_PATH,
      settings_path: Dotfiles::VSCode::DEFAULT_SETTINGS_PATH,
      user_dir: "/env/User",
      installed_extensions_file: "/env/installed.txt",
      prune: true
    ).and_return(manager)

    expect(run_script(script_path, ["plan"])).to include(status: 0)
  ensure
    ENV["DOTFILES_VSCODE_USER_DIR"] = original_user_dir
    ENV["DOTFILES_VSCODE_INSTALLED_EXTENSIONS_FILE"] = original_installed
  end

  it "applies desired state" do
    result = run_script(script_path, ["apply"])

    expect(result).to include(status: 0)
    expect(result.fetch(:stdout)).to eq("VS Code configuration applied.\n")
    expect(manager).to have_received(:apply)
  end

  it "reports a successful doctor result" do
    result = run_script(script_path, ["doctor"])

    expect(result).to include(status: 0)
    expect(result.fetch(:stdout)).to eq("formatted actions\n")
  end

  it "reports JSON doctor output and exits nonzero for pending actions" do
    pending = [{ "type" => "setting", "action" => "write", "key" => "extensions.autoUpdate" }]
    allow(manager).to receive(:doctor_actions).and_return(pending)

    result = run_script(script_path, ["doctor", "--format", "json"])

    expect(result).to include(status: 1)
    expect(JSON.parse(result.fetch(:stdout))).to eq("actions" => pending)
  end

  it "rejects unknown commands" do
    result = run_script(script_path, ["wat"])

    expect(result).to include(status: 2)
    expect(result.fetch(:stderr)).to eq("Usage: script/vscode [validate|plan|apply|doctor]\n")
  end

  it "exits with VS Code manager errors" do
    allow(manager).to receive(:validate!).and_raise(Dotfiles::VSCode::Error, "bad vscode config")

    result = run_script(script_path, ["validate"])

    expect(result).to include(status: 1)
    expect(result.fetch(:stderr)).to eq("bad vscode config\n")
  end
end
