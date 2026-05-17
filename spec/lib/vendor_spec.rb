# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/dotfiles/vendor"

RSpec.describe Dotfiles::Vendor do
  OLD_LOCKFILE = <<~LOCK
    GEM
      remote: https://rubygems.org/
      specs:
        old-gem (1.0.0)
        platform-gem (2.0.0-arm64-darwin)
          old-gem (~> 1.0)

    PLATFORMS
      ruby

    DEPENDENCIES
      old-gem
      platform-gem
  LOCK

  TOO_NEW_LOCKFILE = <<~LOCK
    GEM
      remote: https://rubygems.org/
      specs:
        fresh-gem (9.0.0)

    PLATFORMS
      ruby

    DEPENDENCIES
      fresh-gem
  LOCK

  class FakeRubyGemsClient
    attr_reader :calls

    def initialize(versions_by_name)
      @versions_by_name = versions_by_name
      @calls = []
    end

    def versions(name)
      @calls << name
      @versions_by_name.fetch(name)
    end
  end

  def build_vendor(argv: [], runner: ->(*) { true }, metadata_client: old_metadata, clock: fixed_clock, dependabot_path: default_dependabot_path, lockfile_path: default_lockfile_path)
    described_class.new(
      argv: argv,
      out: StringIO.new,
      err: StringIO.new,
      runner: runner,
      metadata_client: metadata_client,
      clock: clock,
      dependabot_path: dependabot_path,
      lockfile_path: lockfile_path
    )
  end

  def fixed_clock
    -> { Time.utc(2026, 5, 17, 12, 0, 0) }
  end

  def old_metadata
    FakeRubyGemsClient.new(
      "old-gem" => [
        { "number" => "1.0.0", "platform" => "ruby", "created_at" => "2025-01-01T00:00:00Z" }
      ],
      "platform-gem" => [
        { "number" => "2.0.0", "platform" => "arm64-darwin", "created_at" => "2025-02-01T00:00:00Z" }
      ]
    )
  end

  def fresh_metadata
    FakeRubyGemsClient.new(
      "fresh-gem" => [
        { "number" => "9.0.0", "platform" => "ruby", "created_at" => "2026-05-01T00:00:00Z" }
      ]
    )
  end

  def default_dependabot_path
    @default_dependabot_path ||= write_dependabot
  end

  def default_lockfile_path
    @default_lockfile_path ||= write_lockfile(OLD_LOCKFILE)
  end

  def write_dependabot(text = nil)
    path = File.join(tmpdir, "dependabot.yml")
    File.write(path, text || <<~YAML)
      ---
      version: 2
      updates:
        - package-ecosystem: bundler
          directory: "/"
          cooldown:
            default-days: 45
    YAML
    path
  end

  def write_lockfile(text)
    path = File.join(tmpdir, "Gemfile.lock")
    File.write(path, text)
    path
  end

  def tmpdir
    @tmpdir ||= Dir.mktmpdir
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
    expect(vendor.out.string).to include(
      "📦 dotfiles vendor",
      "🧊 RubyGems cooldown: 45 days from #{default_dependabot_path}",
      "✅ RubyGems cooldown satisfied for 2 locked gem(s).",
      "✅ Vendored Ruby dependencies are refreshed."
    )
    expect(vendor.err.string).to eq("")
  end

  it "supports dry runs without executing commands" do
    calls = []
    metadata_client = FakeRubyGemsClient.new({})
    vendor = build_vendor(argv: ["--dry-run"], runner: ->(*) { calls << true }, metadata_client: metadata_client, lockfile_path: File.join(tmpdir, "missing.lock"))

    expect(vendor.run).to eq(0)

    expect(calls).to eq([])
    expect(metadata_client.calls).to eq([])
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

  it "restores the previous lockfile when the release cooldown rejects a resolved gem" do
    lockfile_path = write_lockfile(OLD_LOCKFILE)
    calls = []
    runner = lambda do |_env, *command, chdir:|
      calls << [command, chdir]
      File.write(lockfile_path, TOO_NEW_LOCKFILE) if command.include?("--add-checksums")
      true
    end
    vendor = build_vendor(runner: runner, metadata_client: fresh_metadata, lockfile_path: lockfile_path)

    expect(vendor.run).to eq(1)

    expect(calls).to eq([[["bundle", "lock", "--add-checksums"], ROOT]])
    expect(File.read(lockfile_path)).to eq(OLD_LOCKFILE)
    expect(vendor.err.string).to include(
      "RubyGems cooldown rejected versions newer than 45 days",
      "fresh-gem 9.0.0 was published 2026-05-01T00:00:00Z",
      "Gemfile.lock was restored to its pre-vendor state."
    )
  end

  it "returns an error when Gemfile.lock is missing" do
    vendor = build_vendor(lockfile_path: File.join(tmpdir, "missing.lock"))

    expect(vendor.run).to eq(1)

    expect(vendor.err.string).to include("Gemfile.lock not found:")
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

  describe Dotfiles::DependabotCooldownPolicy do
    it "loads the bundler cooldown from Dependabot" do
      policy = described_class.from_dependabot(default_dependabot_path)

      expect(policy.days).to eq(45)
      expect(policy.source_path).to eq(default_dependabot_path)
    end

    it "falls back to a non-root bundler entry when needed" do
      path = write_dependabot(<<~YAML)
        ---
        version: 2
        updates:
          - package-ecosystem: github-actions
            directory: "/"
            cooldown:
              default-days: 45
          - package-ecosystem: bundler
            directory: "/tools"
            cooldown:
              default-days: 30
      YAML

      expect(described_class.from_dependabot(path).days).to eq(30)
    end

    it "rejects missing Dependabot files" do
      expect { described_class.from_dependabot(File.join(tmpdir, "missing.yml")) }
        .to raise_error(Dotfiles::Error, /dependabot config not found/)
    end

    it "rejects Dependabot config without updates" do
      path = write_dependabot("---\nversion: 2\n")

      expect { described_class.from_dependabot(path) }
        .to raise_error(Dotfiles::Error, /missing required updates list/)
    end

    it "rejects Dependabot config without a bundler entry" do
      path = write_dependabot(<<~YAML)
        ---
        version: 2
        updates:
          - package-ecosystem: github-actions
            directory: "/"
            cooldown:
              default-days: 45
      YAML

      expect { described_class.from_dependabot(path) }
        .to raise_error(Dotfiles::Error, /no bundler update entry/)
    end

    it "rejects invalid cooldown values" do
      path = write_dependabot(<<~YAML)
        ---
        version: 2
        updates:
          - package-ecosystem: bundler
            directory: "/"
            cooldown:
              default-days: "45"
      YAML

      expect { described_class.from_dependabot(path) }
        .to raise_error(Dotfiles::Error, /cooldown.default-days must be a positive integer/)
    end

    it "rejects invalid YAML" do
      path = write_dependabot("updates:\n  - [")

      expect { described_class.from_dependabot(path) }
        .to raise_error(Dotfiles::Error, /invalid YAML/)
    end
  end

  describe Dotfiles::LockfileSpecs do
    it "parses only top-level RubyGems specs from Gemfile.lock" do
      specs = described_class.parse(OLD_LOCKFILE)

      expect(specs).to eq([
        Dotfiles::LockedGem.new(name: "old-gem", version: "1.0.0"),
        Dotfiles::LockedGem.new(name: "platform-gem", version: "2.0.0-arm64-darwin")
      ])
    end

    it "stops parsing when another lockfile section starts before specs" do
      expect(described_class.parse("GEM\nPLATFORMS\n  ruby\n")).to eq([])
    end
  end

  describe Dotfiles::RubyGemsClient do
    it "fetches and parses version metadata" do
      seen_uri = nil
      client = described_class.new(fetcher: lambda { |uri|
        seen_uri = uri
        '[{"number":"1.0.0","created_at":"2025-01-01T00:00:00Z"}]'
      })

      expect(client.versions("space gem")).to eq([{ "number" => "1.0.0", "created_at" => "2025-01-01T00:00:00Z" }])
      expect(seen_uri.to_s).to eq("https://rubygems.org/api/v1/versions/space+gem.json")
    end

    it "rejects invalid JSON metadata" do
      client = described_class.new(fetcher: ->(_uri) { "not json" })

      expect { client.versions("bad-gem") }
        .to raise_error(Dotfiles::Error, /invalid JSON/)
    end

    it "rejects metadata that is not an array" do
      client = described_class.new(fetcher: ->(_uri) { '{"number":"1.0.0"}' })

      expect { client.versions("bad-gem") }
        .to raise_error(Dotfiles::Error, /was not a JSON array/)
    end

    it "uses the RubyGems HTTP API with a stable user agent" do
      response = Struct.new(:code, :body).new("200", "[]")
      http = instance_double(Net::HTTP)
      expect(http).to receive(:request) do |request|
        expect(request["User-Agent"]).to eq(Dotfiles::RubyGemsClient::USER_AGENT)
        expect(request.uri.to_s).to eq("https://rubygems.org/api/v1/versions/old-gem.json")
        response
      end
      expect(Net::HTTP).to receive(:start)
        .with("rubygems.org", 443, use_ssl: true, open_timeout: 10, read_timeout: 10)
        .and_yield(http)

      expect(described_class.new.versions("old-gem")).to eq([])
    end

    it "fails closed when the RubyGems HTTP API does not return success" do
      response = Struct.new(:code, :body).new("500", "server error")
      http = instance_double(Net::HTTP, request: response)
      expect(Net::HTTP).to receive(:start).and_yield(http)

      expect { described_class.new.versions("old-gem") }
        .to raise_error(Dotfiles::Error, /HTTP 500/)
    end
  end

  describe Dotfiles::RubyGemsCooldown do
    def policy(days: 45)
      Dotfiles::DependabotCooldownPolicy.new(days: days, source_path: File.join(ROOT, ".github/dependabot.yml"))
    end

    def cooldown(client: old_metadata)
      described_class.new(policy: policy, client: client, clock: fixed_clock)
    end

    it "accepts locked gems older than the cooldown window" do
      specs = Dotfiles::LockfileSpecs.parse(OLD_LOCKFILE)

      expect(cooldown.validate!(specs)).to eq(true)
    end

    it "rejects an empty lockfile spec list" do
      expect { cooldown.validate!([]) }
        .to raise_error(Dotfiles::Error, /no RubyGems specs/)
    end

    it "rejects locked gems newer than the cooldown window" do
      specs = Dotfiles::LockfileSpecs.parse(TOO_NEW_LOCKFILE)

      expect { cooldown(client: fresh_metadata).validate!(specs) }
        .to raise_error(Dotfiles::ReleaseCooldownError, /wait until 2026-06-15T00:00:00Z/)
    end

    it "fails closed when RubyGems metadata does not include the locked version" do
      client = FakeRubyGemsClient.new("old-gem" => [])
      spec = Dotfiles::LockedGem.new(name: "old-gem", version: "1.0.0")

      expect { cooldown(client: client).validate!([spec]) }
        .to raise_error(Dotfiles::Error, /did not include old-gem 1.0.0/)
    end

    it "fails closed when RubyGems metadata has an invalid created_at timestamp" do
      client = FakeRubyGemsClient.new(
        "old-gem" => [{ "number" => "1.0.0", "platform" => "ruby", "created_at" => "nope" }]
      )
      spec = Dotfiles::LockedGem.new(name: "old-gem", version: "1.0.0")

      expect { cooldown(client: client).validate!([spec]) }
        .to raise_error(Dotfiles::Error, /invalid created_at/)
    end
  end
end
