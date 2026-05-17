# frozen_string_literal: true

require_relative "manifest"
require_relative "runtime"
require_relative "vscode"

module Dotfiles
  class Doctor
    REQUIRED_COMMANDS = %w[bash ruby bundle rg].freeze
    OPTIONAL_COMMANDS = %w[brew code eza git gpg sqlite3].freeze
    TERMINAL_VSCODE_ACTIONS = %w[keep keep_auto_update warn].freeze

    attr_reader :argv, :out, :err, :color

    def initialize(
      argv:,
      out: $stdout,
      err: $stderr,
      manifest: nil,
      vscode_manager: nil,
      state_dir: File.join(ROOT, ".dotfiles/state"),
      color: true
    )
      @argv = argv.dup
      @out = out
      @err = err
      @manifest = manifest
      @vscode_manager = vscode_manager
      @state_dir = state_dir
      @color = color
      @issues = 0
      @warnings = 0
      @required_ok = 0
      @optional_ok = 0
      @managed_ok = 0
      @manifest_ok = false
      @vscode_manifest_ok = false
      @vscode_state_ok = false
      @latest_state = nil
    end

    def run
      parse_args!
      section "🩺 dotfiles doctor"
      check_commands
      check_manifest
      check_vscode
      check_latest_state
      print_summary
      @issues.zero? ? 0 : 1
    end

    private

    def manifest
      @manifest ||= Manifest.load
    end

    def vscode_manager
      @vscode_manager ||= VSCode::Manager.new
    end

    def parse_args!
      until argv.empty?
        arg = argv.shift
        case arg
        when "--production"
          next
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
        Usage: script/doctor

        Check local dotfiles install health.
      USAGE
    end

    def check_commands
      REQUIRED_COMMANDS.each { |command| check_command(command, required: true) }
      OPTIONAL_COMMANDS.each { |command| check_command(command, required: false) }
    end

    def check_command(command, required:)
      if Runtime.command?(command)
        required ? @required_ok += 1 : @optional_ok += 1
      elsif required
        issue "required command missing: #{command}"
      else
        warn "optional command missing: #{command}"
      end
    end

    def check_manifest
      manifest.validate!
      @manifest_ok = true
      manifest.entries.select(&:active?).each { |entry| check_entry(entry) }
    rescue Error => e
      issue "install manifest validation failed"
      issue e.message
    end

    def check_entry(entry)
      issue "#{entry.id} source is missing: #{entry.source_path}" unless File.exist?(entry.source_path)

      if entry.parent == "require" && !Dir.exist?(entry.target_parent)
        warn "#{entry.id} parent directory is missing: #{entry.target_parent}"
        return
      end

      if !File.exist?(entry.target_path) && !File.symlink?(entry.target_path)
        issue "#{entry.id} target is not installed: #{entry.target_path}"
        return
      end

      case entry.mode
      when "symlink"
        check_symlink_entry(entry)
      when "copy"
        check_copy_entry(entry)
      else
        issue "#{entry.id} target has unsupported mode: #{entry.mode}"
      end
    end

    def check_symlink_entry(entry)
      unless File.symlink?(entry.target_path)
        issue "#{entry.id} target exists but is not a symlink: #{entry.target_path}"
        return
      end

      if File.readlink(entry.target_path) == entry.source_path
        @managed_ok += 1
      else
        issue "#{entry.id} target symlink points elsewhere: #{entry.target_path}"
      end
    end

    def check_copy_entry(entry)
      if entry.target_matches?
        @managed_ok += 1
      else
        issue "#{entry.id} target differs from repo source: #{entry.target_path}"
      end
    end

    def check_vscode
      vscode_manager.validate!
      @vscode_manifest_ok = true
      actions = vscode_manager.doctor_actions
      if actions.any? { |action| !TERMINAL_VSCODE_ACTIONS.include?(action.fetch("action")) }
        issue "VS Code desired state has pending changes; run script/install --dry-run"
      else
        @vscode_state_ok = true
      end
    rescue VSCode::Error => e
      issue "VS Code manifest validation failed"
      issue e.message
    end

    def check_latest_state
      @latest_state = Dir[File.join(@state_dir, "install-*.tsv")].sort.last
      warn "no install state found under #{@state_dir}" unless @latest_state
    end

    def print_summary
      success "Commands: #{value("#{@required_ok}/#{REQUIRED_COMMANDS.length}")} required, #{value("#{@optional_ok}/#{OPTIONAL_COMMANDS.length}")} optional available"
      success "Manifest: valid" if @manifest_ok
      success "Managed files: #{value(@managed_ok)} OK"
      print_vscode_summary
      info "Latest install state: #{value(@latest_state)}" if @latest_state

      if @issues.positive?
        err.puts "\n❌ Doctor found #{bad_value(@issues)} issue(s) and #{warn_value(@warnings)} warning(s)."
      else
        out.print "\n✅ Doctor found no blocking issues"
        out.print " (#{warn_value(@warnings)} warning(s))" if @warnings.positive?
        out.puts "."
      end
    end

    def print_vscode_summary
      if @vscode_manifest_ok && @vscode_state_ok
        success "VS Code: manifests valid and desired state converged"
      elsif @vscode_manifest_ok
        success "VS Code: manifests valid"
      end
    end

    def section(text)
      out.puts "\n#{text}"
    end

    def success(text)
      out.puts "✅ #{text}"
    end

    def info(text)
      out.puts "ℹ️  #{text}"
    end

    def warn(message)
      @warnings += 1
      err.puts "⚠️  #{message}"
    end

    def issue(message)
      @issues += 1
      err.puts "❌ #{message}"
    end

    def value(text)
      Runtime.value(text, color: color)
    end

    def bad_value(text)
      Runtime.bad_value(text, color: color)
    end

    def warn_value(text)
      Runtime.warn_value(text, color: color)
    end
  end
end
