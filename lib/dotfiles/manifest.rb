# frozen_string_literal: true

require "json"
require "fileutils"
require "yaml"

module Dotfiles
  ROOT = File.expand_path("../..", __dir__)
  DEFAULT_MANIFEST_PATH = File.join(ROOT, "install.yml")
  VALID_MODES = ["copy", "symlink"].freeze
  VALID_PARENT_POLICIES = ["create", "require"].freeze
  VALID_COMPARE_STRATEGIES = ["exact", "karabiner"].freeze

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
    end
  end

  class Entry
    REQUIRED_KEYS = ["id", "source", "target", "mode", "parent"].freeze
    BOOLEAN_VALUES = [true, false].freeze
    attr_reader :id, :source, :target, :mode, :parent, :compare, :optional

    def initialize(attrs)
      unless attrs.is_a?(Hash)
        raise Error, "manifest file entry must be a map"
      end

      @id = attrs["id"].to_s
      @source = attrs["source"].to_s
      @target = attrs["target"].to_s
      @mode = attrs["mode"].to_s
      @parent = attrs["parent"].to_s
      @compare = attrs.fetch("compare", "exact").to_s
      @optional = attrs.fetch("optional", false)
    end

    def validate(index:)
      errors = []
      REQUIRED_KEYS.each do |key|
        value = public_send(key.tr("-", "_"))
        errors << "entry #{index} is missing #{key}" if value.empty?
      end

      errors << "#{id}: source must be repo-relative" if source.start_with?("/", "~")
      errors << "#{id}: source must not contain .. segments" if path_has_parent_traversal?(source)
      errors << "#{id}: optional must be true or false" unless BOOLEAN_VALUES.include?(optional)
      errors << "#{id}: source does not exist: #{source}" if !optional && !File.exist?(source_path)
      errors << "#{id}: target must start with ~/; got #{target}" unless target.start_with?("~/")
      errors << "#{id}: target must not contain .. segments" if path_has_parent_traversal?(target.delete_prefix("~/"))
      errors << "#{id}: source must stay within repo root" unless within_root?(source_path, ROOT)
      errors << "#{id}: target must stay within HOME" unless within_root?(target_path, ENV.fetch("HOME"))
      errors << "#{id}: backup must stay within HOME/dotfiles_old" unless within_root?(backup_path, File.join(ENV.fetch("HOME"), "dotfiles_old"))
      errors << "#{id}: unsupported mode #{mode}" unless VALID_MODES.include?(mode)
      errors << "#{id}: unsupported parent policy #{parent}" unless VALID_PARENT_POLICIES.include?(parent)
      errors << "#{id}: unsupported compare strategy #{compare}" unless VALID_COMPARE_STRATEGIES.include?(compare)
      errors
    end

    def source_path
      canonical_join(ROOT, source)
    end

    def active?
      !optional || File.exist?(source_path)
    end

    def target_path
      expand_home(target)
    end

    def target_matches?
      return false unless File.exist?(target_path) || File.symlink?(target_path)

      case compare
      when "exact"
        FileUtils.compare_file(source_path, target_path)
      when "karabiner"
        normalized_karabiner(source_path) == normalized_karabiner(target_path)
      else
        false
      end
    end

    def backup_path
      relative_target = target.delete_prefix("~/")
      canonical_join(File.join(ENV.fetch("HOME"), "dotfiles_old"), relative_target)
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
        "compare" => compare,
        "optional" => optional,
        "active" => active?,
        "source_path" => source_path,
        "target_path" => target_path,
        "backup_path" => backup_path,
        "target_parent" => target_parent
      }
    end

    private

    def expand_home(path)
      canonical_join(ENV.fetch("HOME"), path.delete_prefix("~/"))
    end

    def canonical_join(base, relative)
      relative_path = relative.to_s
      relative_path = "./#{relative_path}" if relative_path.start_with?("~")
      File.expand_path(relative_path, base)
    end

    def path_has_parent_traversal?(path)
      path.split("/").include?("..")
    end

    def within_root?(path, root)
      candidate = File.expand_path(path)
      root_path = File.expand_path(root)
      candidate == root_path || candidate.start_with?("#{root_path}/")
    end

    def normalized_karabiner(path)
      data = JSON.parse(File.read(path))
      Array(data["profiles"]).each do |profile|
        profile.delete("virtual_hid_keyboard")
      end
      data
    end
  end

  class Error < StandardError; end
end
