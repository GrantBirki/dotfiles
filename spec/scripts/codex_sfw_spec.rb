# frozen_string_literal: true

require "open3"
require "spec_helper"

RSpec.describe "codex-sfw launcher" do
  def write_executable(path, body)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    FileUtils.chmod("+x", path)
  end

  it "launches codex with dotfiles language-manager paths and SFW shims first" do
    Dir.mktmpdir do |home|
      capture_path = File.join(home, "codex-env")
      expected_paths = [
        File.join(home, ".local/share/dotfiles/sfw-shims"),
        File.join(home, ".nodenv/shims"),
        File.join(home, ".pyenv/shims"),
        File.join(home, ".cargo/bin"),
        File.join(home, "bin"),
        File.join(home, ".local/bin")
      ]
      expected_paths.each { |path| FileUtils.mkdir_p(path) }
      write_executable(File.join(home, ".local/bin/codex"), <<~BASH)
        #!/usr/bin/env bash
        {
          printf 'DOTFILES_SFW_REQUIRE=%s\\n' "$DOTFILES_SFW_REQUIRE"
          printf 'DOTFILES_SFW_SHIM_DIR=%s\\n' "$DOTFILES_SFW_SHIM_DIR"
          printf 'PATH=%s\\n' "$PATH"
          printf 'args=%s\\n' "$*"
        } > "$CAPTURE_PATH"
      BASH

      _stdout, stderr, status = Open3.capture3(
        {
          "CAPTURE_PATH" => capture_path,
          "HOME" => home,
          "PATH" => "/usr/bin:/bin"
        },
        File.join(ROOT, "local-bin/codex-sfw"),
        "exec",
        "npm --version"
      )

      expect(status).to be_success, stderr
      capture = File.read(capture_path)
      expect(capture).to include(
        "DOTFILES_SFW_REQUIRE=1",
        "DOTFILES_SFW_SHIM_DIR=#{File.join(home, ".local/share/dotfiles/sfw-shims")}",
        "args=exec npm --version"
      )
      expect(capture).to include("PATH=#{(expected_paths + ["/usr/bin", "/bin"]).join(File::PATH_SEPARATOR)}")
    end
  end
end
