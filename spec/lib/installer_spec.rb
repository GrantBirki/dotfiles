# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/dotfiles/installer"

RSpec.describe Dotfiles::Installer do
  around do |example|
    original_home = ENV.fetch("HOME")
    Dir.mktmpdir do |home|
      ENV["HOME"] = home
      @home = home
      example.run
    end
  ensure
    ENV["HOME"] = original_home
  end

  def entry(attrs = {})
    Dotfiles::Entry.new({
      "id" => "readme",
      "source" => "README.md",
      "target" => "~/.config/readme",
      "mode" => "symlink",
      "parent" => "create"
    }.merge(attrs))
  end

  def manifest(entries)
    instance_double(Dotfiles::Manifest, validate!: true, entries: entries)
  end

  def vscode_manager(actions = [])
    instance_double(Dotfiles::VSCode::Manager, actions: actions, apply: true)
  end

  def run_installer(argv:, entries:, manager: vscode_manager, platform: "arm64-darwin25", state_dir: nil, default_directories: [])
    stdout = StringIO.new
    stderr = StringIO.new
    installer = described_class.new(
      argv: argv,
      home: @home,
      out: stdout,
      err: stderr,
      platform: platform,
      manifest: manifest(entries),
      vscode_manager: manager,
      state_dir: state_dir || File.join(@home, "state"),
      default_directories: default_directories,
      color: false
    )
    status = installer.run
    [status, stdout.string, stderr.string]
  end

  it "refuses non-macOS platforms" do
    status, stdout, stderr = run_installer(argv: [], entries: [], platform: "x86_64-linux")

    expect(status).to eq(1)
    expect(stdout).to eq("")
    expect(stderr).to include("only supports macOS")
  end

  it "handles CLI help, production, and unknown options" do
    stdout = StringIO.new
    installer = described_class.new(argv: ["--help"], home: @home, out: stdout, err: StringIO.new, color: false)
    expect { installer.run }.to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
    expect(stdout.string).to include("Usage: script/install")

    status, stdout, stderr = run_installer(argv: ["--production"], entries: [])
    expect(status).to eq(0)
    expect(stdout).to include("dotfiles install")
    expect(stderr).to eq("")

    stderr = StringIO.new
    installer = described_class.new(argv: ["--wat"], home: @home, out: StringIO.new, err: stderr, color: false)
    expect { installer.run }.to raise_error(SystemExit) { |error| expect(error.status).to eq(2) }
    expect(stderr.string).to include("Unknown option: --wat", "Usage: script/install")
  end

  it "previews directory creation and symlink installs without mutating files" do
    target = File.join(@home, ".config/readme")
    status, stdout, stderr = run_installer(
      argv: ["--dry-run"],
      entries: [entry],
      default_directories: [".cargo"]
    )

    expect(status).to eq(0)
    expect(stderr).to eq("")
    expect(stdout).to include("Dry run", "would create directory: #{@home}/.cargo", "would create parent directory for readme")
    expect(stdout).to include("would link readme: #{target} -> #{File.join(Dotfiles::ROOT, "README.md")}")
    expect(File.exist?(target)).to eq(false)
  end

  it "records already converged symlinks and state" do
    FileUtils.mkdir_p(File.join(@home, ".config"))
    FileUtils.ln_s(File.join(Dotfiles::ROOT, "README.md"), File.join(@home, ".config/readme"))
    state_dir = File.join(@home, "state")

    status, stdout, stderr = run_installer(argv: [], entries: [entry], state_dir: state_dir)

    expect(status).to eq(0)
    expect(stderr).to eq("")
    expect(stdout).to include("Managed files: 1 already converged", "Install state:")
    state = Dir[File.join(state_dir, "install-*.tsv")].first
    expect(File.read(state)).to include("readme", "already-linked")
  end

  it "creates parent and default directories during real installs" do
    status, stdout, stderr = run_installer(
      argv: [],
      entries: [entry],
      default_directories: [".cargo"]
    )

    expect(status).to eq(0)
    expect(stderr).to eq("")
    expect(stdout).to include("created directory: #{@home}/.cargo", "created parent directory for readme")
    expect(File.symlink?(File.join(@home, ".config/readme"))).to eq(true)
  end

  it "backs up changed targets and copies files" do
    target = File.join(@home, ".config/readme")
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, "old")
    copy_entry = entry("mode" => "copy")

    status, stdout, stderr = run_installer(argv: [], entries: [copy_entry])

    expect(status).to eq(0)
    expect(stderr).to eq("")
    expect(stdout).to include("backed up readme", "copied readme")
    expect(File.read(target)).to eq(File.read(File.join(Dotfiles::ROOT, "README.md")))
    expect(Dir[File.join(@home, "dotfiles_old/.config/readme*")].length).to eq(1)
  end

  it "previews backups and copy operations in dry-run mode" do
    target = File.join(@home, ".config/readme")
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, "old")

    status, stdout, stderr = run_installer(argv: ["--dry-run"], entries: [entry("mode" => "copy")])

    expect(status).to eq(0)
    expect(stderr).to eq("")
    expect(stdout).to include("would back up readme", "would copy readme")
    expect(File.read(target)).to eq("old")
  end

  it "skips entries whose required parent directory is absent" do
    status, stdout, stderr = run_installer(argv: [], entries: [entry("parent" => "require")])

    expect(status).to eq(0)
    expect(stderr).to eq("")
    expect(stdout).to include("Skipping readme because parent directory is missing", "0 file change(s)")
  end

  it "applies VS Code desired state when actionable changes exist" do
    manager = vscode_manager([{ "type" => "setting", "action" => "write", "key" => "x", "desired" => true }])

    status, stdout, = run_installer(argv: [], entries: [], manager: manager)

    expect(status).to eq(0)
    expect(stdout).to include("VS Code: applying 1 change(s)", "setting write: 1")
    expect(manager).to have_received(:apply)
  end

  it "can skip VS Code reconciliation and reports shell reload guidance" do
    bashrc = entry("id" => "bashrc", "target" => "~/.bashrc")

    status, stdout, = run_installer(argv: ["--skip-vscode-extensions"], entries: [bashrc])

    expect(status).to eq(0)
    expect(stdout).to include("VS Code: skipped", "Existing shells may need: source ~/.bashrc")
  end

  it "reports unsupported install modes from manifest entries" do
    weird = instance_double(
      Dotfiles::Entry,
      active?: true,
      parent: "create",
      target_parent: @home,
      mode: "weird",
      id: "weird"
    )
    status, _stdout, stderr = run_installer(argv: [], entries: [weird])

    expect(status).to eq(1)
    expect(stderr).to include("Unsupported install mode for weird")
  end

  it "returns errors from manifest validation or VS Code planning" do
    bad_manifest = instance_double(Dotfiles::Manifest, validate!: nil, entries: [])
    allow(bad_manifest).to receive(:validate!).and_raise(Dotfiles::Error, "broken manifest")
    stdout = StringIO.new
    stderr = StringIO.new
    installer = described_class.new(
      argv: [],
      home: @home,
      out: stdout,
      err: stderr,
      platform: "arm64-darwin25",
      manifest: bad_manifest,
      color: false
    )

    expect(installer.run).to eq(1)
    expect(stderr.string).to eq("broken manifest\n")
  end
end
