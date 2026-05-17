# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/dotfiles/runtime"

RSpec.describe Dotfiles::Runtime do
  it "formats timestamps and unique paths" do
    Dir.mktmpdir do |dir|
      now = Time.new(2026, 5, 17, 10, 1, 2)
      path = File.join(dir, "target")

      expect(described_class.timestamp(now)).to eq("20260517100102")
      expect(described_class.unique_path(path, now: now)).to eq(path)

      File.write(path, "exists")
      expect(described_class.unique_path(path, now: now)).to eq("#{path}.20260517100102")
      File.write("#{path}.20260517100102", "exists")
      expect(described_class.unique_path(path, now: now)).to eq("#{path}.20260517100102.1")
    end
  end

  it "checks commands, colors values, and detects macOS platforms" do
    Dir.mktmpdir do |dir|
      command = File.join(dir, "tool")
      File.write(command, "#!/bin/sh\n")
      FileUtils.chmod("+x", command)
      original_path = ENV["PATH"]
      ENV["PATH"] = dir

      expect(described_class.command?("tool")).to eq(true)
      expect(described_class.command?("missing")).to eq(false)
      expect(described_class.value("x", color: false)).to eq("x")
      expect(described_class.value("x", color: true)).to eq("\033[0;36mx\033[0m")
      expect(described_class.bad_value("x", color: false)).to eq("x")
      expect(described_class.warn_value("x", color: false)).to eq("x")
      expect(described_class.darwin?("arm64-darwin25")).to eq(true)
      expect(described_class.darwin?("x86_64-linux")).to eq(false)
    ensure
      ENV["PATH"] = original_path
    end
  end
end
