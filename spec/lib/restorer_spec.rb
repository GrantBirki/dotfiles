# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/dotfiles/restorer"

RSpec.describe Dotfiles::Restorer do
  def write_state(dir, rows)
    path = File.join(dir, "install-20260517120000.tsv")
    File.write(path, (["id\tsource_path\ttarget_path\tbackup_path\taction"] + rows.map { |row| row.join("\t") }).join("\n"))
    path
  end

  def run_restorer(argv:, state_dir:)
    stdout = StringIO.new
    stderr = StringIO.new
    status = described_class.new(argv: argv, out: stdout, err: stderr, state_dir: state_dir).run
    [status, stdout.string, stderr.string]
  end

  it "reports missing state files" do
    Dir.mktmpdir do |dir|
      status, stdout, stderr = run_restorer(argv: [], state_dir: dir)

      expect(status).to eq(1)
      expect(stdout).to eq("")
      expect(stderr).to include("No install state file found")
    end
  end

  it "handles CLI help, production, unknown options, and missing state values" do
    Dir.mktmpdir do |dir|
      stdout = StringIO.new
      restorer = described_class.new(argv: ["--help"], out: stdout, err: StringIO.new, state_dir: dir)
      expect { restorer.run }.to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
      expect(stdout.string).to include("Usage: script/restore")

      state = write_state(dir, [["skip", "source", "target", "", "skipped-parent"]])
      status, stdout, stderr = run_restorer(argv: ["--production"], state_dir: dir)
      expect(status).to eq(0)
      expect(stdout).to include("Using install state: #{state}")
      expect(stderr).to eq("")

      stderr = StringIO.new
      restorer = described_class.new(argv: ["--wat"], out: StringIO.new, err: stderr, state_dir: dir)
      expect { restorer.run }.to raise_error(SystemExit) { |error| expect(error.status).to eq(2) }
      expect(stderr.string).to include("Unknown option: --wat", "Usage: script/restore")

      stderr = StringIO.new
      restorer = described_class.new(argv: ["--state"], out: StringIO.new, err: stderr, state_dir: dir)
      expect { restorer.run }.to raise_error(SystemExit) { |error| expect(error.status).to eq(2) }
      expect(stderr.string).to include("--state requires a path")
    end
  end

  it "previews restoring a managed symlink from a backup" do
    Dir.mktmpdir do |dir|
      source = File.join(dir, "source")
      target = File.join(dir, "target")
      backup = File.join(dir, "backup")
      File.write(source, "managed")
      FileUtils.ln_s(source, target)
      File.write(backup, "original")
      state = write_state(dir, [["readme", source, target, backup, "linked"]])

      status, stdout, stderr = run_restorer(argv: ["--dry-run", "--state", state], state_dir: dir)

      expect(status).to eq(0)
      expect(stderr).to eq("")
      expect(stdout).to include("Would remove managed symlink: #{target}", "Would restore #{backup} to #{target}", "Restore complete.")
      expect(File.exist?(backup)).to eq(true)
      expect(File.symlink?(target)).to eq(true)
    end
  end

  it "restores backups while moving unexpected current targets aside" do
    Dir.mktmpdir do |dir|
      target = File.join(dir, "target")
      backup = File.join(dir, "backup")
      File.write(target, "new")
      File.write(backup, "old")
      state = write_state(dir, [["copy", File.join(dir, "source"), target, backup, "copied"]])

      status, _stdout, stderr = run_restorer(argv: ["--state", state], state_dir: dir)

      expect(status).to eq(0)
      expect(stderr).to eq("")
      expect(File.read(target)).to eq("old")
      expect(Dir[File.join(dir, "target.dotfiles_restore_backup*")].length).to eq(1)
    end
  end

  it "previews moving unexpected current targets before restoring backups" do
    Dir.mktmpdir do |dir|
      target = File.join(dir, "target")
      backup = File.join(dir, "backup")
      File.write(target, "new")
      File.write(backup, "old")
      state = write_state(dir, [["copy", File.join(dir, "source"), target, backup, "copied"]])

      status, stdout, stderr = run_restorer(argv: ["--dry-run", "--state", state], state_dir: dir)

      expect(status).to eq(0)
      expect(stderr).to eq("")
      expect(stdout).to include("Would move current #{target}", "Would restore #{backup} to #{target}")
      expect(File.read(target)).to eq("new")
      expect(File.read(backup)).to eq("old")
    end
  end

  it "handles missing backups, no-backup rows, skipped rows, and unknown actions" do
    Dir.mktmpdir do |dir|
      source = File.join(dir, "source")
      managed_link = File.join(dir, "managed-link")
      unexpected = File.join(dir, "unexpected")
      File.write(source, "managed")
      FileUtils.ln_s(source, managed_link)
      File.write(unexpected, "manual")
      state = write_state(dir, [
        ["missing", source, File.join(dir, "target"), File.join(dir, "nope"), "linked"],
        ["remove", source, managed_link, "", "linked"],
        ["copy", source, File.join(dir, "copy-target"), "", "copied"],
        ["absent", source, File.join(dir, "absent-target"), "", "linked"],
        ["unexpected", source, unexpected, "", "linked"],
        ["skip", source, File.join(dir, "skip-target"), "", "already-linked"],
        ["wat", source, File.join(dir, "wat-target"), "", "mystery"]
      ])

      status, stdout, stderr = run_restorer(argv: ["--state", state], state_dir: dir)

      expect(status).to eq(1)
      expect(stdout).to include("No original backup was recorded", "is already absent", "Skipping skip (already-linked).")
      expect(stderr).to include("Backup for missing is missing", "Refusing to remove unexpected current target", "Unknown action for wat")
      expect(File.exist?(managed_link)).to eq(false)
    end
  end
end
