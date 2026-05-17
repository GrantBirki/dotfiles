# frozen_string_literal: true

require "fileutils"
require "time"

module Dotfiles
  module Runtime
    COLORS = {
      cyan: "\033[0;36m",
      red: "\033[0;31m",
      yellow: "\033[0;33m"
    }.freeze
    OFF = "\033[0m"

    module_function

    def timestamp(now = Time.now)
      now.strftime("%Y%m%d%H%M%S")
    end

    def unique_path(path, now: Time.now)
      return path unless File.exist?(path) || File.symlink?(path)

      base = "#{path}.#{timestamp(now)}"
      candidate = base
      counter = 1
      while File.exist?(candidate) || File.symlink?(candidate)
        candidate = "#{base}.#{counter}"
        counter += 1
      end
      candidate
    end

    def command?(name)
      ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |dir|
        candidate = File.join(dir, name)
        File.file?(candidate) && File.executable?(candidate)
      end
    end

    def color(text, name, enabled:)
      return text.to_s unless enabled

      "#{COLORS.fetch(name)}#{text}#{OFF}"
    end

    def value(text, color: true)
      color(text, :cyan, enabled: color)
    end

    def bad_value(text, color: true)
      color(text, :red, enabled: color)
    end

    def warn_value(text, color: true)
      color(text, :yellow, enabled: color)
    end

    def darwin?(platform = RUBY_PLATFORM)
      platform.include?("darwin")
    end
  end
end
