# frozen_string_literal: true

require "open3"
require "spec_helper"

RSpec.describe "Secretive Git wrappers" do
  def with_test_socket_file(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "")
    yield
  ensure
    FileUtils.rm_f(path)
  end

  def write_executable(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    FileUtils.chmod(0o755, path)
  end

  def public_key_path(root)
    File.join(root, ".config/git/secretive_git_key.pub")
  end

  it "runs Git SSH transport through Secretive with disk-key fallbacks disabled" do
    root = Dir.mktmpdir
    socket_path = File.join(root, "secretive.sock")
    capture_path = File.join(root, "ssh-capture.txt")
    fake_ssh = File.join(root, "fake-ssh")
    FileUtils.mkdir_p(File.dirname(public_key_path(root)))
    File.write(public_key_path(root), "ssh-ed25519 AAAATEST git\n")
    write_executable(fake_ssh, <<~BASH)
      #!/usr/bin/env bash
      {
        printf 'SSH_AUTH_SOCK=%s\\n' "$SSH_AUTH_SOCK"
        printf 'arg=%s\\n' "$@"
      } > "$CAPTURE_PATH"
    BASH

    with_test_socket_file(socket_path) do
      _stdout, stderr, status = Open3.capture3(
        {
          "HOME" => root,
          "SECRETIVE_SSH_AUTH_SOCK" => socket_path,
          "GIT_SECRETIVE_TEST_SKIP_SOCKET_CHECK" => "1",
          "GIT_SECRETIVE_IDENTITY_FILE" => public_key_path(root),
          "GIT_SECRETIVE_SSH_BIN" => fake_ssh,
          "CAPTURE_PATH" => capture_path
        },
        File.join(ROOT, "local-bin/git-secretive-ssh"),
        "git@github.com",
        "git-upload-pack repo.git"
      )

      expect(status).to be_success, stderr
    end

    capture = File.read(capture_path)
    expect(capture).to include(
      "SSH_AUTH_SOCK=#{socket_path}",
      "arg=-o",
      "arg=IdentityAgent=#{socket_path}",
      "arg=IdentityFile=#{public_key_path(root)}",
      "arg=PasswordAuthentication=no",
      "arg=KbdInteractiveAuthentication=no",
      "arg=BatchMode=yes",
      "arg=AddKeysToAgent=no",
      "arg=UseKeychain=no",
      "arg=git@github.com"
    )
  end

  it "allows Git SSH signing only with the configured Secretive public key" do
    root = Dir.mktmpdir
    socket_path = File.join(root, "secretive.sock")
    capture_path = File.join(root, "ssh-keygen-capture.txt")
    fake_ssh_keygen = File.join(root, "fake-ssh-keygen")
    FileUtils.mkdir_p(File.dirname(public_key_path(root)))
    File.write(public_key_path(root), "ssh-ed25519 AAAATEST git\n")
    write_executable(fake_ssh_keygen, <<~BASH)
      #!/usr/bin/env bash
      {
        printf 'SSH_AUTH_SOCK=%s\\n' "$SSH_AUTH_SOCK"
        printf 'arg=%s\\n' "$@"
      } > "$CAPTURE_PATH"
    BASH

    with_test_socket_file(socket_path) do
      _stdout, stderr, status = Open3.capture3(
        {
          "HOME" => root,
          "SECRETIVE_SSH_AUTH_SOCK" => socket_path,
          "GIT_SECRETIVE_TEST_SKIP_SOCKET_CHECK" => "1",
          "GIT_SECRETIVE_IDENTITY_FILE" => public_key_path(root),
          "GIT_SECRETIVE_SSH_KEYGEN_BIN" => fake_ssh_keygen,
          "CAPTURE_PATH" => capture_path
        },
        File.join(ROOT, "local-bin/git-secretive-ssh-keygen"),
        "-Y",
        "sign",
        "-f",
        public_key_path(root),
        "-n",
        "git",
        File.join(root, "payload")
      )

      expect(status).to be_success, stderr
    end

    expect(File.read(capture_path)).to include("SSH_AUTH_SOCK=#{socket_path}", "arg=-Y", "arg=sign", "arg=#{public_key_path(root)}")

    FileUtils.rm_f(capture_path)
    with_test_socket_file(socket_path) do
      _stdout, stderr, status = Open3.capture3(
        {
          "HOME" => root,
          "SECRETIVE_SSH_AUTH_SOCK" => socket_path,
          "GIT_SECRETIVE_TEST_SKIP_SOCKET_CHECK" => "1",
          "GIT_SECRETIVE_IDENTITY_FILE" => public_key_path(root),
          "GIT_SECRETIVE_SSH_KEYGEN_BIN" => fake_ssh_keygen,
          "CAPTURE_PATH" => capture_path
        },
        File.join(ROOT, "local-bin/git-secretive-ssh-keygen"),
        "-Y",
        "sign",
        "-f",
        File.join(root, ".ssh/id_ed25519"),
        "-n",
        "git",
        File.join(root, "payload")
      )

      expect(status).not_to be_success
      expect(stderr).to include("Refusing Git SSH signing with non-Secretive key")
    end
    expect(File).not_to exist(capture_path)
  end

  it "delegates Git SSH verification without requiring Secretive" do
    root = Dir.mktmpdir
    capture_path = File.join(root, "ssh-keygen-verify-capture.txt")
    fake_ssh_keygen = File.join(root, "fake-ssh-keygen")
    allowed_signers = File.join(root, "allowed_signers")
    File.write(allowed_signers, "grant.birkinbine@gmail.com ssh-ed25519 AAAATEST git\n")
    write_executable(fake_ssh_keygen, <<~BASH)
      #!/usr/bin/env bash
      {
        printf 'SSH_AUTH_SOCK=%s\\n' "${SSH_AUTH_SOCK:-}"
        printf 'arg=%s\\n' "$@"
      } > "$CAPTURE_PATH"
    BASH

    _stdout, stderr, status = Open3.capture3(
      {
        "HOME" => root,
        "SSH_AUTH_SOCK" => nil,
        "SECRETIVE_SSH_AUTH_SOCK" => File.join(root, "missing-secretive.sock"),
        "GIT_SECRETIVE_SSH_KEYGEN_BIN" => fake_ssh_keygen,
        "CAPTURE_PATH" => capture_path
      },
      File.join(ROOT, "local-bin/git-secretive-ssh-keygen"),
      "-Y",
      "verify",
      "-f",
      allowed_signers,
      "-I",
      "grant.birkinbine@gmail.com",
      "-n",
      "git",
      "-s",
      File.join(root, "payload.sig")
    )

    expect(status).to be_success, stderr
    expect(File.read(capture_path)).to include("SSH_AUTH_SOCK=\n", "arg=-Y", "arg=verify", "arg=#{allowed_signers}")
  end
end
