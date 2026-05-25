# frozen_string_literal: true

require "fileutils"
require_relative "manifest"
require_relative "runtime"
require_relative "sfw_binary"
require_relative "vscode"

module Dotfiles
  class Installer
    SHELL_ENTRY_IDS = %w[bashrc bash-aliases bash-logout profile].freeze
    TERMINAL_VSCODE_ACTIONS = %w[keep keep_auto_update warn].freeze
    DEFAULT_DIRECTORIES = [".cargo", ".local/bin"].freeze
    GIT_SECRETIVE_PROGRAM_INCLUDE_TARGET = ".config/git/secretive-program.gitconfig"
    GIT_SECRETIVE_PROGRAM_TARGET = ".local/bin/git-secretive-ssh-keygen"

    attr_reader :argv, :home, :out, :err, :platform, :color

    def initialize(
      argv:,
      home: ENV.fetch("HOME"),
      out: $stdout,
      err: $stderr,
      platform: RUBY_PLATFORM,
      manifest: nil,
      sfw_binary: nil,
      vscode_manager: nil,
      state_dir: File.join(ROOT, ".dotfiles/state"),
      default_directories: DEFAULT_DIRECTORIES,
      color: true
    )
      @argv = argv.dup
      @home = home
      @out = out
      @err = err
      @platform = platform
      @manifest = manifest
      @sfw_binary = sfw_binary
      @vscode_manager = vscode_manager
      @state_dir = state_dir
      @default_directories = default_directories
      @color = color
      @dry_run = false
      @install_vscode_extensions = true
      @install_sfw_binary = env_sfw_install_enabled?
      @dir_changes = 0
      @manifest_ok = 0
      @manifest_changes = 0
      @manifest_skipped = 0
      @shell_changed = false
      @manifest_details = []
      @state_rows = []
    end

    def run
      parse_args!
      unless Runtime.darwin?(platform)
        err.puts "This dotfiles installer only supports macOS."
        return 1
      end

      section "🚀 dotfiles install"
      manifest.validate!
      success "Install manifest is valid"
      warn_msg "Dry run: no filesystem changes will be made" if dry_run?

      ensure_default_directories
      section "📁 Managed files"
      install_manifest_entries
      print_manifest_summary
      section "🛡️ Socket Firewall"
      install_sfw_binary
      section "🔐 Git"
      install_git_secretive_program_include
      write_state_file unless dry_run?

      section "🧩 VS Code"
      reconcile_vscode

      info "Existing shells may need: source ~/.bashrc" if !dry_run? && @shell_changed
      out.puts "\n✅ Done"
      0
    rescue Error, VSCode::Error => e
      err.puts e.message
      1
    end

    private

    def dry_run?
      @dry_run
    end

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
        when "--dry-run", "-n"
          @dry_run = true
        when "--skip-vscode-extensions"
          @install_vscode_extensions = false
        when "--skip-sfw-binary"
          @install_sfw_binary = false
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
        Usage: script/install [--dry-run] [--skip-vscode-extensions] [--skip-sfw-binary]

        Install managed dotfiles, reconcile the Socket Firewall binary, and reconcile the VS Code extension manifest.
      USAGE
    end

    def env_sfw_install_enabled?
      ENV.fetch("DOTFILES_SKIP_SFW_BINARY", "0") != "1"
    end

    def sfw_binary
      @sfw_binary ||= SFWBinary.new(home: home, out: out, err: err)
    end

    def ensure_default_directories
      @default_directories.each do |relative_dir|
        path = File.join(home, relative_dir)
        next if Dir.exist?(path)

        @dir_changes += 1
        if dry_run?
          detail "would create directory: #{path}"
        else
          FileUtils.mkdir_p(path)
          detail "created directory: #{path}"
        end
      end
    end

    def install_manifest_entries
      manifest.entries.select(&:active?).each do |entry|
        install_entry(entry)
      end
    end

    def install_entry(entry)
      if entry.parent == "require" && !Dir.exist?(entry.target_parent)
        @manifest_skipped += 1
        warn_msg "Skipping #{entry.id} because parent directory is missing: #{entry.target_parent}"
        record_state(entry, "", "skipped-parent")
        return
      end

      ensure_parent(entry)
      if already_converged?(entry)
        @manifest_ok += 1
        record_state(entry, "", entry.mode == "symlink" ? "already-linked" : "already-copied")
        return
      end

      @manifest_changes += 1
      @shell_changed = true if SHELL_ENTRY_IDS.include?(entry.id)
      backup_path = backup_current_target(entry)
      install_target(entry)
      record_state(entry, backup_path, entry.mode == "symlink" ? "linked" : "copied")
    end

    def ensure_parent(entry)
      return unless entry.parent == "create"
      return if Dir.exist?(entry.target_parent)

      @dir_changes += 1
      if dry_run?
        detail "would create parent directory for #{entry.id}: #{entry.target_parent}"
      else
        FileUtils.mkdir_p(entry.target_parent)
        detail "created parent directory for #{entry.id}: #{entry.target_parent}"
      end
    end

    def already_converged?(entry)
      case entry.mode
      when "symlink"
        File.symlink?(entry.target_path) && File.readlink(entry.target_path) == entry.source_path
      when "copy"
        entry.target_matches?
      else
        raise Error, "Unsupported install mode for #{entry.id}: #{entry.mode}"
      end
    end

    def backup_current_target(entry)
      return "" unless File.exist?(entry.target_path) || File.symlink?(entry.target_path)

      backup_path = Runtime.unique_path(entry.backup_path)
      if dry_run?
        detail "would back up #{entry.id}: #{entry.target_path} -> #{backup_path}"
      else
        FileUtils.mkdir_p(File.dirname(backup_path))
        FileUtils.mv(entry.target_path, backup_path)
        detail "backed up #{entry.id}: #{entry.target_path} -> #{backup_path}"
      end
      backup_path
    end

    def install_target(entry)
      if dry_run?
        detail(entry.mode == "symlink" ? "would link #{entry.id}: #{entry.target_path} -> #{entry.source_path}" : "would copy #{entry.id}: #{entry.source_path} -> #{entry.target_path}")
      elsif entry.mode == "symlink"
        FileUtils.ln_s(entry.source_path, entry.target_path)
        detail "linked #{entry.id}: #{entry.target_path} -> #{entry.source_path}"
      else
        FileUtils.cp(entry.source_path, entry.target_path)
        detail "copied #{entry.id}: #{entry.source_path} -> #{entry.target_path}"
      end
    end

    def record_state(entry, backup_path, action)
      return if dry_run?

      @state_rows << [entry.id, entry.source_path, entry.target_path, backup_path, action]
    end

    def write_state_file
      FileUtils.mkdir_p(@state_dir)
      state_file = Runtime.unique_path(File.join(@state_dir, "install-#{Runtime.timestamp}.tsv"))
      tmp = "#{state_file}.tmp"
      File.open(tmp, "w") do |file|
        file.puts "id\tsource_path\ttarget_path\tbackup_path\taction"
        @state_rows.each { |row| file.puts row.join("\t") }
      end
      FileUtils.mv(tmp, state_file)
      success "Install state: #{value(state_file)}"
    ensure
      FileUtils.rm_f(tmp) if tmp && File.exist?(tmp)
    end

    def print_manifest_summary
      if @manifest_changes.zero? && @dir_changes.zero? && @manifest_skipped.zero?
        success "Managed files: #{value(@manifest_ok)} already converged"
      else
        success "Managed files: #{value(@manifest_changes)} file change(s), #{value(@dir_changes)} directory change(s), #{value(@manifest_ok)} already converged"
        @manifest_details.each { |line| out.puts "   #{line}" }
      end
    end

    def install_git_secretive_program_include
      path = File.join(home, GIT_SECRETIVE_PROGRAM_INCLUDE_TARGET)
      content = git_secretive_program_include_content
      if File.exist?(path) && File.read(path) == content
        success "Git Secretive signing helper include: already converged"
        return
      end

      if dry_run?
        info "Git Secretive signing helper include: would write #{path}"
      else
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
        success "Git Secretive signing helper include: wrote #{path}"
      end
    end

    def install_sfw_binary
      unless @install_sfw_binary
        info "Socket Firewall binary: skipped"
        return
      end

      sfw_binary.install(dry_run: dry_run?)
    end

    def git_secretive_program_include_content
      helper_path = File.join(home, GIT_SECRETIVE_PROGRAM_TARGET)
      <<~CONFIG
        # Generated by script/install. Git does not expand ~ for gpg.ssh.program.
        [gpg "ssh"]
        \tprogram = #{helper_path}
      CONFIG
    end

    def reconcile_vscode
      unless @install_vscode_extensions
        info "VS Code: skipped"
        return
      end

      actions = vscode_manager.actions
      summarize_vscode_plan(actions, dry_run? ? "dry-run" : "apply")
      vscode_manager.apply if !dry_run? && actionable_vscode_actions(actions).any?
    end

    def summarize_vscode_plan(actions, mode)
      actionable = actionable_vscode_actions(actions)
      warnings = actions.select { |action| action.fetch("action") == "warn" }

      if actionable.empty?
        success "VS Code: already converged"
      else
        verb = mode == "dry-run" ? "would apply" : "applying"
        out.puts "🔧 VS Code: #{verb} #{value(actionable.length)} change(s)"
        actionable.group_by { |action| [action.fetch("type"), action.fetch("action")] }.keys.sort.each do |type, action|
          count = actionable.count { |item| item.fetch("type") == type && item.fetch("action") == action }
          out.puts "   #{type} #{action}: #{value(count)}"
        end
      end

      warnings.each { |action| warn_msg "VS Code: #{action.fetch("message")}" }
    end

    def actionable_vscode_actions(actions)
      actions.reject { |action| TERMINAL_VSCODE_ACTIONS.include?(action.fetch("action")) }
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

    def warn_msg(text)
      out.puts "⚠️  #{text}"
    end

    def detail(text)
      @manifest_details << text
    end

    def value(text)
      Runtime.value(text, color: color)
    end
  end
end
