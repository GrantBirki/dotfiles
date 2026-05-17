# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/dotfiles/manifest"

RSpec.describe Dotfiles::Manifest do
  around do |example|
    original_home = ENV.fetch("HOME")
    Dir.mktmpdir do |home|
      ENV["HOME"] = home
      example.run
    end
  ensure
    ENV["HOME"] = original_home
  end

  def manifest_entry(id: "bashrc", source: "README.md", target: "~/.bashrc", mode: "symlink", parent: "create", compare: nil, optional: nil)
    {
      "id" => id,
      "source" => source,
      "target" => target,
      "mode" => mode,
      "parent" => parent
    }.tap do |entry|
      entry["compare"] = compare if compare
      entry["optional"] = optional unless optional.nil?
    end
  end

  def write_manifest(path, files)
    File.write(path, { "files" => files }.to_yaml)
  end

  it "loads and validates a valid manifest" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "install.yml")
      write_manifest(path, [manifest_entry])

      manifest = described_class.load(path)

      expect(manifest.path).to eq(File.expand_path(path))
      expect(manifest.entries.map(&:id)).to eq(["bashrc"])
      expect(manifest.validate).to eq([])
      expect(manifest.validate!).to eq(true)
    end
  end

  it "raises a useful error when the manifest file is missing" do
    expect do
      described_class.load("/tmp/does-not-exist-dotfiles-manifest.yml")
    end.to raise_error(Dotfiles::Error, %r{manifest not found: /tmp/does-not-exist-dotfiles-manifest.yml})
  end

  it "requires the top-level files key" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "install.yml")
      File.write(path, { "not_files" => [] }.to_yaml)

      expect { described_class.load(path) }.to raise_error(Dotfiles::Error, "manifest is missing required `files` key")
    end
  end

  it "requires files to be an array" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "install.yml")
      File.write(path, { "files" => "nope" }.to_yaml)

      expect { described_class.load(path) }.to raise_error(Dotfiles::Error, "manifest `files` must be an array")
    end
  end

  it "requires each file entry to be a map" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "install.yml")
      write_manifest(path, ["not-a-map"])

      expect { described_class.load(path) }.to raise_error(Dotfiles::Error, "manifest file entry must be a map")
    end
  end

  it "reports duplicate ids and duplicate targets" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "install.yml")
      write_manifest(path, [
        manifest_entry(id: "same", target: "~/.same"),
        manifest_entry(id: "same", target: "~/.same")
      ])

      manifest = described_class.load(path)

      expect(manifest.validate).to include("duplicate id: same", "duplicate target: ~/.same")
      expect { manifest.validate! }.to raise_error(Dotfiles::Error, /duplicate id: same/)
    end
  end

end

RSpec.describe Dotfiles::Entry do
  around do |example|
    original_home = ENV.fetch("HOME")
    Dir.mktmpdir do |home|
      ENV["HOME"] = home
      example.run
    end
  ensure
    ENV["HOME"] = original_home
  end

  it "validates missing required fields" do
    entry = described_class.new({})

    expect(entry.validate(index: 3)).to include(
      "entry 3 is missing id",
      "entry 3 is missing source",
      "entry 3 is missing target",
      "entry 3 is missing mode",
      "entry 3 is missing parent"
    )
  end

  it "validates source, target, mode, and parent constraints" do
    entry = described_class.new(
      "id" => "bad",
      "source" => "/tmp/not-in-repo",
      "target" => "/tmp/not-home",
      "mode" => "copy",
      "parent" => "skip",
      "compare" => "unknown"
    )

    expect(entry.validate(index: 0)).to include(
      "bad: source must be repo-relative",
      "bad: source does not exist: /tmp/not-in-repo",
      "bad: target must start with ~/; got /tmp/not-home",
      "bad: unsupported parent policy skip",
      "bad: unsupported compare strategy unknown"
    )
  end

  it "supports copy mode and a karabiner comparison strategy" do
    entry = described_class.new(
      "id" => "karabiner",
      "source" => "configs/karabiner/karabiner.json",
      "target" => "~/.config/karabiner/karabiner.json",
      "mode" => "copy",
      "parent" => "require",
      "compare" => "karabiner"
    )

    expect(entry.validate(index: 0)).to eq([])
    expect(entry.compare).to eq("karabiner")
  end

  it "supports inactive optional sources for private local config" do
    entry = described_class.new(
      "id" => "vscode-mcp-private",
      "source" => "configs/vsc/mcp.json",
      "target" => "~/Library/Application Support/Code/User/mcp.json",
      "mode" => "symlink",
      "parent" => "create",
      "optional" => true
    )

    expect(entry.validate(index: 0)).to eq([])
    expect(entry.optional).to eq(true)
    expect(entry.active?).to eq(false)
    expect(entry.to_h).to include("optional" => true, "active" => false)
  end

  it "rejects invalid optional values" do
    entry = described_class.new(
      "id" => "bad-optional",
      "source" => "README.md",
      "target" => "~/.config/bad",
      "mode" => "symlink",
      "parent" => "create",
      "optional" => "yes"
    )

    expect(entry.validate(index: 0)).to include("bad-optional: optional must be true or false")
  end

  it "rejects tilde-prefixed sources" do
    entry = described_class.new(
      "id" => "tilde",
      "source" => "~/secret",
      "target" => "~/.secret",
      "mode" => "symlink",
      "parent" => "create"
    )

    expect(entry.validate(index: 0)).to include("tilde: source must be repo-relative")
  end

  it "expands paths and serializes install metadata" do
    entry = described_class.new(
      "id" => "readme",
      "source" => "README.md",
      "target" => "~/.config/readme",
      "mode" => "symlink",
      "parent" => "require"
    )

    expect(entry.source_path).to eq(File.join(Dotfiles::ROOT, "README.md"))
    expect(entry.target_path).to eq(File.join(ENV.fetch("HOME"), ".config/readme"))
    expect(entry.backup_path).to eq(File.join(ENV.fetch("HOME"), "dotfiles_old/.config/readme"))
    expect(entry.target_parent).to eq(File.join(ENV.fetch("HOME"), ".config"))
    expect(entry.to_h).to include(
      "id" => "readme",
      "source" => "README.md",
      "target" => "~/.config/readme",
      "mode" => "symlink",
      "parent" => "require",
      "compare" => "exact",
      "optional" => false,
      "active" => true
    )
  end
end
