# frozen_string_literal: true

require "shellwords"

require_relative "manifest"
require_relative "sfw_binary"

module Dotfiles
  class SocketFirewall
    PACKAGE_MANAGERS = %w[npm yarn pnpm pip uv cargo].freeze
    STATUS_COMMANDS = (["sfw"] + PACKAGE_MANAGERS).freeze
    CACHE_COMMANDS = [
      { label: "npm", command: %w[npm cache clean --force] },
      { label: "yarn v1", command: %w[yarn cache clean] },
      { label: "yarn v2+", command: %w[yarn cache clean --mirror] },
      { label: "pnpm", command: %w[pnpm store prune] },
      { label: "pip", command: %w[pip cache purge] },
      { label: "uv", command: %w[uv cache clean] }
    ].freeze
    DEFAULT_RUNNER = ->(env, *command, chdir:) { system(env, *command, chdir: chdir) }

    attr_reader :argv, :out, :err, :env, :home, :root

    def initialize(argv:, out: $stdout, err: $stderr, runner: DEFAULT_RUNNER, env: ENV, home: ENV.fetch("HOME"), root: ROOT, sfw_binary: nil)
      @argv = argv.dup
      @out = out
      @err = err
      @runner = runner
      @env = env
      @home = home
      @root = root
      @sfw_binary = sfw_binary
      @command = "status"
      @dry_run = false
      @verify_path = nil
    end

    def run
      parse_args!
      case @command
      when "install"
        install
      when "verify"
        verify
      when "doctor"
        doctor
      when "cache-clean"
        cache_clean
      when "codex-config"
        print_codex_config
      when "status"
        status
      else
        err.puts usage
        2
      end
    rescue Error => e
      err.puts e.message
      1
    end

    def shim_dir
      env.fetch("DOTFILES_SFW_SHIM_DIR", File.join(home, ".local/share/dotfiles/sfw-shims"))
    end

    def sfw_bin
      env.fetch("DOTFILES_SFW_BIN", File.join(home, ".local/bin/sfw"))
    end

    def path_without_shims(path = env.fetch("PATH", ""))
      path.split(File::PATH_SEPARATOR).reject { |entry| entry.empty? || entry == shim_dir }.join(File::PATH_SEPARATOR)
    end

    def protected_path(path = env.fetch("PATH", ""))
      ([shim_dir] + path_without_shims(path).split(File::PATH_SEPARATOR).reject(&:empty?)).join(File::PATH_SEPARATOR)
    end

    def resolve_command(command, path:)
      path.split(File::PATH_SEPARATOR).each do |dir|
        candidate = File.join(dir, command)
        return candidate if File.file?(candidate) && File.executable?(candidate)
      end
      nil
    end

    def status_data
      protected = protected_path
      unprotected = path_without_shims
      {
        "shim_dir" => shim_dir,
        "sfw_bin" => sfw_bin,
        "require" => env.fetch("DOTFILES_SFW_REQUIRE", "1"),
        "disabled" => env.fetch("DOTFILES_SFW_DISABLE", "0"),
        "protected_path" => protected,
        "binary" => sfw_binary.status,
        "commands" => STATUS_COMMANDS.map do |command|
          {
            "name" => command,
            "protected" => resolve_command(command, path: protected) || "<missing>",
            "unprotected" => resolve_command(command, path: unprotected) || "<missing>"
          }
        end
      }
    end

    def format_status(data)
      lines = [
        "Socket Firewall status",
        "  shim dir:     #{data.fetch("shim_dir")}",
        "  binary:       #{data.fetch("sfw_bin")}",
        "  binary hash:  #{data.fetch("binary").fetch("hash_status")}",
        "  executable:   #{data.fetch("binary").fetch("executable_status")}",
        "  signing:      #{data.fetch("binary").fetch("signing_status")}",
        "  quarantine:   #{data.fetch("binary").fetch("quarantine_status")}",
        "  require mode: #{data.fetch("require")}",
        "  disabled:     #{data.fetch("disabled")}",
        ""
      ]
      data.fetch("commands").each do |row|
        lines << format("%-6<name>s protected:   %<protected>s", row.transform_keys(&:to_sym))
        lines << format("%-6<name>s unprotected: %<unprotected>s", row.transform_keys(&:to_sym))
      end
      "#{lines.join("\n")}\n"
    end

    def codex_config
      <<~TOML
        [shell_environment_policy]
        inherit = "all"

        [shell_environment_policy.set]
        DOTFILES_SFW_REQUIRE = #{toml_string(env.fetch("DOTFILES_SFW_REQUIRE", "1"))}
        DOTFILES_SFW_SHIM_DIR = #{toml_string(shim_dir)}
        DOTFILES_SFW_BIN = #{toml_string(sfw_bin)}
        PATH = #{toml_string(protected_path)}
      TOML
    end

    private

    def parse_args!
      @command = argv.shift if argv.first && !argv.first.start_with?("-")
      @verify_path = argv.shift if @command == "verify" && argv.first && !argv.first.start_with?("-")
      until argv.empty?
        arg = argv.shift
        case arg
        when "--dry-run", "-n"
          @dry_run = true
        when "--help", "-h"
          out.print usage
          raise SystemExit, 0
        else
          raise Error, "Unknown option: #{arg}\n#{usage}"
        end
      end
    end

    def usage
      <<~USAGE
        Usage: script/socket-firewall [status|doctor|install|verify|cache-clean|codex-config] [--dry-run]
      USAGE
    end

    def install
      out.puts "Socket Firewall install"
      sfw_binary.install(dry_run: @dry_run)
      0
    end

    def verify
      sfw_binary.verify(@verify_path || sfw_bin)
      0
    end

    def doctor
      data = status_data
      out.print format_status(data)
      return 0 unless env.fetch("DOTFILES_SFW_REQUIRE", "1") == "1" && !managed_binary_ready?(data.fetch("binary"))

      err.puts "sfw is required but the managed binary is unavailable, mismatched, or not executable"
      1
    end

    def cache_clean
      out.puts "Socket Firewall cache clean"
      CACHE_COMMANDS.each do |entry|
        command = entry.fetch(:command)
        if command_available?(command.first)
          run_command({ "DOTFILES_SFW_DISABLE" => "1" }, command)
        else
          out.puts "skipping #{entry.fetch(:label)} cache clean; command not found: #{command.first}"
        end
      end
      out.puts "clearing cargo registry and git caches"
      run_command({}, ["rm", "-fr", File.join(cargo_home, "registry"), File.join(cargo_home, "git")])
      0
    end

    def print_codex_config
      out.print codex_config
      0
    end

    def status
      out.print format_status(status_data)
      0
    end

    def sfw_binary
      @sfw_binary ||= SFWBinary.new(env: env, home: home, out: out, err: err)
    end

    def managed_binary_ready?(binary)
      binary.fetch("hash_status") == "ok" && binary.fetch("executable_status") == "ok"
    end

    def command_available?(command)
      !resolve_command(command, path: path_without_shims).nil?
    end

    def cargo_home
      configured = env.fetch("CARGO_HOME", "").to_s
      candidate = configured.empty? ? File.join(home, ".cargo") : configured

      unless candidate.start_with?(File::SEPARATOR)
        raise Error, "refusing to clear cargo cache with non-absolute CARGO_HOME: #{candidate}"
      end

      expanded = File.expand_path(candidate)
      if expanded == File::SEPARATOR
        raise Error, "refusing to clear cargo cache with unsafe CARGO_HOME: #{expanded}"
      end

      expanded
    end

    def run_command(command_env, command)
      if @dry_run
        out.puts "would run: #{command_display(command_env, command)}"
        return true
      end

      return true if @runner.call(command_env, *command, chdir: root)

      raise Error, "command failed: #{command_display(command_env, command)}"
    end

    def command_display(command_env, command)
      env_prefix = command_env.map { |key, value| "#{key}=#{Shellwords.escape(value)}" }
      (env_prefix + command.map(&:shellescape)).join(" ")
    end

    def toml_string(value)
      escaped = value.to_s.gsub("\\") { "\\\\" }.gsub("\"") { "\\\"" }
      "\"#{escaped}\""
    end
  end
end
