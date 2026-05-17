# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/dotfiles/doctor"

RSpec.describe Dotfiles::Doctor do
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
    instance_double(Dotfiles::VSCode::Manager, validate!: true, doctor_actions: actions)
  end

  def run_doctor(entries:, manager: vscode_manager, state_dir: nil)
    stdout = StringIO.new
    stderr = StringIO.new
    doctor = described_class.new(
      argv: [],
      out: stdout,
      err: stderr,
      manifest: manifest(entries),
      vscode_manager: manager,
      state_dir: state_dir || File.join(@home, "state"),
      color: false
    )
    allow(Dotfiles::Runtime).to receive(:command?).and_return(true)
    status = doctor.run
    [status, stdout.string, stderr.string]
  end

  it "reports a healthy install" do
    FileUtils.mkdir_p(File.join(@home, ".config"))
    FileUtils.ln_s(File.join(Dotfiles::ROOT, "README.md"), File.join(@home, ".config/readme"))
    state_dir = File.join(@home, "state")
    FileUtils.mkdir_p(state_dir)
    File.write(File.join(state_dir, "install-20260517120000.tsv"), "")

    status, stdout, stderr = run_doctor(entries: [entry], state_dir: state_dir)

    expect(status).to eq(0)
    expect(stderr).to eq("")
    expect(stdout).to include("Commands: 4/4 required, 6/6 optional available")
    expect(stdout).to include("Managed files: 1 OK", "VS Code: manifests valid and desired state converged")
  end

  it "handles CLI help, production, and unknown options" do
    stdout = StringIO.new
    stderr = StringIO.new
    doctor = described_class.new(argv: ["--help"], out: stdout, err: stderr, color: false)
    expect { doctor.run }.to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
    expect(stdout.string).to include("Usage: script/doctor")

    status, = begin
      state_dir = File.join(@home, "state")
      FileUtils.mkdir_p(state_dir)
      File.write(File.join(state_dir, "install-20260517120000.tsv"), "")
      stdout = StringIO.new
      stderr = StringIO.new
      doctor = described_class.new(
        argv: ["--production"],
        out: stdout,
        err: stderr,
        manifest: manifest([]),
        vscode_manager: vscode_manager,
        state_dir: state_dir,
        color: false
      )
      allow(Dotfiles::Runtime).to receive(:command?).and_return(true)
      [doctor.run, stdout.string]
    end
    expect(status).to eq(0)

    stderr = StringIO.new
    doctor = described_class.new(argv: ["--wat"], out: StringIO.new, err: stderr, color: false)
    expect { doctor.run }.to raise_error(SystemExit) { |error| expect(error.status).to eq(2) }
    expect(stderr.string).to include("Unknown option: --wat", "Usage: script/doctor")
  end

  it "reports missing commands and missing install state" do
    stdout = StringIO.new
    stderr = StringIO.new
    doctor = described_class.new(
      argv: [],
      out: stdout,
      err: stderr,
      manifest: manifest([]),
      vscode_manager: vscode_manager,
      state_dir: File.join(@home, "missing-state"),
      color: false
    )
    allow(Dotfiles::Runtime).to receive(:command?) { |command| command != "bash" && command != "brew" }

    expect(doctor.run).to eq(1)
    expect(stderr.string).to include("required command missing: bash", "optional command missing: brew", "no install state found")
    expect(stderr.string).to include("Doctor found")
  end

  it "reports manifest validation failures" do
    bad_manifest = instance_double(Dotfiles::Manifest, validate!: nil)
    allow(bad_manifest).to receive(:validate!).and_raise(Dotfiles::Error, "broken manifest")

    stdout = StringIO.new
    stderr = StringIO.new
    doctor = described_class.new(
      argv: [],
      out: stdout,
      err: stderr,
      manifest: bad_manifest,
      vscode_manager: vscode_manager,
      state_dir: File.join(@home, "state"),
      color: false
    )
    allow(Dotfiles::Runtime).to receive(:command?).and_return(true)

    expect(doctor.run).to eq(1)
    expect(stderr.string).to include("install manifest validation failed", "broken manifest")
  end

  it "reports managed-file drift cases" do
    FileUtils.mkdir_p(File.join(@home, ".config"))
    File.write(File.join(@home, ".config/not-a-link"), "manual")
    FileUtils.ln_s(File.join(Dotfiles::ROOT, "Gemfile"), File.join(@home, ".config/wrong-link"))
    File.write(File.join(@home, ".config/copy"), "wrong")
    entries = [
      entry("target" => "~/.config/missing"),
      entry("id" => "not-link", "target" => "~/.config/not-a-link"),
      entry("id" => "wrong-link", "target" => "~/.config/wrong-link"),
      entry("id" => "copy", "target" => "~/.config/copy", "mode" => "copy"),
      entry("id" => "requires-parent", "target" => "~/.nope/readme", "parent" => "require")
    ]

    status, _stdout, stderr = run_doctor(entries: entries)

    expect(status).to eq(1)
    expect(stderr).to include("target is not installed", "target exists but is not a symlink")
    expect(stderr).to include("target symlink points elsewhere", "target differs from repo source", "parent directory is missing")
  end

  it "counts matching copied files and reports unsupported entry modes" do
    target = File.join(@home, ".config/readme-copy")
    FileUtils.mkdir_p(File.dirname(target))
    FileUtils.cp(File.join(Dotfiles::ROOT, "README.md"), target)
    unsupported = instance_double(
      Dotfiles::Entry,
      active?: true,
      id: "weird",
      source_path: File.join(Dotfiles::ROOT, "README.md"),
      target_path: target,
      target_parent: File.dirname(target),
      parent: "create",
      mode: "weird"
    )

    status, stdout, stderr = run_doctor(entries: [entry("id" => "copy-ok", "target" => "~/.config/readme-copy", "mode" => "copy"), unsupported])

    expect(status).to eq(1)
    expect(stdout).to include("Managed files: 1 OK")
    expect(stderr).to include("weird target has unsupported mode")
  end

  it "reports pending and invalid VS Code state" do
    pending_manager = vscode_manager([{ "type" => "setting", "action" => "write", "key" => "x" }])
    status, _stdout, stderr = run_doctor(entries: [], manager: pending_manager)

    expect(status).to eq(1)
    expect(stderr).to include("VS Code desired state has pending changes")

    invalid_manager = instance_double(Dotfiles::VSCode::Manager, validate!: nil)
    allow(invalid_manager).to receive(:validate!).and_raise(Dotfiles::VSCode::Error, "bad vscode")
    status, _stdout, stderr = run_doctor(entries: [], manager: invalid_manager)

    expect(status).to eq(1)
    expect(stderr).to include("VS Code manifest validation failed", "bad vscode")
  end
end
