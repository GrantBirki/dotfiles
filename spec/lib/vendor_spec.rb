# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/dotfiles/vendor"

RSpec.describe Dotfiles::Vendor do
  def build_vendor(argv: [], runner: ->(*) { true })
    described_class.new(argv: argv, out: StringIO.new, err: StringIO.new, runner: runner)
  end

  it "runs the vendoring commands with frozen mode disabled" do
    calls = []
    runner = lambda do |env, *command, chdir:|
      calls << [env, command, chdir]
      true
    end
    vendor = build_vendor(runner: runner)

    result = vendor.run

    expect(result).to eq(0)
    expect(calls).to eq([
      [{ "BUNDLE_FROZEN" => "false" }, ["bundle", "lock", "--add-checksums"], ROOT],
      [{ "BUNDLE_FROZEN" => "false" }, ["bundle", "cache", "--all", "--all-platforms", "--no-install"], ROOT]
    ])
    expect(vendor.out.string).to include("📦 dotfiles vendor", "✅ Vendored Ruby dependencies are refreshed.")
    expect(vendor.err.string).to eq("")
  end

  it "supports dry runs without executing commands" do
    calls = []
    vendor = build_vendor(argv: ["--dry-run"], runner: ->(*) { calls << true })

    expect(vendor.run).to eq(0)

    expect(calls).to eq([])
    expect(vendor.out.string).to include("⚠️  Dry run: no commands will be executed.")
    expect(vendor.argv).to eq([])
  end

  it "returns an error when a vendoring command fails" do
    calls = []
    runner = lambda do |_env, *command, chdir:|
      calls << [command, chdir]
      command.include?("--add-checksums") ? false : true
    end
    vendor = build_vendor(runner: runner)

    expect(vendor.run).to eq(1)

    expect(calls).to eq([[["bundle", "lock", "--add-checksums"], ROOT]])
    expect(vendor.err.string).to eq("command failed: bundle lock --add-checksums\n")
  end

  it "prints usage for help" do
    vendor = build_vendor(argv: ["--help"])

    expect { vendor.run }.to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
    expect(vendor.out.string).to include("Usage: script/vendor [--dry-run]")
  end

  it "rejects unknown options" do
    vendor = build_vendor(argv: ["--wat"])

    expect { vendor.run }.to raise_error(SystemExit) { |error| expect(error.status).to eq(2) }
    expect(vendor.err.string).to include("Unknown option: --wat", "Usage: script/vendor [--dry-run]")
  end
end
