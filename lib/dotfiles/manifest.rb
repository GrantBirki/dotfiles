# frozen_string_literal: true

require "json"
require "yaml"

module Dotfiles
  ROOT = File.expand_path("../..", __dir__)
  DEFAULT_MANIFEST_PATH = File.join(ROOT, "install.yml")
  VALID_MODES = ["symlink"].freeze
  VALID_PARENT_POLICIES = ["create", "require"].freeze

  class Manifest
    attr_reader :path, :entries

    def self.load(path = DEFAULT_MANIFEST_PATH)
      new(path)
    end

    def initialize(path)
      @path = File.expand_path(path)
      @entries = load_entries
    end

    def validate
      errors = []
      seen_ids = {}
      seen_targets = {}

      entries.each_with_index do |entry, index|
        errors.concat(entry.validate(index: index))

        if seen_ids[entry.id]
          errors << "duplicate id: #{entry.id}"
        end
        seen_ids[entry.id] = true

        if seen_targets[entry.target]
          errors << "duplicate target: #{entry.target}"
        end
        seen_targets[entry.target] = true
      end

      errors
    end

    def validate!
      errors = validate
      return true if errors.empty?

      raise Error, errors.join("\n")
    end

    private

    def load_entries
      data = safe_load_yaml(File.read(path))
      files = data.fetch("files")
      unless files.is_a?(Array)
        raise Error, "manifest `files` must be an array"
      end

      files.map { |attrs| Entry.new(attrs) }
    rescue Errno::ENOENT
      raise Error, "manifest not found: #{path}"
    rescue KeyError
      raise Error, "manifest is missing required `files` key"
    end

    def safe_load_yaml(text)
      YAML.safe_load(text, permitted_classes: [], permitted_symbols: [], aliases: false)
    rescue ArgumentError
      YAML.safe_load(text, [], [], false)
    end
  end

  class Entry
    REQUIRED_KEYS = ["id", "source", "target", "mode", "parent"].freeze
    attr_reader :id, :source, :target, :mode, :parent

    def initialize(attrs)
      unless attrs.is_a?(Hash)
        raise Error, "manifest file entry must be a map"
      end

      @id = attrs["id"].to_s
      @source = attrs["source"].to_s
      @target = attrs["target"].to_s
      @mode = attrs["mode"].to_s
      @parent = attrs["parent"].to_s
    end

    def validate(index:)
      errors = []
      REQUIRED_KEYS.each do |key|
        value = public_send(key.tr("-", "_"))
        errors << "entry #{index} is missing #{key}" if value.empty?
      end

      errors << "#{id}: source must be repo-relative" if source.start_with?("/", "~")
      errors << "#{id}: source does not exist: #{source}" unless File.exist?(source_path)
      errors << "#{id}: target must start with ~/; got #{target}" unless target.start_with?("~/")
      errors << "#{id}: unsupported mode #{mode}" unless VALID_MODES.include?(mode)
      errors << "#{id}: unsupported parent policy #{parent}" unless VALID_PARENT_POLICIES.include?(parent)
      errors
    end

    def source_path
      File.join(ROOT, source)
    end

    def target_path
      expand_home(target)
    end

    def backup_path
      relative_target = target.delete_prefix("~/")
      File.join(ENV.fetch("HOME"), "dotfiles_old", relative_target)
    end

    def target_parent
      File.dirname(target_path)
    end

    def to_h
      {
        "id" => id,
        "source" => source,
        "target" => target,
        "mode" => mode,
        "parent" => parent,
        "source_path" => source_path,
        "target_path" => target_path,
        "backup_path" => backup_path,
        "target_parent" => target_parent
      }
    end

    private

    def expand_home(path)
      path.sub(/\A~(?=\/|\z)/, ENV.fetch("HOME"))
    end
  end

  class Error < StandardError; end
end
