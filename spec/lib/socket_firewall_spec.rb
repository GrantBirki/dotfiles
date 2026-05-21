# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/dotfiles/socket_firewall"

RSpec.describe Dotfiles::SocketFirewall do
  def executable(dir, name)
    FileUtils.mkdir_p(dir)
    path = File.join(dir, name)
    File.write(path, "#!/bin/sh\n")
    FileUtils.chmod("+x", path)
    path
  end

  def build(argv: [], env: {}, runner: ->(*) { true }, home: "/home/user")
    described_class.new(
      argv: argv,
      out: StringIO.new,
      err: StringIO.new,
      runner: runner,
      env: env,
      home: home,
      root: ROOT
    )
  end

  it "builds protected paths and reports protected and unprotected command resolution" do
    Dir.mktmpdir do |dir|
      shim_dir = File.join(dir, "sfw-shims")
      real_dir = File.join(dir, "real")
      sfw_shim = executable(shim_dir, "sfw")
      npm_shim = executable(shim_dir, "npm")
      real_sfw = executable(real_dir, "sfw")
      real_npm = executable(real_dir, "npm")
      firewall = build(env: {
        "DOTFILES_SFW_SHIM_DIR" => shim_dir,
        "DOTFILES_SFW_REQUIRE" => "0",
        "DOTFILES_SFW_DISABLE" => "1",
        "PATH" => [shim_dir, real_dir, ""].join(File::PATH_SEPARATOR)
      })

      expect(firewall.path_without_shims).to eq(real_dir)
      expect(firewall.protected_path).to eq([shim_dir, real_dir].join(File::PATH_SEPARATOR))
      expect(firewall.resolve_command("npm", path: firewall.protected_path)).to eq(npm_shim)
      expect(firewall.resolve_command("missing", path: firewall.protected_path)).to be_nil

      data = firewall.status_data
      expect(data.fetch("commands").find { |row| row.fetch("name") == "sfw" })
        .to include("protected" => sfw_shim, "unprotected" => real_sfw)
      expect(data.fetch("commands").find { |row| row.fetch("name") == "npm" })
        .to include("protected" => npm_shim, "unprotected" => real_npm)
      expect(firewall.format_status(data)).to include(
        "Socket Firewall status",
        "require mode: 0",
        "disabled:     1",
        "npm    protected:"
      )
    end
  end

  it "prints status by default" do
    firewall = build(env: { "PATH" => "" })

    expect(firewall.run).to eq(0)
    expect(firewall.out.string).to include("Socket Firewall status", "sfw    protected:   <missing>")
  end

  it "prints Codex config with the protected path" do
    Dir.mktmpdir do |dir|
      env = {
        "DOTFILES_SFW_SHIM_DIR" => File.join(dir, "shim"),
        "DOTFILES_SFW_REQUIRE" => "1",
        "PATH" => File.join(dir, "bin")
      }
      firewall = build(argv: ["codex-config"], env: env)

      expect(firewall.run).to eq(0)
      expect(firewall.out.string).to include(
        "[shell_environment_policy]",
        "DOTFILES_SFW_REQUIRE = \"1\"",
        "DOTFILES_SFW_SHIM_DIR = \"#{File.join(dir, "shim")}\"",
        "PATH = \"#{File.join(dir, "shim")}:#{File.join(dir, "bin")}\""
      )
    end
  end

  it "returns doctor success when real sfw is available outside the shim directory" do
    Dir.mktmpdir do |dir|
      real_dir = File.join(dir, "real")
      executable(real_dir, "sfw")
      firewall = build(argv: ["doctor"], env: { "PATH" => real_dir })

      expect(firewall.run).to eq(0)
      expect(firewall.out.string).to include("sfw    unprotected: #{File.join(real_dir, "sfw")}")
      expect(firewall.err.string).to eq("")
    end
  end

  it "returns doctor failure when sfw is required but unavailable" do
    firewall = build(argv: ["doctor"], env: { "PATH" => "", "DOTFILES_SFW_REQUIRE" => "1" })

    expect(firewall.run).to eq(1)
    expect(firewall.err.string).to eq("sfw is required but unavailable outside the protected shim directory\n")
  end

  it "installs sfw and rehashes nodenv when nodenv is available" do
    Dir.mktmpdir do |dir|
      executable(dir, "nodenv")
      calls = []
      runner = lambda do |env, *command, chdir:|
        calls << [env, command, chdir]
        true
      end
      firewall = build(argv: ["install"], env: { "PATH" => dir }, runner: runner)

      expect(firewall.run).to eq(0)
      expect(calls).to eq([
        [{ "DOTFILES_SFW_DISABLE" => "1" }, %w[npm i -g sfw], ROOT],
        [{}, %w[nodenv rehash], ROOT]
      ])
      expect(firewall.out.string).to include("Socket Firewall install")
    end
  end

  it "supports dry-run installs and skips nodenv rehash when nodenv is missing" do
    firewall = build(argv: ["install", "--dry-run"], env: { "PATH" => "" }, runner: ->(*) { raise "should not run" })

    expect(firewall.run).to eq(0)
    expect(firewall.out.string).to include(
      "would run: DOTFILES_SFW_DISABLE=1 npm i -g sfw",
      "nodenv not found; skipped nodenv rehash"
    )
  end

  it "reports failed install commands" do
    firewall = build(argv: ["install"], env: { "PATH" => "" }, runner: ->(*) { false })

    expect(firewall.run).to eq(1)
    expect(firewall.err.string).to eq("command failed: DOTFILES_SFW_DISABLE=1 npm i -g sfw\n")
  end

  it "cleans package-manager caches with SFW disabled" do
    Dir.mktmpdir do |dir|
      executable(dir, "npm")
      firewall = build(argv: ["cache-clean", "--dry-run"], env: { "PATH" => dir, "CARGO_HOME" => File.join(dir, "cargo") })

      expect(firewall.run).to eq(0)
      expect(firewall.out.string).to include(
        "Socket Firewall cache clean",
        "would run: DOTFILES_SFW_DISABLE=1 npm cache clean --force",
        "skipping yarn v1 cache clean; command not found: yarn",
        "would run: rm -fr #{File.join(dir, "cargo/registry")} #{File.join(dir, "cargo/git")}"
      )
    end
  end

  it "prints usage for help" do
    firewall = build(argv: ["--help"])

    expect { firewall.run }.to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
    expect(firewall.out.string).to include("Usage: script/socket-firewall")
  end

  it "rejects unknown options and commands" do
    bad_option = build(argv: ["status", "--wat"])
    bad_command = build(argv: ["wat"])

    expect(bad_option.run).to eq(1)
    expect(bad_option.err.string).to include("Unknown option: --wat", "Usage: script/socket-firewall")
    expect(bad_command.run).to eq(2)
    expect(bad_command.err.string).to eq("Usage: script/socket-firewall [status|doctor|install|cache-clean|codex-config] [--dry-run]\n")
  end
end
