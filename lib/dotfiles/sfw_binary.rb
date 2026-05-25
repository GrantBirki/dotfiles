# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "net/http"
require "open3"
require "tmpdir"
require "yaml"

require_relative "manifest"
require_relative "runtime"

module Dotfiles
  class SFWBinary
    DEFAULT_CONFIG_PATH = File.join(ROOT, "configs/sfw/sfw.yml")
    SHA256_PATTERN = /\A[0-9a-f]{64}\z/.freeze
    DIGEST_PREFIX = "sha256:"

    class CommandResult
      attr_reader :stdout, :stderr

      def initialize(success:, stdout: "", stderr: "")
        @success = success
        @stdout = stdout
        @stderr = stderr
      end

      def success?
        @success
      end
    end

    attr_reader :config_path, :env, :home, :out, :err

    def initialize(
      config_path: DEFAULT_CONFIG_PATH,
      env: ENV,
      home: ENV.fetch("HOME"),
      out: $stdout,
      err: $stderr,
      release_fetcher: nil,
      downloader: nil,
      command_runner: nil
    )
      @config_path = config_path
      @env = env
      @home = home
      @out = out
      @err = err
      @release_fetcher = release_fetcher || method(:fetch_release)
      @downloader = downloader || method(:download)
      @command_runner = command_runner || method(:run_command)
    end

    def metadata
      @metadata ||= load_metadata
    end

    def target_path
      env.fetch("DOTFILES_SFW_BIN", File.join(home, ".local/bin/sfw"))
    end

    def expected_sha256
      metadata.fetch("sha256")
    end

    def actual_sha256(path = target_path)
      return nil unless File.file?(path)

      Digest::SHA256.file(path).hexdigest
    end

    def matching?(path = target_path)
      actual_sha256(path) == expected_sha256
    end

    def verify(path = target_path)
      actual = actual_sha256(path)
      out.puts "Socket Firewall binary verify"
      out.puts "  path:     #{path}"
      out.puts "  expected: #{expected_sha256}"
      out.puts "  actual:   #{actual || "<missing>"}"
      raise Error, "sfw binary is missing: #{path}" unless actual
      raise Error, "sfw binary SHA256 mismatch: #{path}" unless actual == expected_sha256

      out.puts "  status:   ok"
      true
    end

    def status
      actual = actual_sha256
      signing = File.file?(target_path) ? signing_status(target_path) : "missing"
      {
        "path" => target_path,
        "expected_sha256" => expected_sha256,
        "actual_sha256" => actual || "<missing>",
        "hash_status" => actual == expected_sha256 ? "ok" : "mismatch",
        "executable_status" => executable_status(target_path),
        "signing_status" => signing,
        "quarantine_status" => quarantine_status(target_path)
      }
    end

    def install(dry_run: false)
      if matching?
        repair_matching_target(dry_run: dry_run)
        return true
      end

      if dry_run
        out.puts "Socket Firewall binary: would install #{metadata.fetch("asset")} to #{target_path}"
        return true
      end

      verify_release_metadata!
      source = valid_seed_path || download_asset
      install_source(source)
      true
    end

    private

    def load_metadata
      data = YAML.safe_load(File.read(config_path), permitted_classes: [], permitted_symbols: [], aliases: false)
      validate_metadata!(data)
      data
    rescue Errno::ENOENT
      raise Error, "SFW metadata not found: #{config_path}"
    end

    def validate_metadata!(data)
      required = %w[version asset url sha256 size github_digest upstream_repo release_api_url license]
      missing = required.select { |key| !data.is_a?(Hash) || data[key].nil? || data[key].to_s.empty? }
      raise Error, "SFW metadata missing required keys: #{missing.join(", ")}" unless missing.empty?
      raise Error, "SFW metadata sha256 must be lowercase SHA256" unless data.fetch("sha256").match?(SHA256_PATTERN)
      raise Error, "SFW metadata github_digest must match sha256" unless data.fetch("github_digest") == "#{DIGEST_PREFIX}#{data.fetch("sha256")}"
      raise Error, "SFW metadata size must be positive" unless data.fetch("size").is_a?(Integer) && data.fetch("size").positive?
      raise Error, "SFW metadata asset must be macOS arm64" unless data.fetch("asset") == "sfw-free-macos-arm64"
      raise Error, "SFW metadata URL must be HTTPS" unless data.fetch("url").start_with?("https://")
      raise Error, "SFW metadata release API URL must be HTTPS" unless data.fetch("release_api_url").start_with?("https://")
      raise Error, "SFW metadata license must be PolyForm Shield" unless data.fetch("license").fetch("name").include?("PolyForm Shield")
    end

    def verify_release_metadata!
      release = @release_fetcher.call(metadata.fetch("release_api_url"))
      raise Error, "SFW release metadata tag mismatch" unless release.fetch("tag_name") == metadata.fetch("version")

      asset = release.fetch("assets").find { |entry| entry.fetch("name") == metadata.fetch("asset") }
      raise Error, "SFW release metadata missing asset: #{metadata.fetch("asset")}" unless asset

      expected = {
        "browser_download_url" => metadata.fetch("url"),
        "size" => metadata.fetch("size"),
        "digest" => metadata.fetch("github_digest")
      }
      expected.each do |key, value|
        raise Error, "SFW release metadata #{key} mismatch" unless asset.fetch(key) == value
      end
    rescue KeyError => e
      raise Error, "SFW release metadata missing key: #{e.key}"
    end

    def seed_paths
      paths = []
      paths << env["DOTFILES_SFW_ASSET"] if env["DOTFILES_SFW_ASSET"] && !env["DOTFILES_SFW_ASSET"].empty?
      paths << File.join(home, "Downloads", metadata.fetch("asset"))
      paths << File.join(ROOT, ".dotfiles/cache/sfw", metadata.fetch("asset"))
      paths
    end

    def valid_seed_path
      seed_paths.each_with_index do |path, index|
        next unless File.file?(path)

        if valid_asset?(path)
          out.puts "Socket Firewall binary: using verified local asset #{path}"
          return path
        end

        raise Error, "DOTFILES_SFW_ASSET failed SFW verification: #{path}" if index.zero? && env["DOTFILES_SFW_ASSET"]

        out.puts "Socket Firewall binary: ignoring unverified local asset #{path}"
      end
      nil
    end

    def valid_asset?(path)
      File.size(path) == metadata.fetch("size") && actual_sha256(path) == expected_sha256
    end

    def download_asset
      cache_dir = File.join(ROOT, ".dotfiles/cache/sfw")
      FileUtils.mkdir_p(cache_dir)
      destination = File.join(cache_dir, metadata.fetch("asset"))
      tmp = "#{destination}.tmp"
      FileUtils.rm_f(tmp)
      out.puts "Socket Firewall binary: downloading #{metadata.fetch("url")}"
      @downloader.call(metadata.fetch("url"), tmp)
      raise Error, "downloaded SFW asset failed verification" unless valid_asset?(tmp)

      FileUtils.mv(tmp, destination)
      destination
    ensure
      FileUtils.rm_f(tmp) if tmp && File.exist?(tmp)
    end

    def install_source(source)
      FileUtils.mkdir_p(File.dirname(target_path))
      tmp = "#{target_path}.tmp"
      FileUtils.cp(source, tmp)
      FileUtils.chmod(0o755, tmp)
      raise Error, "installed SFW binary failed verification" unless matching?(tmp)
      verify_signature!(tmp)

      backup_existing_target
      FileUtils.mv(tmp, target_path)
      out.puts "Socket Firewall binary: installed #{target_path}"
    ensure
      FileUtils.rm_f(tmp) if tmp && File.exist?(tmp)
    end

    def repair_matching_target(dry_run:)
      if File.executable?(target_path)
        out.puts "Socket Firewall binary: already converged at #{target_path}"
        return
      end

      if dry_run
        out.puts "Socket Firewall binary: would repair executable mode on #{target_path}"
        return
      end

      FileUtils.chmod(0o755, target_path)
      verify_signature!(target_path)
      out.puts "Socket Firewall binary: repaired executable mode on #{target_path}"
    end

    def backup_existing_target
      return unless File.exist?(target_path) || File.symlink?(target_path)

      backup = Runtime.unique_path("#{target_path}.bak")
      FileUtils.mv(target_path, backup)
      out.puts "Socket Firewall binary: backed up existing target to #{backup}"
    end

    def verify_signature!(path)
      raise Error, "SFW binary signature verification failed" unless signing_status(path) == "valid"

      out.puts "Socket Firewall binary: signed binary verified; leaving quarantine attributes unchanged"
    end

    def signing_status(path)
      result = @command_runner.call(["/usr/bin/codesign", "--verify", "--strict", "--verbose=2", path])
      return "valid" if result.success?
      return "unavailable" if command_unavailable?(result, "/usr/bin/codesign")

      output = "#{result.stdout}\n#{result.stderr}"
      return "unsigned" if output.include?("code object is not signed") || output.include?("is not signed at all")

      "invalid"
    end

    def quarantine_status(path)
      return "missing" unless File.file?(path)

      result = @command_runner.call(["/usr/bin/xattr", "-p", "com.apple.quarantine", path])
      return "unavailable" if command_unavailable?(result, "/usr/bin/xattr")

      result.success? ? "present" : "absent"
    end

    def executable_status(path)
      return "missing" unless File.file?(path)

      File.executable?(path) ? "ok" : "not-executable"
    end

    def command_unavailable?(result, command)
      output = "#{result.stdout}\n#{result.stderr}"
      output.include?("command not found: #{command}")
    end

    def fetch_release(url)
      uri = URI(url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/vnd.github+json"
        request["User-Agent"] = "dotfiles-sfw-installer"
        http.request(request)
      end
      raise Error, "failed to fetch SFW release metadata: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise Error, "failed to parse SFW release metadata: #{e.message}"
    end

    def download(url, destination, limit = 5)
      raise Error, "too many redirects while downloading SFW binary" if limit.zero?

      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = "dotfiles-sfw-installer"
        http.request(request) do |response|
          case response
          when Net::HTTPSuccess
            File.open(destination, "wb") { |file| response.read_body { |chunk| file.write(chunk) } }
          when Net::HTTPRedirection
            return download(URI.join(url, response["location"]).to_s, destination, limit - 1)
          else
            raise Error, "failed to download SFW binary: HTTP #{response.code}"
          end
        end
      end
    end

    def run_command(command)
      stdout, stderr, status = Open3.capture3(*command)
      CommandResult.new(success: status.success?, stdout: stdout, stderr: stderr)
    rescue Errno::ENOENT
      CommandResult.new(success: false, stderr: "command not found: #{command.first}")
    end
  end
end
