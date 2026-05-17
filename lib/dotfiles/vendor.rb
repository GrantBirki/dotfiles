# frozen_string_literal: true

require_relative "manifest"

module Dotfiles
  class Vendor
    COMMANDS = [
      ["bundle", "lock", "--add-checksums"],
      ["bundle", "cache", "--all", "--all-platforms", "--no-install"]
    ].freeze

    attr_reader :argv, :out, :err

    def initialize(argv:, out: $stdout, err: $stderr, runner: nil)
      @argv = argv.dup
      @out = out
      @err = err
      @runner = runner || method(:system)
      @dry_run = false
    end

    def run
      parse_args!
      out.puts "📦 dotfiles vendor"
      out.puts "ℹ️  This is the intentional networked dependency refresh path." unless dry_run?
      out.puts "⚠️  Dry run: no commands will be executed." if dry_run?

      COMMANDS.each { |command| run_command(command) }
      out.puts "✅ Vendored Ruby dependencies are refreshed."
      0
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
      USAGE
    end

    def run_command(command)
      out.puts "→ #{command.join(" ")}"
      return if dry_run?

      ok = @runner.call({ "BUNDLE_FROZEN" => "false" }, *command, chdir: ROOT)
      raise Error, "command failed: #{command.join(" ")}" unless ok
    end
  end
end
