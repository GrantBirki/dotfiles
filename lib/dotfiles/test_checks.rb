# frozen_string_literal: true

require "bundler"
require "English"
require "json"
require "yaml"

require_relative "manifest"

module Dotfiles
  module TestChecks
    class Error < StandardError; end

    module JSONC
      module_function

      def validate_file(path)
        JSON.parse(strip(File.read(path)))
        true
      rescue JSON::ParserError => e
        raise Error, "#{path}: invalid JSON/JSONC: #{e.message}"
      rescue Errno::ENOENT
        raise Error, "#{path}: file not found"
      end

      def strip(text)
        out = +""
        in_string = false
        escape = false
        chars = text.each_char.to_a
        index = 0

        while index < chars.length
          char = chars[index]

          if in_string
            out << char
            if escape
              escape = false
            elsif char == "\\"
              escape = true
            elsif char == '"'
              in_string = false
            end
          elsif char == '"'
            in_string = true
            out << char
          elsif char == "/" && chars[index + 1] == "/"
            index += 2
            index += 1 while index < chars.length && chars[index] != "\n"
            out << "\n" if index < chars.length
          elsif char == "/" && chars[index + 1] == "*"
            index = consume_block_comment(chars, index, out)
          else
            out << char
          end

          index += 1
        end

        out.gsub(/,\s*([}\]])/, '\1')
      end

      def consume_block_comment(chars, index, out)
        index += 2
        closed = false
        while index < chars.length
          if chars[index] == "*" && chars[index + 1] == "/"
            index += 1
            closed = true
            break
          end
          out << "\n" if chars[index] == "\n"
          index += 1
        end
        raise Error, "unterminated block comment" unless closed

        index
      end
    end

    module YAMLCheck
      module_function

      def validate_file(path)
        YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false)
        true
      rescue Psych::Exception => e
        raise Error, "#{path}: invalid YAML: #{e.message}"
      rescue Errno::ENOENT
        raise Error, "#{path}: file not found"
      end
    end

    module BundlerSupplyChain
      module_function

      def validate(root)
        failures = []
        failures.concat(validate_config(root))
        lock_text = File.read(File.join(root, "Gemfile.lock"))
        failures.concat(validate_lockfile(lock_text, root))
        raise Error, failures.join("\n") unless failures.empty?

        true
      rescue Errno::ENOENT => e
        raise Error, e.message
      end

      def validate_config(root)
        config_path = File.join(root, ".bundle/config")
        config = YAML.safe_load(File.read(config_path), permitted_classes: [], permitted_symbols: [], aliases: false)
        return [] if config.fetch("BUNDLE_FROZEN", nil) == "true"

        [".bundle/config must set BUNDLE_FROZEN: \"true\""]
      end

      def validate_lockfile(lock_text, root)
        failures = []
        unless lock_text.match?(/\ACHECKSUMS\n|\nCHECKSUMS\n/)
          failures << "Gemfile.lock is missing CHECKSUMS"
        end

        checksum_entries, checksum_failures = checksum_entries(lock_text)
        failures.concat(checksum_failures)
        specs = Bundler::LockfileParser.new(lock_text).specs
        failures.concat(validate_spec_checksums(specs, checksum_entries))
        failures.concat(validate_cached_gems(specs, root))
        failures
      end

      def checksum_entries(lock_text)
        entries = {}
        failures = []
        in_checksums = false
        lock_text.each_line do |line|
          stripped = line.chomp
          if stripped == "CHECKSUMS"
            in_checksums = true
            next
          end
          next unless in_checksums
          break if stripped.match?(/\A[A-Z][A-Z ]*\z/)
          next if stripped.empty?

          match = stripped.match(/\A  (?<name>.+) \((?<version>[^)]+)\) sha256=(?<sha>[0-9a-f]{64})\z/)
          if match
            entries[[match[:name], match[:version]]] = match[:sha]
          else
            failures << "invalid Gemfile.lock checksum line: #{stripped}"
          end
        end
        [entries, failures]
      end

      def validate_spec_checksums(specs, checksum_entries)
        specs.filter_map do |spec|
          version = checksum_version(spec)
          next if checksum_entries.key?([spec.name, version])

          "missing checksum for #{spec.name} (#{version})"
        end
      end

      def checksum_version(spec)
        platform = spec.platform.to_s
        platform == "ruby" ? spec.version.to_s : "#{spec.version}-#{platform}"
      end

      def validate_cached_gems(specs, root)
        cache_dir = File.join(root, "vendor/cache")
        expected_cache = specs.map { |spec| "#{spec.full_name}.gem" }.sort
        actual_cache = Dir.exist?(cache_dir) ? Dir.children(cache_dir).grep(/\.gem\z/).sort : []
        failures = []
        (expected_cache - actual_cache).each { |gem| failures << "missing cached gem: vendor/cache/#{gem}" }
        (actual_cache - expected_cache).each { |gem| failures << "extra cached gem: vendor/cache/#{gem}" }
        failures
      end
    end

    module CIWorkflowActionPins
      module_function

      def validate(root)
        failures = []
        workflow_paths(root).each do |path|
          failures.concat(validate_file(root, path))
        end
        raise Error, failures.join("\n") unless failures.empty?

        true
      end

      def workflow_paths(root)
        Dir[File.join(root, ".github/workflows/*.{yml,yaml}")].sort
      end

      def validate_file(root, path)
        failures = []
        File.readlines(path).each_with_index do |line, index|
          match = line.match(/\buses:\s*['"]?(?<uses>[^'"\s#]+)['"]?/)
          next unless match

          value = match[:uses]
          next if value.start_with?("./")
          next if pinned_action_ref?(value)

          relative = path.delete_prefix("#{root}/")
          failures << "#{relative}:#{index + 1} action is not SHA-pinned: #{value}"
        end
        failures
      end

      def pinned_action_ref?(value)
        if value.start_with?("docker://")
          value.match?(/@sha256:[0-9a-f]{64}\z/i)
        else
          value.match?(/@[0-9a-f]{40}\z/i)
        end
      end
    end

    module VSCodeFixturePlan
      module_function

      def validate(json)
        plan = JSON.parse(json).fetch("actions")
        assertions.each do |message, assertion|
          raise Error, message unless assertion.call(plan)
        end
        true
      rescue JSON::ParserError => e
        raise Error, "fixture plan is invalid JSON: #{e.message}"
      rescue KeyError
        raise Error, "fixture plan is missing actions"
      end

      def assertions
        [
          ["fixture should update non-auto-update drift", ->(plan) { action_for(plan, "extension", "update", id: "donjayamanne.githistory") }],
          ["fixture should install missing baseline extension", ->(plan) { action_for(plan, "extension", "install", id: "hashicorp.terraform") }],
          ["fixture should keep auto-updated ChatGPT", ->(plan) { action_for(plan, "extension", "keep_auto_update", id: "openai.chatgpt") }],
          ["fixture should keep auto-updated Copilot Chat", ->(plan) { action_for(plan, "extension", "keep_auto_update", id: "github.copilot-chat") }],
          ["fixture should prune untracked extension", ->(plan) { action_for(plan, "extension", "prune", id: "untracked.publisher") }],
          ["fixture should configure selected auto-update allowlist", method(:valid_auto_update_allowlist?)],
          ["fixture should deny auto-update for tracked non-allowlisted extensions", method(:valid_auto_update_denylist?)],
          ["fixture should pin non-auto-update extensions in extensions.allowed", method(:valid_extensions_allowed_pin?)],
          ["fixture should allow only stable auto-update exceptions in extensions.allowed", method(:valid_extensions_allowed_stable?)],
        ]
      end

      def action_for(plan, type, action, id: nil, key: nil)
        plan.find do |entry|
          entry["type"] == type &&
            entry["action"] == action &&
            (id.nil? || entry["id"] == id) &&
            (key.nil? || entry["key"] == key)
        end
      end

      def valid_auto_update_allowlist?(plan)
        allowlist = action_for(plan, "storage", "configure", key: "extensions.autoUpdate")
        allowlist && allowlist.fetch("desired") == ["github.copilot-chat", "github.vscode-github-actions", "openai.chatgpt"]
      end

      def valid_auto_update_denylist?(plan)
        denylist = action_for(plan, "storage", "configure", key: "extensions.donotAutoUpdate")
        desired = denylist&.fetch("desired", nil)
        desired &&
          desired.include?("donjayamanne.githistory") &&
          !desired.include?("openai.chatgpt") &&
          !desired.include?("github.copilot-chat") &&
          !desired.include?("github.vscode-github-actions")
      end

      def extensions_allowed_action(plan)
        action_for(plan, "setting", "keep", key: "extensions.allowed") ||
          action_for(plan, "setting", "write", key: "extensions.allowed")
      end

      def valid_extensions_allowed_pin?(plan)
        allowed = extensions_allowed_action(plan)
        allowed && allowed.fetch("desired").fetch("donjayamanne.githistory") == ["0.6.20"]
      end

      def valid_extensions_allowed_stable?(plan)
        allowed = extensions_allowed_action(plan)
        allowed &&
          allowed.fetch("desired").fetch("openai.chatgpt") == "stable" &&
          allowed.fetch("desired").fetch("github.copilot-chat") == "stable" &&
          allowed.fetch("desired").fetch("github.vscode-github-actions") == "stable"
      end
    end

    module GitSecretivePolicy
      module_function

      EXPECTED_VALUES = {
        "core.sshcommand" => "~/.local/bin/git-secretive-ssh",
        "gpg.format" => "ssh",
        "gpg.ssh.allowedsignersfile" => "~/.config/git/allowed_signers",
        "include.path" => "~/.config/git/secretive-program.gitconfig",
        "user.signingkey" => "~/.config/git/secretive_git_key.pub"
      }.freeze
      REQUIRED_TRUE_VALUES = %w[commit.gpgsign tag.gpgsign tag.forcesignannotated].freeze
      CLASSIC_GPG_KEYS = %w[gpg.program gpg.openpgp.program].freeze
      GENERATED_LOCAL_KEYS = %w[gpg.ssh.program].freeze
      PRIVATE_KEY_PATH_PATTERN = %r{(^|/)(id_rsa|id_dsa|id_ecdsa|id_ed25519)(\z|[._-])}.freeze

      def validate(root)
        config_path = File.join(root, "dotfiles/.gitconfig")
        config = read_git_config(config_path)
        failures = []
        failures.concat(expected_value_failures(config))
        failures.concat(required_true_failures(config))
        failures.concat(classic_gpg_failures(config))
        failures.concat(generated_local_key_failures(config))
        failures.concat(signing_key_failures(config))
        raise Error, failures.join("\n") unless failures.empty?

        true
      rescue Errno::ENOENT
        raise Error, "dotfiles/.gitconfig not found"
      end

      def expected_value_failures(config)
        EXPECTED_VALUES.each_with_object([]) do |(key, expected), failures|
          actual = value_for(config, key)
          next if actual == expected

          failures << "dotfiles/.gitconfig must set #{key}=#{expected}; got #{actual.inspect}"
        end
      end

      def required_true_failures(config)
        REQUIRED_TRUE_VALUES.each_with_object([]) do |key, failures|
          next if truthy?(value_for(config, key))

          failures << "dotfiles/.gitconfig must enable #{key}"
        end
      end

      def classic_gpg_failures(config)
        CLASSIC_GPG_KEYS.each_with_object([]) do |key, failures|
          next unless config.key?(key)

          failures << "dotfiles/.gitconfig must not set classic GPG signing key #{key}"
        end
      end

      def generated_local_key_failures(config)
        GENERATED_LOCAL_KEYS.each_with_object([]) do |key, failures|
          next unless config.key?(key)

          failures << "dotfiles/.gitconfig must not set machine-local #{key}; script/install writes ~/.config/git/secretive-program.gitconfig"
        end
      end

      def signing_key_failures(config)
        signing_key = value_for(config, "user.signingkey")
        return [] unless private_key_path?(signing_key)

        ["dotfiles/.gitconfig user.signingkey must not point at a private SSH key path"]
      end

      def private_key_path?(value)
        return false if value.nil? || value.end_with?(".pub") || value.start_with?("key::") || value.start_with?("ssh-")

        value.match?(PRIVATE_KEY_PATH_PATTERN) || value.downcase.include?("private")
      end

      def truthy?(value)
        %w[true yes on 1].include?(value.to_s.downcase)
      end

      def value_for(config, key)
        config.fetch(key, []).last
      end

      def read_git_config(path)
        current_section = nil
        values = Hash.new { |hash, key| hash[key] = [] }
        File.readlines(path).each do |line|
          stripped = line.strip
          next if stripped.empty? || stripped.start_with?("#", ";")

          section = stripped.match(/\A\[(?<name>[^\]]+)\]\z/)
          if section
            current_section = normalize_section(section[:name])
            next
          end

          entry = stripped.match(/\A(?<key>[A-Za-z0-9_.-]+)\s*=\s*(?<value>.*?)\s*\z/)
          next unless current_section && entry

          values["#{current_section}.#{entry[:key].downcase}"] << entry[:value]
        end
        values
      end

      def normalize_section(name)
        match = name.match(/\A(?<section>[A-Za-z0-9_.-]+)\s+"(?<subsection>.*)"\z/)
        return "#{match[:section]}.#{match[:subsection]}".downcase if match

        name.downcase
      end
    end

    module PublicSafety
      module_function

      LOCAL_GIT_KEY_PATHS = %w[
        configs/git/secretive_git_key.pub
        configs/git/allowed_signers
      ].freeze
      SECRET_PATTERNS = [
        /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
        /AKIA[0-9A-Z]{16}/,
        /gh[pousr]_[A-Za-z0-9_]{36,}/,
        /xox[baprs]-[A-Za-z0-9-]{20,}/,
        /sk-[A-Za-z0-9]{32,}/,
        /(?:api[_-]?key|access[_-]?token|client[_-]?secret|refresh[_-]?token)\s*[:=]\s*["']?[A-Za-z0-9_\.\/+=-]{20,}/i
      ].freeze

      def validate(root, tracked_files: nil)
        tracked_files ||= git_tracked_files(root)
        failures = []
        failures.concat(blocked_vscode_paths(tracked_files))
        failures.concat(blocked_git_key_paths(tracked_files))
        failures.concat(sensitive_generated_paths(tracked_files))
        failures.concat(secret_pattern_failures(root, tracked_files))
        raise Error, failures.join("\n") unless failures.empty?

        true
      end

      def git_tracked_files(root)
        output = Dir.chdir(root) { `git ls-files` }
        raise Error, "git ls-files failed" unless $CHILD_STATUS.success?

        output.lines.map(&:strip)
      end

      def blocked_vscode_paths(tracked_files)
        tracked_files
          .grep(%r{\Aconfigs/vsc/(?!extensions\.yml\z|keybindings\.json\z|policy\.yml\z|settings\.json\z|tasks\.json\z|snippets/)})
          .map { |path| "unexpected tracked VS Code config surface: #{path}" }
      end

      def blocked_git_key_paths(tracked_files)
        tracked_files
          .select { |path| LOCAL_GIT_KEY_PATHS.include?(path) }
          .map { |path| "local Secretive Git key material must not be tracked: #{path}" }
      end

      def sensitive_generated_paths(tracked_files)
        tracked_files
          .grep(%r{(^|/)(globalStorage|workspaceStorage|History|CachedData|logs|state\.vscdb|storage\.json|machineid|argv\.json)(/|$)})
          .map { |path| "sensitive generated path is tracked: #{path}" }
      end

      def secret_pattern_failures(root, tracked_files)
        tracked_files.filter_map do |path|
          full_path = File.join(root, path)
          next unless File.file?(full_path)

          text = File.binread(full_path)
          next if text.include?("\x00")
          next unless SECRET_PATTERNS.any? { |pattern| text.match?(pattern) }

          "possible committed secret pattern in #{path}"
        end
      end
    end

    class CLI
      attr_reader :argv, :out, :err

      def initialize(argv:, out: $stdout, err: $stderr)
        @argv = argv.dup
        @out = out
        @err = err
      end

      def run
        command = argv.shift
        case command
        when "jsonc"
          require_args!(1)
          argv.each { |path| JSONC.validate_file(path) }
        when "yaml"
          require_args!(1)
          argv.each { |path| YAMLCheck.validate_file(path) }
        when "bundler-supply-chain"
          require_args!(1)
          BundlerSupplyChain.validate(argv.fetch(0))
        when "ci-workflow-action-pins"
          require_args!(1)
          CIWorkflowActionPins.validate(argv.fetch(0))
        when "vscode-fixture-plan"
          require_args!(1)
          VSCodeFixturePlan.validate(argv.fetch(0))
        when "git-secretive-policy"
          require_args!(1)
          GitSecretivePolicy.validate(argv.fetch(0))
        when "public-safety"
          require_args!(1)
          PublicSafety.validate(argv.fetch(0))
        when "--help", "-h"
          out.puts usage
        else
          err.puts usage
          return 2
        end
        0
      rescue Error => e
        err.puts e.message
        1
      end

      private

      def require_args!(count)
        return if argv.length >= count

        raise Error, "missing argument\n#{usage}"
      end

      def usage
        <<~USAGE.chomp
          Usage: script/test-check <command> [args]

          Commands:
            jsonc <path>...
            yaml <path>...
            bundler-supply-chain <repo-root>
            ci-workflow-action-pins <repo-root>
            vscode-fixture-plan <plan-json>
            git-secretive-policy <repo-root>
            public-safety <repo-root>
        USAGE
      end
    end
  end
end
