# frozen_string_literal: true

require "open3"

require_relative "manifest"
require_relative "runtime"
require_relative "vscode"

module Dotfiles
  class Doctor
    REQUIRED_COMMANDS = %w[bash ruby bundle rg].freeze
    OPTIONAL_COMMANDS = %w[brew code eza git gpg ssh-add sqlite3].freeze
    TERMINAL_VSCODE_ACTIONS = %w[keep keep_auto_update warn].freeze
    SECRETIVE_SOCKET_TARGET = "~/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh"
    GIT_SIGNING_KEY_TARGET = "~/.config/git/secretive_git_key.pub"
    GIT_ALLOWED_SIGNERS_TARGET = "~/.config/git/allowed_signers"
    GIT_SECRETIVE_PROGRAM_INCLUDE_TARGET = "~/.config/git/secretive-program.gitconfig"
    GIT_SECRETIVE_PROGRAM_TARGET = "~/.local/bin/git-secretive-ssh-keygen"

    attr_reader :argv, :out, :err, :color

    def initialize(
      argv:,
      out: $stdout,
      err: $stderr,
      manifest: nil,
      vscode_manager: nil,
      state_dir: File.join(ROOT, ".dotfiles/state"),
      secretive_socket_path: nil,
      git_signing_key_path: nil,
      git_allowed_signers_path: nil,
      secretive_socket_checker: nil,
      color: true
    )
      @argv = argv.dup
      @out = out
      @err = err
      @manifest = manifest
      @vscode_manager = vscode_manager
      @state_dir = state_dir
      @secretive_socket_path = secretive_socket_path || expand_home(SECRETIVE_SOCKET_TARGET)
      @git_signing_key_path = git_signing_key_path || expand_home(GIT_SIGNING_KEY_TARGET)
      @git_allowed_signers_path = git_allowed_signers_path || expand_home(GIT_ALLOWED_SIGNERS_TARGET)
      @git_secretive_program_include_path = expand_home(GIT_SECRETIVE_PROGRAM_INCLUDE_TARGET)
      @git_secretive_program_path = expand_home(GIT_SECRETIVE_PROGRAM_TARGET)
      @secretive_socket_checker = secretive_socket_checker || ->(path) { File.socket?(path) }
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
      check_git_secretive
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

    def check_git_secretive
      section "🔐 Secretive Git SSH"
      socket_ok = check_secretive_socket
      key_ok = check_secretive_file("Git signing key", @git_signing_key_path)
      check_secretive_file("Git allowed signers", @git_allowed_signers_path)
      check_git_secretive_program_include
      check_secretive_agent_key if socket_ok && key_ok
    end

    def check_secretive_socket
      if @secretive_socket_checker.call(@secretive_socket_path)
        success "Secretive socket: #{value(@secretive_socket_path)}"
        true
      else
        warn "Secretive socket is missing: #{@secretive_socket_path}"
        false
      end
    end

    def check_secretive_file(label, path)
      if File.readable?(path)
        success "#{label}: #{value(path)}"
        true
      else
        warn "#{label} is missing or unreadable: #{path}"
        false
      end
    end

    def check_git_secretive_program_include
      if !File.readable?(@git_secretive_program_include_path)
        warn "Git Secretive signing helper include is missing: #{@git_secretive_program_include_path}"
      elsif File.read(@git_secretive_program_include_path) == git_secretive_program_include_content
        success "Git Secretive signing helper include: #{value(@git_secretive_program_include_path)}"
      else
        warn "Git Secretive signing helper include is stale; run script/install: #{@git_secretive_program_include_path}"
      end
    end

    def git_secretive_program_include_content
      <<~CONFIG
        # Generated by script/install. Git does not expand ~ for gpg.ssh.program.
        [gpg "ssh"]
        \tprogram = #{@git_secretive_program_path}
      CONFIG
    end

    def check_secretive_agent_key
      ok, stdout, stderr = secretive_agent_public_keys
      unless ok
        warn "Secretive agent keys could not be queried: #{first_error_line(stderr)}"
        return
      end

      key_body = public_key_body(File.readlines(@git_signing_key_path).find { |line| !line.strip.empty? && !line.start_with?("#") })
      if key_body.empty?
        warn "Git signing key file does not contain a public SSH key: #{@git_signing_key_path}"
      elsif stdout.lines.any? { |line| public_key_body(line) == key_body }
        success "Secretive agent exposes Git signing key"
      else
        warn "Secretive agent does not expose the configured Git signing key"
      end
    end

    def secretive_agent_public_keys
      stdout, stderr, status = Open3.capture3({ "SSH_AUTH_SOCK" => @secretive_socket_path }, "ssh-add", "-L")
      [status.success?, stdout, stderr]
    end

    def public_key_body(line)
      line.to_s.strip.split(/\s+/).first(2).join(" ")
    end

    def first_error_line(stderr)
      line = stderr.to_s.lines.first.to_s.strip
      line.empty? ? "ssh-add -L failed" : line
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

    def expand_home(path)
      path.sub(/\A~(?=\/|\z)/, ENV.fetch("HOME"))
    end
  end
end
