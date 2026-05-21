# frozen_string_literal: true

require "open3"
require "spec_helper"

RSpec.describe "Socket Firewall package-manager shim" do
  def write_executable(path, body)
    File.write(path, body)
    FileUtils.chmod("+x", path)
  end

  def setup_shim(dir, name)
    shim_dir = File.join(dir, "shims")
    FileUtils.mkdir_p(shim_dir)
    FileUtils.ln_s(File.join(ROOT, "shell/sfw/package-manager-shim.bash"), File.join(shim_dir, name))
    shim_dir
  end

  def run_shim(env, shim_dir, name, *args)
    Open3.capture3(env, File.join(shim_dir, name), *args)
  end

  it "routes package-manager invocations through real sfw with the shim path removed" do
    Dir.mktmpdir do |dir|
      shim_dir = setup_shim(dir, "npm")
      real_dir = File.join(dir, "real")
      log = File.join(dir, "log")
      FileUtils.mkdir_p(real_dir)
      write_executable(File.join(real_dir, "sfw"), <<~SH)
        #!/bin/sh
        {
          printf 'cmd=sfw\\n'
          printf 'args=%s\\n' "$*"
          printf 'path=%s\\n' "$PATH"
          printf 'active=%s\\n' "${DOTFILES_SFW_ACTIVE:-}"
        } >> "$LOG"
      SH
      write_executable(File.join(real_dir, "npm"), <<~SH)
        #!/bin/sh
        printf 'cmd=npm\\n' >> "$LOG"
      SH
      env = {
        "DOTFILES_SFW_SHIM_DIR" => shim_dir,
        "DOTFILES_SFW_REQUIRE" => "1",
        "HOME" => dir,
        "LOG" => log,
        "PATH" => [shim_dir, real_dir, "/bin", "/usr/bin"].join(File::PATH_SEPARATOR)
      }

      _stdout, stderr, status = run_shim(env, shim_dir, "npm", "install", "left-pad")

      expect(status).to be_success
      expect(stderr).to eq("")
      expect(File.read(log)).to include(
        "cmd=sfw",
        "args=npm install left-pad",
        "path=#{[real_dir, "/bin", "/usr/bin"].join(File::PATH_SEPARATOR)}",
        "active=1"
      )
      expect(File.read(log)).not_to include("cmd=npm")
    end
  end

  it "forwards explicit sfw invocations to the real sfw without re-entering the shim" do
    Dir.mktmpdir do |dir|
      shim_dir = setup_shim(dir, "sfw")
      real_dir = File.join(dir, "real")
      log = File.join(dir, "log")
      FileUtils.mkdir_p(real_dir)
      write_executable(File.join(real_dir, "sfw"), <<~SH)
        #!/bin/sh
        {
          printf 'args=%s\\n' "$*"
          printf 'path=%s\\n' "$PATH"
          printf 'active=%s\\n' "${DOTFILES_SFW_ACTIVE:-}"
        } >> "$LOG"
      SH
      env = {
        "DOTFILES_SFW_SHIM_DIR" => shim_dir,
        "HOME" => dir,
        "LOG" => log,
        "PATH" => [shim_dir, real_dir, "/bin", "/usr/bin"].join(File::PATH_SEPARATOR)
      }

      _stdout, stderr, status = run_shim(env, shim_dir, "sfw", "npm", "--version")

      expect(status).to be_success
      expect(stderr).to eq("")
      expect(File.read(log)).to include(
        "args=npm --version",
        "path=#{[real_dir, "/bin", "/usr/bin"].join(File::PATH_SEPARATOR)}",
        "active=1"
      )
    end
  end

  it "uses the real package manager when explicitly disabled" do
    Dir.mktmpdir do |dir|
      shim_dir = setup_shim(dir, "npm")
      real_dir = File.join(dir, "real")
      log = File.join(dir, "log")
      FileUtils.mkdir_p(real_dir)
      write_executable(File.join(real_dir, "sfw"), <<~SH)
        #!/bin/sh
        printf 'cmd=sfw\\n' >> "$LOG"
      SH
      write_executable(File.join(real_dir, "npm"), <<~SH)
        #!/bin/sh
        {
          printf 'cmd=npm\\n'
          printf 'args=%s\\n' "$*"
          printf 'path=%s\\n' "$PATH"
        } >> "$LOG"
      SH
      env = {
        "DOTFILES_SFW_DISABLE" => "1",
        "DOTFILES_SFW_SHIM_DIR" => shim_dir,
        "HOME" => dir,
        "LOG" => log,
        "PATH" => [shim_dir, real_dir, "/bin", "/usr/bin"].join(File::PATH_SEPARATOR)
      }

      _stdout, stderr, status = run_shim(env, shim_dir, "npm", "install", "left-pad")

      expect(status).to be_success
      expect(stderr).to eq("")
      expect(File.read(log)).to include(
        "cmd=npm",
        "args=install left-pad",
        "path=#{[real_dir, "/bin", "/usr/bin"].join(File::PATH_SEPARATOR)}"
      )
      expect(File.read(log)).not_to include("cmd=sfw")
    end
  end

  it "fails closed when sfw is required but unavailable" do
    Dir.mktmpdir do |dir|
      shim_dir = setup_shim(dir, "npm")
      real_dir = File.join(dir, "real")
      FileUtils.mkdir_p(real_dir)
      write_executable(File.join(real_dir, "npm"), "#!/bin/sh\nexit 0\n")
      env = {
        "DOTFILES_SFW_SHIM_DIR" => shim_dir,
        "DOTFILES_SFW_REQUIRE" => "1",
        "HOME" => dir,
        "PATH" => [shim_dir, real_dir, "/bin", "/usr/bin"].join(File::PATH_SEPARATOR)
      }

      _stdout, stderr, status = run_shim(env, shim_dir, "npm", "--version")

      expect(status.exitstatus).to eq(127)
      expect(stderr).to include(
        "dotfiles-sfw-shim: refusing to run npm unprotected because sfw is unavailable",
        "dotfiles-sfw-shim: install with: DOTFILES_SFW_DISABLE=1 npm i -g sfw && nodenv rehash"
      )
    end
  end
end
