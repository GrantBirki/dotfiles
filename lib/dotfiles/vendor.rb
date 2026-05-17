# frozen_string_literal: true

require "cgi"
require "json"
require "net/http"
require "time"
require "uri"
require "yaml"

require_relative "manifest"

module Dotfiles
  LockedGem = Struct.new(:name, :version, keyword_init: true)

  class DependabotCooldownPolicy
    attr_reader :days, :source_path

    def self.from_dependabot(path)
      data = YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false)
      updates = Array(data.fetch("updates"))
      update = updates.find { |entry| entry["package-ecosystem"] == "bundler" && entry["directory"] == "/" } ||
        updates.find { |entry| entry["package-ecosystem"] == "bundler" }
      raise Error, "dependabot config has no bundler update entry" unless update

      days = update.fetch("cooldown", {}).fetch("default-days", nil)
      unless days.is_a?(Integer) && days.positive?
        raise Error, "dependabot bundler cooldown.default-days must be a positive integer"
      end

      new(days: days, source_path: path)
    rescue Errno::ENOENT
      raise Error, "dependabot config not found: #{path}"
    rescue KeyError
      raise Error, "dependabot config is missing required updates list"
    rescue Psych::Exception => e
      raise Error, "dependabot config is invalid YAML: #{e.message}"
    end

    def initialize(days:, source_path:)
      @days = days
      @source_path = source_path
    end
  end

  class LockfileSpecs
    def self.parse(text)
      specs = []
      in_gem_section = false
      in_specs = false

      text.each_line do |line|
        if line == "GEM\n"
          in_gem_section = true
          next
        end

        if in_gem_section && line == "  specs:\n"
          in_specs = true
          next
        end

        if in_specs
          break unless line.start_with?("    ")

          match = line.match(/\A    (?<name>\S+) \((?<version>[^)]+)\)/)
          specs << LockedGem.new(name: match[:name], version: match[:version]) if match
        elsif line.match?(/\A[A-Z]/)
          in_gem_section = false
        end
      end

      specs.uniq.sort_by { |spec| [spec.name, spec.version] }
    end
  end

  class RubyGemsClient
    USER_AGENT = "GrantBirki/dotfiles script/vendor"

    def initialize(fetcher: nil)
      @fetcher = fetcher || method(:http_get)
    end

    def versions(name)
      body = @fetcher.call(versions_uri(name))
      data = JSON.parse(body)
      raise Error, "RubyGems metadata for #{name} was not a JSON array" unless data.is_a?(Array)

      data
    rescue JSON::ParserError => e
      raise Error, "RubyGems metadata for #{name} was invalid JSON: #{e.message}"
    end

    private

    def versions_uri(name)
      URI("https://rubygems.org/api/v1/versions/#{CGI.escape(name)}.json")
    end

    def http_get(uri)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 10) do |http|
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = USER_AGENT
        response = http.request(request)
        code = response.code.to_i
        raise Error, "RubyGems metadata request failed for #{uri}: HTTP #{response.code}" unless code.between?(200, 299)

        response.body.to_s
      end
    end
  end

  class ReleaseCooldownError < Error; end

  class RubyGemsCooldown
    SECONDS_PER_DAY = 86_400

    def initialize(policy:, client:, clock:)
      @policy = policy
      @client = client
      @clock = clock
    end

    def validate!(locked_gems)
      raise Error, "Gemfile.lock has no RubyGems specs to validate" if locked_gems.empty?

      too_new = locked_gems.filter_map do |locked_gem|
        version = metadata_for(locked_gem)
        created_at = parse_created_at(version.fetch("created_at", nil), locked_gem)
        next unless created_at > cutoff_time

        [locked_gem, created_at]
      end
      return true if too_new.empty?

      raise ReleaseCooldownError, cooldown_message(too_new)
    end

    private

    def metadata_for(locked_gem)
      metadata = @client.versions(locked_gem.name).find do |version|
        version_number = version.fetch("number", "").to_s
        platform = version.fetch("platform", "ruby").to_s
        locked_gem.version == version_number ||
          locked_gem.version == "#{version_number}-#{platform}"
      end
      return metadata if metadata

      raise Error, "RubyGems metadata did not include #{locked_gem.name} #{locked_gem.version}"
    end

    def parse_created_at(value, locked_gem)
      Time.iso8601(value.to_s).utc
    rescue ArgumentError
      raise Error, "RubyGems metadata for #{locked_gem.name} #{locked_gem.version} has invalid created_at"
    end

    def cutoff_time
      @clock.call.utc - (@policy.days * SECONDS_PER_DAY)
    end

    def cooldown_message(too_new)
      lines = [
        "RubyGems cooldown rejected versions newer than #{@policy.days} days from #{relative_path(@policy.source_path)}:"
      ]
      too_new.each do |locked_gem, created_at|
        wait_until = created_at + (@policy.days * SECONDS_PER_DAY)
        lines << "- #{locked_gem.name} #{locked_gem.version} was published #{created_at.iso8601}; wait until #{wait_until.iso8601}"
      end
      lines.join("\n")
    end

    def relative_path(path)
      path.delete_prefix("#{ROOT}/")
    end
  end

  class Vendor
    DEPENDABOT_PATH = File.join(ROOT, ".github/dependabot.yml")
    LOCKFILE_PATH = File.join(ROOT, "Gemfile.lock")
    LOCK_COMMAND = ["bundle", "lock", "--add-checksums"].freeze
    CACHE_COMMAND = ["bundle", "cache", "--all", "--all-platforms", "--no-install"].freeze
    COMMANDS = [LOCK_COMMAND, CACHE_COMMAND].freeze

    attr_reader :argv, :out, :err

    def initialize(argv:, out: $stdout, err: $stderr, runner: nil, metadata_client: nil, clock: nil, dependabot_path: DEPENDABOT_PATH, lockfile_path: LOCKFILE_PATH)
      @argv = argv.dup
      @out = out
      @err = err
      @runner = runner || method(:system)
      @metadata_client = metadata_client || RubyGemsClient.new
      @clock = clock || Time.method(:now)
      @dependabot_path = dependabot_path
      @lockfile_path = lockfile_path
      @dry_run = false
    end

    def run
      original_lockfile = nil
      parse_args!
      policy = DependabotCooldownPolicy.from_dependabot(@dependabot_path)
      out.puts "📦 dotfiles vendor"
      out.puts "ℹ️  This is the intentional networked dependency refresh path." unless dry_run?
      out.puts "⚠️  Dry run: no commands will be executed." if dry_run?
      out.puts "🧊 RubyGems cooldown: #{policy.days} days from #{relative_path(policy.source_path)}"

      original_lockfile = read_lockfile unless dry_run?
      run_command(LOCK_COMMAND)
      enforce_cooldown(policy) unless dry_run?
      run_command(CACHE_COMMAND)
      out.puts "✅ Vendored Ruby dependencies are refreshed."
      0
    rescue ReleaseCooldownError => e
      restore_lockfile(original_lockfile)
      err.puts e.message
      err.puts "Gemfile.lock was restored to its pre-vendor state." if original_lockfile
      1
    rescue Error => e
      err.puts e.message
      1
    end

    private

    def dry_run?
      @dry_run
    end

    def parse_args!
      until argv.empty?
        arg = argv.shift
        case arg
        when "--dry-run", "-n"
          @dry_run = true
        when "--help", "-h"
          out.print usage
          raise SystemExit, 0
        else
          err.puts "Unknown option: #{arg}"
          err.print usage
          raise SystemExit, 2
        end
      end
    end

    def usage
      <<~USAGE
        Usage: script/vendor [--dry-run]

        Refresh vendored Ruby gems and Gemfile.lock checksums.
        RubyGems release age is enforced from .github/dependabot.yml.
      USAGE
    end

    def run_command(command)
      out.puts "→ #{command.join(" ")}"
      return if dry_run?

      ok = @runner.call({ "BUNDLE_FROZEN" => "false" }, *command, chdir: ROOT)
      raise Error, "command failed: #{command.join(" ")}" unless ok
    end

    def enforce_cooldown(policy)
      specs = LockfileSpecs.parse(read_lockfile)
      RubyGemsCooldown.new(policy: policy, client: @metadata_client, clock: @clock).validate!(specs)
      out.puts "✅ RubyGems cooldown satisfied for #{specs.length} locked gem(s)."
    end

    def read_lockfile
      File.read(@lockfile_path)
    rescue Errno::ENOENT
      raise Error, "Gemfile.lock not found: #{@lockfile_path}"
    end

    def restore_lockfile(text)
      File.write(@lockfile_path, text) if text
    end

    def relative_path(path)
      path.delete_prefix("#{ROOT}/")
    end
  end
end
