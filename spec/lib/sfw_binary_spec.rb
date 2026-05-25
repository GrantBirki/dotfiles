# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/dotfiles/sfw_binary"

RSpec.describe Dotfiles::SFWBinary do
  def digest_for(content)
    Digest::SHA256.hexdigest(content)
  end

  def metadata_file(dir, content: "binary")
    sha = digest_for(content)
    path = File.join(dir, "sfw.yml")
    File.write(path, {
      "version" => "vtest",
      "asset" => "sfw-free-macos-arm64",
      "url" => "https://github.com/SocketDev/sfw-free/releases/download/vtest/sfw-free-macos-arm64",
      "sha256" => sha,
      "size" => content.bytesize,
      "github_digest" => "sha256:#{sha}",
      "upstream_repo" => "SocketDev/sfw-free",
      "release_api_url" => "https://api.github.com/repos/SocketDev/sfw-free/releases/tags/vtest",
      "license" => {
        "name" => "PolyForm Shield License 1.0.0",
        "url" => "https://github.com/SocketDev/sfw-free#license"
      }
    }.to_yaml)
    path
  end

  def release_for(binary)
    {
      "tag_name" => binary.metadata.fetch("version"),
      "assets" => [
        {
          "name" => binary.metadata.fetch("asset"),
          "browser_download_url" => binary.metadata.fetch("url"),
          "size" => binary.metadata.fetch("size"),
          "digest" => binary.metadata.fetch("github_digest")
        }
      ]
    }
  end

  def command_result(success:, stdout: "", stderr: "")
    Dotfiles::SFWBinary::CommandResult.new(success: success, stdout: stdout, stderr: stderr)
  end

  def build(config_path:, env:, home:, release: nil, downloader: nil, commands: [])
    command_runner = lambda do |_command|
      commands.empty? ? command_result(success: true) : commands.shift
    end
    binary = nil
    release_fetcher = release || ->(_url) { release_for(binary) }
    binary = described_class.new(
      config_path: config_path,
      env: env,
      home: home,
      out: StringIO.new,
      err: StringIO.new,
      release_fetcher: release_fetcher,
      downloader: downloader || ->(_url, path) { File.write(path, "binary") },
      command_runner: command_runner
    )
    binary
  end

  class FakeHTTPSuccess < Net::HTTPSuccess
    attr_reader :code, :body

    def initialize(body: "")
      @code = "200"
      @body = body
    end

    def read_body
      yield body
    end
  end

  class FakeHTTPRedirect < Net::HTTPRedirection
    attr_reader :code

    def initialize(location:)
      @code = "302"
      @location = location
    end

    def [](key)
      key == "location" ? @location : nil
    end
  end

  class FakeHTTPError < Net::HTTPResponse
    attr_reader :code

    def initialize(code:)
      @code = code
    end
  end

  class FakeHTTP
    def initialize(response)
      @response = response
    end

    def request(_request)
      if block_given?
        yield @response
      else
        @response
      end
    end
  end

  def stub_net_http(*responses)
    queue = responses.dup
    allow(Net::HTTP).to receive(:start) do |_host, _port, use_ssl:, &block|
      expect(use_ssl).to eq(true)
      block.call(FakeHTTP.new(queue.shift))
    end
  end

  it "loads metadata and verifies an existing matching binary" do
    Dir.mktmpdir do |dir|
      config = metadata_file(dir)
      target = File.join(dir, "bin/sfw")
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, "binary")
      FileUtils.chmod(0o755, target)
      binary = described_class.new(
        config_path: config,
        env: { "DOTFILES_SFW_BIN" => target },
        home: dir,
        out: StringIO.new,
        err: StringIO.new,
        command_runner: ->(_command) { command_result(success: true) }
      )

      expect(binary.target_path).to eq(target)
      expect(binary.expected_sha256).to eq(digest_for("binary"))
      expect(binary.actual_sha256(target)).to eq(digest_for("binary"))
      expect(binary.matching?).to eq(true)
      expect(binary.install).to eq(true)
      expect(binary.out.string).to include("already converged")
      expect(binary.verify).to eq(true)
      expect(binary.out.string).to include("status:   ok")
      expect(binary.status).to include(
        "hash_status" => "ok",
        "executable_status" => "ok",
        "signing_status" => "valid",
        "quarantine_status" => "present"
      )
    end
  end

  it "repairs executable mode for a matching target without network access" do
    Dir.mktmpdir do |dir|
      config = metadata_file(dir)
      target = File.join(dir, ".local/bin/sfw")
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, "binary")
      FileUtils.chmod(0o644, target)
      binary = described_class.new(
        config_path: config,
        env: {},
        home: dir,
        out: StringIO.new,
        err: StringIO.new,
        release_fetcher: ->(_url) { raise "should not fetch" },
        downloader: ->(_url, _path) { raise "should not download" },
        command_runner: ->(_command) { command_result(success: true) }
      )

      expect(binary.status).to include("hash_status" => "ok", "executable_status" => "not-executable")
      expect(binary.install).to eq(true)
      expect(File.stat(target).mode & 0o777).to eq(0o755)
      expect(binary.out.string).to include("repaired executable mode")
    end
  end

  it "previews executable mode repair for a matching target" do
    Dir.mktmpdir do |dir|
      config = metadata_file(dir)
      target = File.join(dir, ".local/bin/sfw")
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, "binary")
      FileUtils.chmod(0o644, target)
      binary = described_class.new(
        config_path: config,
        env: {},
        home: dir,
        out: StringIO.new,
        err: StringIO.new,
        release_fetcher: ->(_url) { raise "should not fetch" },
        downloader: ->(_url, _path) { raise "should not download" }
      )

      expect(binary.install(dry_run: true)).to eq(true)
      expect(File.stat(target).mode & 0o777).to eq(0o644)
      expect(binary.out.string).to include("would repair executable mode")
    end
  end

  it "reports missing and mismatched verification failures" do
    Dir.mktmpdir do |dir|
      config = metadata_file(dir)
      missing = described_class.new(config_path: config, env: {}, home: dir, out: StringIO.new, err: StringIO.new)
      expect { missing.verify }.to raise_error(Dotfiles::Error, /missing/)

      target = File.join(dir, ".local/bin/sfw")
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, "wrong")
      mismatch = described_class.new(config_path: config, env: {}, home: dir, out: StringIO.new, err: StringIO.new)
      expect(mismatch.matching?).to eq(false)
      expect { mismatch.verify }.to raise_error(Dotfiles::Error, /SHA256 mismatch/)
      expect(mismatch.status).to include("hash_status" => "mismatch", "executable_status" => "not-executable")
    end
  end

  it "previews missing installs without network or filesystem mutation" do
    Dir.mktmpdir do |dir|
      config = metadata_file(dir)
      binary = described_class.new(
        config_path: config,
        env: {},
        home: dir,
        out: StringIO.new,
        err: StringIO.new,
        release_fetcher: ->(_url) { raise "should not fetch" },
        downloader: ->(_url, _path) { raise "should not download" }
      )

      expect(binary.install(dry_run: true)).to eq(true)
      expect(binary.out.string).to include("would install sfw-free-macos-arm64")
      expect(File).not_to exist(File.join(dir, ".local/bin/sfw"))
    end
  end

  it "installs from a verified local seed and backs up an existing target" do
    Dir.mktmpdir do |dir|
      config = metadata_file(dir)
      seed = File.join(dir, "Downloads/sfw-free-macos-arm64")
      target = File.join(dir, ".local/bin/sfw")
      FileUtils.mkdir_p(File.dirname(seed))
      FileUtils.mkdir_p(File.dirname(target))
      File.write(seed, "binary")
      File.write(target, "old")
      commands = [
        command_result(success: false, stderr: "code object is not signed at all"),
        command_result(success: false)
      ]
      binary = build(config_path: config, env: {}, home: dir, commands: commands)

      expect(binary.install).to eq(true)
      expect(File.read(target)).to eq("binary")
      expect(File.stat(target).mode & 0o777).to eq(0o755)
      expect(Dir[File.join(dir, ".local/bin/sfw.bak*")].length).to eq(1)
      expect(binary.out.string).to include(
        "using verified local asset",
        "removed quarantine attribute for unsigned binary",
        "installed #{target}"
      )
    end
  end

  it "downloads when no local seed is available" do
    Dir.mktmpdir do |dir|
      config = metadata_file(dir, content: "downloaded")
      target = File.join(dir, ".local/bin/sfw")
      binary = build(
        config_path: config,
        env: {},
        home: dir,
        downloader: ->(_url, path) { File.write(path, "downloaded") },
        commands: [command_result(success: true)]
      )

      expect(binary.install).to eq(true)
      expect(File.read(target)).to eq("downloaded")
      expect(File).to exist(File.join(Dotfiles::ROOT, ".dotfiles/cache/sfw/sfw-free-macos-arm64"))
      expect(binary.out.string).to include("downloading", "signed binary verified")
    ensure
      FileUtils.rm_f(File.join(Dotfiles::ROOT, ".dotfiles/cache/sfw/sfw-free-macos-arm64"))
    end
  end

  it "rejects invalid explicit seed, invalid release metadata, bad downloads, and invalid signatures" do
    Dir.mktmpdir do |dir|
      config = metadata_file(dir)
      explicit = File.join(dir, "bad-sfw")
      File.write(explicit, "wrong")
      explicit_binary = build(config_path: config, env: { "DOTFILES_SFW_ASSET" => explicit }, home: dir)
      expect { explicit_binary.install }.to raise_error(Dotfiles::Error, /DOTFILES_SFW_ASSET failed/)

      bad_release = build(config_path: config, env: {}, home: dir, release: ->(_url) { { "tag_name" => "bad", "assets" => [] } })
      expect { bad_release.install }.to raise_error(Dotfiles::Error, /tag mismatch/)

      missing_key = build(config_path: config, env: {}, home: dir, release: ->(_url) { { "assets" => [] } })
      expect { missing_key.install }.to raise_error(Dotfiles::Error, /missing key/)

      default_seed = File.join(dir, "Downloads/sfw-free-macos-arm64")
      FileUtils.mkdir_p(File.dirname(default_seed))
      File.write(default_seed, "wrong")
      ignored_seed = build(config_path: config, env: {}, home: dir, commands: [command_result(success: true)])
      expect(ignored_seed.install).to eq(true)
      expect(ignored_seed.out.string).to include("ignoring unverified local asset")
      FileUtils.rm_f(default_seed)
      FileUtils.rm_f(File.join(dir, ".local/bin/sfw"))
      FileUtils.rm_f(File.join(Dotfiles::ROOT, ".dotfiles/cache/sfw/sfw-free-macos-arm64"))

      bad_download = build(config_path: config, env: {}, home: dir, downloader: ->(_url, path) { File.write(path, "wrong") })
      expect { bad_download.install }.to raise_error(Dotfiles::Error, /downloaded SFW asset failed/)

      seed = File.join(dir, "Downloads/sfw-free-macos-arm64")
      FileUtils.mkdir_p(File.dirname(seed))
      File.write(seed, "binary")
      FileUtils.rm_f(File.join(dir, ".local/bin/sfw"))
      invalid_signature = build(config_path: config, env: {}, home: dir, commands: [command_result(success: false, stderr: "rejected")])
      expect { invalid_signature.install }.to raise_error(Dotfiles::Error, /signature verification failed/)
    end
  end

  it "validates metadata shape" do
    Dir.mktmpdir do |dir|
      missing = File.join(dir, "missing.yml")
      expect { described_class.new(config_path: missing, env: {}, home: dir).metadata }.to raise_error(Dotfiles::Error, /not found/)

      invalid = File.join(dir, "invalid.yml")
      File.write(invalid, {
        "version" => "v",
        "asset" => "bad",
        "url" => "http://example.com",
        "sha256" => "bad",
        "size" => 0,
        "github_digest" => "sha256:bad",
        "upstream_repo" => "SocketDev/sfw-free",
        "release_api_url" => "http://example.com",
        "license" => { "name" => "MIT" }
      }.to_yaml)

      expect { described_class.new(config_path: invalid, env: {}, home: dir).metadata }.to raise_error(Dotfiles::Error, /sha256/)

      missing_key = File.join(dir, "missing-key.yml")
      File.write(missing_key, {}.to_yaml)
      expect { described_class.new(config_path: missing_key, env: {}, home: dir).metadata }.to raise_error(Dotfiles::Error, /missing required keys/)
    end
  end

  it "fetches release metadata and downloads assets over HTTP" do
    stub_net_http(
      FakeHTTPSuccess.new(body: "{\"tag_name\":\"v\",\"assets\":[]}"),
      FakeHTTPRedirect.new(location: "/asset"),
      FakeHTTPSuccess.new(body: "asset"),
      FakeHTTPError.new(code: "500"),
      FakeHTTPSuccess.new(body: "nope")
    )
    binary = described_class.new(config_path: metadata_file(Dir.mktmpdir), env: {}, home: Dir.mktmpdir)
    expect(binary.send(:fetch_release, "https://example.test/release")).to eq({ "tag_name" => "v", "assets" => [] })

    destination = File.join(Dir.mktmpdir, "asset")
    binary.send(:download, "https://example.test/redirect", destination)
    expect(File.read(destination)).to eq("asset")

    expect { binary.send(:download, "https://example.test/fail", destination) }.to raise_error(Dotfiles::Error, /HTTP 500/)
    expect { binary.send(:fetch_release, "https://example.test/bad-json") }.to raise_error(Dotfiles::Error, /parse/)
    expect { binary.send(:download, "https://example.test/loop", destination, 0) }.to raise_error(Dotfiles::Error, /too many redirects/)
  end
end
