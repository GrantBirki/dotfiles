# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "time"
require "yaml"
require_relative "runtime"

module Dotfiles
  module VSCode
    ROOT = File.expand_path("../..", __dir__)
    DEFAULT_EXTENSIONS_PATH = File.join(ROOT, "configs/vsc/extensions.yml")
    DEFAULT_POLICY_PATH = File.join(ROOT, "configs/vsc/policy.yml")
    DEFAULT_SETTINGS_PATH = File.join(ROOT, "configs/vsc/settings.json")
    SELECTED_AUTO_UPDATE_KEY = "extensions.autoUpdate"
    DISABLED_AUTO_UPDATE_KEY = "extensions.donotAutoUpdate"
    ANY_VERSION = "any"

    Extension = Struct.new(:id, :version, :auto_update, keyword_init: true) do
      def spec
        return id if any_version?

        "#{id}@#{version}"
      end

      def any_version?
        version == ANY_VERSION
      end
    end

    class Error < StandardError; end

    class Manager
      attr_reader :extensions_path, :policy_path, :settings_path, :user_dir,
                  :installed_extensions_file, :prune

      def initialize(
        extensions_path: DEFAULT_EXTENSIONS_PATH,
        policy_path: DEFAULT_POLICY_PATH,
        settings_path: DEFAULT_SETTINGS_PATH,
        user_dir: self.class.default_user_dir,
        installed_extensions_file: ENV["DOTFILES_VSCODE_INSTALLED_EXTENSIONS_FILE"],
        prune: true
      )
        @extensions_path = File.expand_path(extensions_path)
        @policy_path = File.expand_path(policy_path)
        @settings_path = File.expand_path(settings_path)
        @user_dir = File.expand_path(user_dir)
        @installed_extensions_file = installed_extensions_file
        @prune = prune
      end

      def self.default_user_dir
        File.join(ENV.fetch("HOME"), "Library/Application Support/Code/User")
      end

      def validate!(strict_settings: true)
        errors = schema_errors
        errors.concat(settings_drift_errors) if strict_settings && errors.empty?
        return true if errors.empty?

        raise Error, errors.join("\n")
      end

      def actions
        validate!(strict_settings: false)

        plan = []
        plan.concat(extension_actions)
        plan.concat(settings_actions)
        plan.concat(storage_actions)
        plan.concat(unmanaged_user_file_warnings)
        plan
      end

      def apply
        validate!(strict_settings: false)
        current_actions = actions

        apply_settings(current_actions)
        apply_extensions(current_actions)
        apply_storage(current_actions)

        remaining = actions.reject { |action| terminal_action?(action) }
        return true if remaining.empty?

        raise Error, "VS Code desired state still has pending actions after apply:\n#{format_actions(remaining)}"
      end

      def doctor_actions
        actions
      rescue Error => e
        [{ "type" => "issue", "action" => "error", "message" => e.message }]
      end

      def format_actions(plan_actions = actions)
        plan_actions.map { |action| format_action(action) }.join("\n")
      end

      def extensions
        @extensions ||= load_extensions
      end

      def policy
        @policy ||= load_policy
      end

      def desired_settings
        @desired_settings ||= begin
          desired = policy.fetch("settings").dup
          generated = policy.fetch("generated_settings", {})
          if generated.fetch("extensions.allowed", nil) == "extensions"
            desired["extensions.allowed"] = generated_allowed_extensions
          end
          desired
        end
      end

      private

      def generated_allowed_extensions
        extensions.to_h do |extension|
          allowed_value = extension.auto_update ? "stable" : [extension.version]
          [extension.id, allowed_value]
        end
      end

      def schema_errors
        errors = []
        extensions
        policy
      rescue Error => e
        errors << e.message
      ensure
        return errors
      end

      def settings_drift_errors
        settings_actions.map do |action|
          next unless action.fetch("action") == "write"

          "settings.json does not match policy for #{action.fetch("key")}: expected #{JSON.generate(action.fetch("desired"))}"
        end.compact
      end

      def load_extensions
        data = safe_load_yaml(extensions_path)
        extensions_data = data.fetch("extensions") do
          raise Error, "VS Code extension manifest is missing required `extensions` key"
        end
        raise Error, "VS Code extension manifest `extensions` must be an array" unless extensions_data.is_a?(Array)

        seen = {}
        extensions_data.each_with_index.map do |entry, index|
          validate_extension_entry!(entry, index, seen)
        end
      rescue Errno::ENOENT
        raise Error, "VS Code extension manifest not found: #{extensions_path}"
      end

      def validate_extension_entry!(entry, index, seen)
        raise Error, "extensions[#{index}] must be a mapping" unless entry.is_a?(Hash)

        allowed_keys = %w[id version auto_update]
        unknown_keys = entry.keys - allowed_keys
        raise Error, "extensions[#{index}] has unknown keys: #{unknown_keys.join(", ")}" unless unknown_keys.empty?

        id = entry["id"]
        version = entry["version"]
        auto_update = entry["auto_update"]

        unless id.is_a?(String) && id.match?(/\A[a-z0-9][a-z0-9_-]*\.[a-z0-9][a-z0-9_.-]*\z/)
          raise Error, "extensions[#{index}] has invalid id: #{id.inspect}"
        end

        unless version.is_a?(String) && version.match?(/\A[0-9A-Za-z][0-9A-Za-z._+-]*\z/)
          raise Error, "extensions[#{index}] has invalid version for #{id}: #{version.inspect}"
        end

        unless auto_update == true || auto_update == false
          raise Error, "extensions[#{index}] must set auto_update to true or false: #{id}"
        end

        if version == ANY_VERSION && auto_update != true
          raise Error, "extensions[#{index}] can use version `any` only when auto_update is true: #{id}"
        end

        if seen[id]
          raise Error, "duplicate VS Code extension id in manifest: #{id}"
        end

        seen[id] = true
        Extension.new(id: id, version: version, auto_update: auto_update)
      end

      def load_policy
        data = safe_load_yaml(policy_path)
        raise Error, "VS Code policy must be a mapping" unless data.is_a?(Hash)

        allowed_keys = %w[settings generated_settings selected_auto_update settings_sync unmanaged_user_files]
        unknown_keys = data.keys - allowed_keys
        raise Error, "VS Code policy has unknown keys: #{unknown_keys.join(", ")}" unless unknown_keys.empty?

        validate_policy!(data)
        data
      rescue Errno::ENOENT
        raise Error, "VS Code policy not found: #{policy_path}"
      end

      def validate_policy!(data)
        settings = data.fetch("settings") { raise Error, "VS Code policy is missing required `settings` key" }
        raise Error, "VS Code policy `settings` must be a mapping" unless settings.is_a?(Hash)

        generated = data.fetch("generated_settings", {})
        raise Error, "VS Code policy `generated_settings` must be a mapping" unless generated.is_a?(Hash)
        generated.each do |key, value|
          unless key == "extensions.allowed" && value == "extensions"
            raise Error, "unsupported generated VS Code setting: #{key}=#{value.inspect}"
          end
        end

        selected = data.fetch("selected_auto_update", {})
        raise Error, "VS Code policy `selected_auto_update` must be a mapping" unless selected.is_a?(Hash)
        %w[allow_from_extension_manifest deny_all_others require_vscode_closed backup_before_write].each do |key|
          next if selected[key] == true || selected[key] == false

          raise Error, "VS Code policy selected_auto_update.#{key} must be true or false"
        end

        settings_sync = data.fetch("settings_sync", {})
        raise Error, "VS Code policy `settings_sync` must be a mapping" unless settings_sync.is_a?(Hash)
        if settings_sync.fetch("extensions", "warn-only") != "warn-only"
          raise Error, "VS Code policy settings_sync.extensions must be warn-only"
        end

        unmanaged = data.fetch("unmanaged_user_files", {})
        raise Error, "VS Code policy `unmanaged_user_files` must be a mapping" unless unmanaged.is_a?(Hash)
        %w[warn warn_if_nonempty].each do |key|
          paths = unmanaged.fetch(key, [])
          raise Error, "VS Code policy unmanaged_user_files.#{key} must be an array" unless paths.is_a?(Array)
          raise Error, "VS Code policy unmanaged_user_files.#{key} entries must be strings" unless paths.all?(String)
        end
      end

      def safe_load_yaml(path)
        YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false)
      end

      def extension_actions
        inventory = installed_inventory
        return [warning("code CLI not found or extension inventory unavailable; validated manifest without live drift comparison")] unless inventory

        by_id = inventory.to_h { |spec| [extension_id_from_spec(spec), spec] }
        extension_plan = extensions.map do |extension|
          current_spec = by_id[extension.id]
          current_version = current_spec&.split("@", 2)&.last

          if current_spec.nil?
            action("extension", "install", id: extension.id, version: extension.version, spec: extension.spec)
          elsif current_spec == extension.spec
            keep_action(extension, current_version)
          elsif extension.auto_update
            action("extension", "keep_auto_update", id: extension.id, current_version: current_version,
                                                      version: extension.version, spec: extension.spec)
          else
            action("extension", "update", id: extension.id, current_version: current_version,
                                           version: extension.version, spec: extension.spec)
          end
        end

        if prune
          tracked_ids = extensions.map(&:id)
          extras = by_id.keys.sort - tracked_ids
          extension_plan.concat(extras.map { |id| action("extension", "prune", id: id) })
        end

        extension_plan
      end

      def keep_action(extension, current_version)
        action_name = extension.auto_update ? "keep_auto_update" : "keep"
        action("extension", action_name, id: extension.id, current_version: current_version,
                                         version: extension.version, spec: extension.spec)
      end

      def settings_actions
        current = current_settings
        desired_settings.map do |key, desired_value|
          current_value = current[key]
          if current.key?(key) && current_value == desired_value
            action("setting", "keep", key: key, desired: desired_value, current: current_value)
          else
            action("setting", "write", key: key, desired: desired_value, current: current_value)
          end
        end
      end

      def storage_actions
        selected_policy = policy.fetch("selected_auto_update")
        return [] unless selected_policy.fetch("allow_from_extension_manifest")

        desired_allow = extensions.select(&:auto_update).map(&:id).sort
        desired_deny = selected_policy.fetch("deny_all_others") ? extensions.reject(&:auto_update).map(&:id).sort : []

        [
          storage_action(SELECTED_AUTO_UPDATE_KEY, desired_allow),
          storage_action(DISABLED_AUTO_UPDATE_KEY, desired_deny)
        ]
      end

      def storage_action(key, desired)
        current = current_storage_array(key)
        if current == desired
          action("storage", "keep", key: key, desired: desired, current: current)
        else
          action("storage", "configure", key: key, desired: desired, current: current)
        end
      end

      def unmanaged_user_file_warnings
        unmanaged = policy.fetch("unmanaged_user_files", {})
        warnings = unmanaged.fetch("warn", []).map do |relative_path|
          path = File.join(user_dir, relative_path)
          next unless File.exist?(path) || File.symlink?(path)

          warning("unmanaged VS Code user file exists and is not yet managed: #{path}")
        end.compact

        warnings.concat(unmanaged.fetch("warn_if_nonempty", []).map do |relative_path|
          path = File.join(user_dir, relative_path)
          next unless unmanaged_user_path_nonempty?(path)

          warning("unmanaged VS Code user file is non-empty and is not yet managed: #{path}")
        end.compact)
        warnings
      end

      def unmanaged_user_path_nonempty?(path)
        return Dir.children(path).any? if File.directory?(path)
        return File.size(path).positive? if File.file?(path)

        false
      end

      def current_settings
        @current_settings ||= parse_jsonc(settings_path)
      rescue Errno::ENOENT
        {}
      end

      def parse_jsonc(path)
        text = File.read(path)
        out = +""
        in_string = false
        escape = false
        chars = text.each_char.to_a
        i = 0

        while i < chars.length
          char = chars[i]
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
          elsif char == "/" && chars[i + 1] == "/"
            i += 2
            i += 1 while i < chars.length && chars[i] != "\n"
            out << "\n" if i < chars.length
          elsif char == "/" && chars[i + 1] == "*"
            i += 2
            closed = false
            while i < chars.length
              if chars[i] == "*" && chars[i + 1] == "/"
                i += 1
                closed = true
                break
              end
              out << "\n" if chars[i] == "\n"
              i += 1
            end
            raise Error, "invalid VS Code settings JSON: unterminated block comment" unless closed
          else
            out << char
          end
          i += 1
        end

        JSON.parse(out.gsub(/,\s*([}\]])/, "\\1"))
      rescue JSON::ParserError => e
        raise Error, "invalid VS Code settings JSON: #{e.message}"
      end

      def apply_settings(plan_actions)
        writes = plan_actions.select { |action| action["type"] == "setting" && action["action"] == "write" }
        return if writes.empty?

        settings = current_settings.dup
        writes.each { |setting_action| settings[setting_action.fetch("key")] = setting_action.fetch("desired") }
        File.write(settings_path, "#{JSON.pretty_generate(settings)}\n")
        puts "Updated VS Code settings policy in #{settings_path}"
        @current_settings = settings
      end

      def apply_extensions(plan_actions)
        extension_plan = plan_actions.select { |action| action["type"] == "extension" }
        actionable = extension_plan.reject { |action| %w[keep keep_auto_update].include?(action.fetch("action")) }
        return if actionable.empty?

        raise Error, "'code' CLI not found. Add it from VS Code: Shell Command: Install 'code' command in PATH" unless command?("code")

        actionable.each do |extension_action|
          case extension_action.fetch("action")
          when "install", "update"
            run_code!("--install-extension", extension_action.fetch("spec"), "--force")
            puts "Installed VS Code extension baseline: #{extension_action.fetch("spec")}"
          when "prune"
            result = uninstall_extension!(extension_action.fetch("id"))
            if result == :absent
              puts "VS Code extension already absent: #{extension_action.fetch("id")}"
            else
              puts "Uninstalled VS Code extension not in manifest: #{extension_action.fetch("id")}"
            end
          end
        end

        @installed_inventory = nil
      end

      def apply_storage(plan_actions)
        configure = plan_actions.any? { |action| action["type"] == "storage" && action["action"] == "configure" }
        return unless configure

        selected_policy = policy.fetch("selected_auto_update")
        ensure_vscode_closed! if selected_policy.fetch("require_vscode_closed")
        backup_storage! if selected_policy.fetch("backup_before_write")
        write_storage_arrays
        @current_storage = {}
      end

      def ensure_vscode_closed!
        return unless command?("pgrep")
        return unless system("pgrep", "-x", "Code", out: File::NULL, err: File::NULL)

        raise Error, "VS Code is running. Quit VS Code before applying selected extension auto-update storage."
      end

      def backup_storage!
        return unless File.exist?(storage_db)

        state_dir = File.join(ROOT, ".dotfiles/state")
        FileUtils.mkdir_p(state_dir)
        timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
        backup_path = File.join(state_dir, "vscode-state.vscdb.#{timestamp}.bak")
        FileUtils.cp(storage_db, backup_path)
        puts "Backed up VS Code global storage to #{backup_path}"
      end

      def write_storage_arrays
        raise Error, "sqlite3 is required to configure VS Code selected extension auto-update policy" unless command?("sqlite3")

        FileUtils.mkdir_p(File.dirname(storage_db))
        desired = storage_actions.to_h { |storage_action| [storage_action.fetch("key"), storage_action.fetch("desired")] }
        sql = <<~SQL
          CREATE TABLE IF NOT EXISTS ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);
          INSERT OR REPLACE INTO ItemTable (key, value) VALUES ('#{SELECTED_AUTO_UPDATE_KEY}', '#{sql_literal(JSON.generate(desired.fetch(SELECTED_AUTO_UPDATE_KEY)))}');
          INSERT OR REPLACE INTO ItemTable (key, value) VALUES ('#{DISABLED_AUTO_UPDATE_KEY}', '#{sql_literal(JSON.generate(desired.fetch(DISABLED_AUTO_UPDATE_KEY)))}');
        SQL
        stdout, stderr, status = Open3.capture3("sqlite3", storage_db, sql)
        return if status.success?

        raise Error, "failed to configure VS Code selected auto-update storage: #{stderr.empty? ? stdout : stderr}"
      end

      def installed_inventory
        @installed_inventory ||= begin
          specs = if installed_extensions_file
                    File.read(installed_extensions_file)
                  elsif command?("code")
                    stdout, _stderr, status = Open3.capture3("code", "--list-extensions", "--show-versions")
                    status.success? ? stdout : nil
                  end
          specs&.lines&.map(&:strip)&.reject(&:empty?)&.sort
        end
      end

      def current_storage_array(key)
        return nil unless File.exist?(storage_db)
        return nil unless command?("sqlite3")

        @current_storage ||= {}
        return @current_storage[key] if @current_storage.key?(key)

        stdout, _stderr, status = Open3.capture3("sqlite3", storage_db, "SELECT value FROM ItemTable WHERE key = '#{sql_literal(key)}';")
        @current_storage[key] = if status.success? && !stdout.strip.empty?
                                  JSON.parse(stdout.strip).map(&:downcase).sort
                                end
      rescue JSON::ParserError
        @current_storage[key] = nil
      end

      def storage_db
        File.join(user_dir, "globalStorage/state.vscdb")
      end

      def run_code!(*args)
        stdout, stderr, status = Open3.capture3("code", *args)
        return true if status.success?

        raise Error, "code #{args.join(" ")} failed: #{stderr.empty? ? stdout : stderr}"
      end

      def uninstall_extension!(extension_id)
        stdout, stderr, status = Open3.capture3("code", "--uninstall-extension", extension_id)
        return :uninstalled if status.success?

        message = stderr.empty? ? stdout : stderr
        return :absent if message.include?("is not installed")

        raise Error, "code --uninstall-extension #{extension_id} failed: #{message}"
      end

      def command?(name)
        Runtime.command?(name)
      end

      def extension_id_from_spec(spec)
        spec.split("@", 2).first
      end

      def terminal_action?(action)
        case action.fetch("action")
        when "keep", "keep_auto_update", "warn"
          true
        else
          false
        end
      end

      def action(type, action_name, attrs = {})
        { "type" => type, "action" => action_name }.merge(stringify_keys(attrs))
      end

      def warning(message)
        action("warning", "warn", message: message)
      end

      def stringify_keys(hash)
        hash.to_h { |key, value| [key.to_s, value] }
      end

      def format_action(action)
        case [action.fetch("type"), action.fetch("action")]
        when ["extension", "install"]
          "install extension baseline: #{action.fetch("spec")}"
        when ["extension", "update"]
          "update extension to baseline: #{action.fetch("id")} #{action.fetch("current_version")} -> #{action.fetch("version")}"
        when ["extension", "prune"]
          "prune extension not in manifest: #{action.fetch("id")}"
        when ["extension", "keep_auto_update"]
          "keep auto-update extension: #{action.fetch("id")} current=#{action.fetch("current_version")} baseline=#{action.fetch("version")}"
        when ["extension", "keep"]
          "keep extension: #{action.fetch("spec")}"
        when ["setting", "write"]
          "write setting: #{action.fetch("key")} -> #{JSON.generate(action.fetch("desired"))}"
        when ["setting", "keep"]
          "keep setting: #{action.fetch("key")}"
        when ["storage", "configure"]
          "configure VS Code storage: #{action.fetch("key")} -> #{JSON.generate(action.fetch("desired"))}"
        when ["storage", "keep"]
          "keep VS Code storage: #{action.fetch("key")}"
        when ["warning", "warn"]
          "warn: #{action.fetch("message")}"
        when ["issue", "error"]
          "issue: #{action.fetch("message")}"
        else
          "#{action.fetch("type")}: #{action.fetch("action")} #{action.inspect}"
        end
      end

      def sql_literal(value)
        value.gsub("'", "''")
      end
    end
  end
end
