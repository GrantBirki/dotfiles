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

  def successful_status
    instance_double(Process::Status, success?: true)
  end

  def failed_status
    instance_double(Process::Status, success?: false)
  end

  def secretive_socket_path
    File.join(@home, "Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh")
  end

  def git_signing_key_path
    File.join(@home, ".config/git/secretive_git_key.pub")
  end

  def git_allowed_signers_path
    File.join(@home, ".config/git/allowed_signers")
  end

  def prepare_secretive_git(key: "ssh-ed25519 AAAATEST git")
    FileUtils.mkdir_p(File.dirname(git_signing_key_path))
    File.write(git_signing_key_path, "#{key}\n")
    File.write(git_allowed_signers_path, "grant.birkinbine@gmail.com #{key}\n")
  end

  def run_doctor(entries:, manager: vscode_manager, state_dir: nil, secretive_socket_checker: nil)
    stdout = StringIO.new
    stderr = StringIO.new
    doctor = described_class.new(
      argv: [],
      out: stdout,
      err: stderr,
      manifest: manifest(entries),
      vscode_manager: manager,
      state_dir: state_dir || File.join(@home, "state"),
      secretive_socket_checker: secretive_socket_checker,
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
    prepare_secretive_git
    allow(Open3).to receive(:capture3)
      .with({ "SSH_AUTH_SOCK" => secretive_socket_path }, "ssh-add", "-L")
      .and_return(["ssh-ed25519 AAAATEST git\n", "", successful_status])

    status, stdout, stderr = run_doctor(entries: [entry], state_dir: state_dir, secretive_socket_checker: ->(path) { path == secretive_socket_path })

    expect(status).to eq(0)
    expect(stderr).to eq("")
    expect(stdout).to include("Commands: 4/4 required, 7/7 optional available")
    expect(stdout).to include("Managed files: 1 OK", "VS Code: manifests valid and desired state converged")
    expect(stdout).to include("Secretive socket:", "Git signing key:", "Git allowed signers:", "Secretive agent exposes Git signing key")
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

  it "warns when Secretive local files are missing" do
    status, _stdout, stderr = run_doctor(entries: [])

    expect(status).to eq(0)
    expect(stderr).to include(
      "Secretive socket is missing",
      "Git signing key is missing or unreadable",
      "Git allowed signers is missing or unreadable"
    )
  end

  it "warns when Secretive agent keys cannot be queried" do
    prepare_secretive_git
    allow(Open3).to receive(:capture3)
      .with({ "SSH_AUTH_SOCK" => secretive_socket_path }, "ssh-add", "-L")
      .and_return(["", "agent unavailable\n", failed_status])

    status, _stdout, stderr = run_doctor(entries: [], secretive_socket_checker: ->(path) { path == secretive_socket_path })

    expect(status).to eq(0)
    expect(stderr).to include("Secretive agent keys could not be queried: agent unavailable")
  end

  it "warns when the configured key is empty or absent from Secretive" do
    prepare_secretive_git(key: "# comment only")
    allow(Open3).to receive(:capture3)
      .with({ "SSH_AUTH_SOCK" => secretive_socket_path }, "ssh-add", "-L")
      .and_return(["ssh-ed25519 OTHER key\n", "", successful_status])

    first_status, _first_stdout, first_stderr = run_doctor(entries: [], secretive_socket_checker: ->(path) { path == secretive_socket_path })
    expect(first_status).to eq(0)
    expect(first_stderr).to include("Git signing key file does not contain a public SSH key")

    prepare_secretive_git
    allow(Open3).to receive(:capture3)
      .with({ "SSH_AUTH_SOCK" => secretive_socket_path }, "ssh-add", "-L")
      .and_return(["ssh-ed25519 OTHER key\n", "", successful_status])

    second_status, _second_stdout, second_stderr = run_doctor(entries: [], secretive_socket_checker: ->(path) { path == secretive_socket_path })
    expect(second_status).to eq(0)
    expect(second_stderr).to include("Secretive agent does not expose the configured Git signing key")
  end
end
