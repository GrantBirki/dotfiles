# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/dotfiles/test_checks"

RSpec.describe Dotfiles::TestChecks do
  def write_file(root, relative_path, content)
    path = File.join(root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def minimal_lock(checksums: true, checksum_line: "  diff-lcs (1.6.2) sha256=9ae0d2cba7d4df3075fe8cd8602a8604993efc0dfa934cff568969efb1909962")
    <<~LOCK
      GEM
        remote: https://rubygems.org/
        specs:
          diff-lcs (1.6.2)

      PLATFORMS
        ruby

      DEPENDENCIES
        diff-lcs
      #{checksums ? "\nCHECKSUMS\n#{checksum_line}\n" : ""}
      BUNDLED WITH
        4.0.6
    LOCK
  end

  describe Dotfiles::TestChecks::JSONC do
    it "validates JSON with line comments, block comments, trailing commas, and strings" do
      path = write_file(
        Dir.mktmpdir,
        "settings.json",
        <<~JSON
          {
            // comment
            "url": "https://example.com/not-comment",
            "escaped": "quote: \\"",
            /*
              block comment
            */
            "items": [
              "a",
            ],
          }
        JSON
      )

      expect(described_class.validate_file(path)).to eq(true)
      expect(JSON.parse(described_class.strip(File.read(path)))).to eq(
        "url" => "https://example.com/not-comment",
        "escaped" => "quote: \"",
        "items" => ["a"]
      )
    end

    it "rejects invalid JSON after stripping comments" do
      path = write_file(Dir.mktmpdir, "bad.json", "{")

      expect { described_class.validate_file(path) }
        .to raise_error(Dotfiles::TestChecks::Error, /invalid JSON\/JSONC/)
    end

    it "rejects missing JSON files" do
      expect { described_class.validate_file("/missing/nope.json") }
        .to raise_error(Dotfiles::TestChecks::Error, /file not found/)
    end

    it "rejects unterminated block comments" do
      expect { described_class.strip("{ /* nope") }
        .to raise_error(Dotfiles::TestChecks::Error, /unterminated block comment/)
    end
  end

  describe Dotfiles::TestChecks::YAMLCheck do
    it "validates YAML files" do
      path = write_file(Dir.mktmpdir, "config.yml", "---\nkey: value\n")

      expect(described_class.validate_file(path)).to eq(true)
    end

    it "rejects invalid YAML" do
      path = write_file(Dir.mktmpdir, "bad.yml", "key: [")

      expect { described_class.validate_file(path) }
        .to raise_error(Dotfiles::TestChecks::Error, /invalid YAML/)
    end

    it "rejects missing YAML files" do
      expect { described_class.validate_file("/missing/nope.yml") }
        .to raise_error(Dotfiles::TestChecks::Error, /file not found/)
    end
  end

  describe Dotfiles::TestChecks::BundlerSupplyChain do
    def write_bundler_project(root, lock_text: minimal_lock, config: { "BUNDLE_FROZEN" => "true" }, cache_files: ["diff-lcs-1.6.2.gem"])
      write_file(root, ".bundle/config", YAML.dump(config))
      write_file(root, "Gemfile.lock", lock_text)
      cache_files.each { |name| write_file(root, "vendor/cache/#{name}", "gem") }
    end

    it "accepts frozen config, checksums, and exact cached gems" do
      root = Dir.mktmpdir
      write_bundler_project(root)

      expect(described_class.validate(root)).to eq(true)
    end

    it "reports unfrozen config, missing checksum section, and missing cached gems" do
      root = Dir.mktmpdir
      write_bundler_project(root, lock_text: minimal_lock(checksums: false), config: {}, cache_files: [])

      expect { described_class.validate(root) }
        .to raise_error(Dotfiles::TestChecks::Error) { |error|
          expect(error.message).to include(
            ".bundle/config must set BUNDLE_FROZEN",
            "Gemfile.lock is missing CHECKSUMS",
            "missing checksum for diff-lcs (1.6.2)",
            "missing cached gem: vendor/cache/diff-lcs-1.6.2.gem"
          )
        }
    end

    it "reports malformed checksum entries and extra cached gems" do
      root = Dir.mktmpdir
      write_bundler_project(root, lock_text: minimal_lock(checksum_line: "  nope"), cache_files: ["diff-lcs-1.6.2.gem", "extra-1.0.0.gem"])

      expect { described_class.validate(root) }
        .to raise_error(Dotfiles::TestChecks::Error) { |error|
          expect(error.message).to include(
            "invalid Gemfile.lock checksum line:   nope",
            "missing checksum for diff-lcs (1.6.2)",
            "extra cached gem: vendor/cache/extra-1.0.0.gem"
          )
        }
    end

    it "reports missing Bundler files" do
      expect { described_class.validate(Dir.mktmpdir) }
        .to raise_error(Dotfiles::TestChecks::Error, /No such file or directory/)
    end
  end

  describe Dotfiles::TestChecks::CIWorkflowActionPins do
    it "accepts SHA-pinned actions, Docker digests, and local actions" do
      root = Dir.mktmpdir
      write_file(root, ".github/workflows/test.yml", <<~YAML)
        jobs:
          test:
            steps:
              - uses: actions/checkout@#{'a' * 40}
              - uses: docker://alpine@sha256:#{'b' * 64}
              - uses: ./local-action
      YAML

      expect(described_class.validate(root)).to eq(true)
    end

    it "rejects unpinned workflow actions" do
      root = Dir.mktmpdir
      write_file(root, ".github/workflows/test.yml", <<~YAML)
        jobs:
          test:
            steps:
              - uses: actions/checkout@v6
              - uses: docker://alpine:latest
      YAML

      expect { described_class.validate(root) }
        .to raise_error(Dotfiles::TestChecks::Error) { |error|
          expect(error.message).to include(
            ".github/workflows/test.yml:4 action is not SHA-pinned: actions/checkout@v6",
            ".github/workflows/test.yml:5 action is not SHA-pinned: docker://alpine:latest"
          )
        }
    end
  end

  describe Dotfiles::TestChecks::VSCodeFixturePlan do
    def action(type, action, extra = {})
      { "type" => type, "action" => action }.merge(extra)
    end

    def valid_plan_json
      JSON.dump(
        "actions" => [
          action("extension", "update", "id" => "donjayamanne.githistory"),
          action("extension", "install", "id" => "hashicorp.terraform"),
          action("extension", "keep_auto_update", "id" => "openai.chatgpt"),
          action("extension", "keep_auto_update", "id" => "github.copilot-chat"),
          action("extension", "prune", "id" => "untracked.publisher"),
          action("storage", "configure", "key" => "extensions.autoUpdate", "desired" => ["github.copilot-chat", "github.vscode-github-actions", "openai.chatgpt"]),
          action("storage", "configure", "key" => "extensions.donotAutoUpdate", "desired" => ["donjayamanne.githistory"]),
          action("setting", "write", "key" => "extensions.allowed", "desired" => {
            "donjayamanne.githistory" => ["0.6.20"],
            "openai.chatgpt" => "stable",
            "github.copilot-chat" => "stable",
            "github.vscode-github-actions" => "stable"
          })
        ]
      )
    end

    it "accepts the expected VS Code fixture plan" do
      expect(described_class.validate(valid_plan_json)).to eq(true)
    end

    it "rejects invalid JSON" do
      expect { described_class.validate("{") }
        .to raise_error(Dotfiles::TestChecks::Error, /fixture plan is invalid JSON/)
    end

    it "rejects JSON without actions" do
      expect { described_class.validate("{}") }
        .to raise_error(Dotfiles::TestChecks::Error, /fixture plan is missing actions/)
    end

    it "reports the first failed fixture assertion" do
      bad_plan = JSON.parse(valid_plan_json)
      bad_plan.fetch("actions").reject! { |entry| entry["id"] == "hashicorp.terraform" }

      expect { described_class.validate(JSON.dump(bad_plan)) }
        .to raise_error(Dotfiles::TestChecks::Error, /fixture should install missing baseline extension/)
    end
  end

  describe Dotfiles::TestChecks::PublicSafety do
    it "accepts safe tracked files" do
      root = Dir.mktmpdir
      write_file(root, "README.md", "hello")

      expect(described_class.validate(root, tracked_files: ["README.md"])).to eq(true)
    end

    it "reports unexpected VS Code config and generated state paths" do
      root = Dir.mktmpdir

      expect {
        described_class.validate(root, tracked_files: [
          "configs/vsc/mcp.json",
          "configs/vsc/snippets/example.json",
          "Library/Application Support/Code/User/globalStorage/state.vscdb"
        ])
      }.to raise_error(Dotfiles::TestChecks::Error) { |error|
        expect(error.message).to include(
          "unexpected tracked VS Code config surface: configs/vsc/mcp.json",
          "sensitive generated path is tracked: Library/Application Support/Code/User/globalStorage/state.vscdb"
        )
        expect(error.message).not_to include("configs/vsc/snippets/example.json")
      }
    end

    it "reports secret-like file contents and ignores binary files" do
      root = Dir.mktmpdir
      write_file(root, "secret.txt", "token=#{'ghp_' + ('A' * 36)}")
      write_file(root, "binary.bin", "abc\x00#{'sk-' + ('B' * 32)}")

      expect { described_class.validate(root, tracked_files: ["secret.txt", "binary.bin"]) }
        .to raise_error(Dotfiles::TestChecks::Error, /possible committed secret pattern in secret.txt/)
    end

    it "uses git ls-files when tracked files are not provided" do
      root = Dir.mktmpdir
      write_file(root, "tracked.txt", "safe")
      Dir.chdir(root) do
        system("git", "init", "--quiet")
        system("git", "add", "tracked.txt")
      end

      expect(described_class.validate(root)).to eq(true)
    end
  end

  describe Dotfiles::TestChecks::CLI do
    def run_cli(args)
      out = StringIO.new
      err = StringIO.new
      status = described_class.new(argv: args, out: out, err: err).run
      [status, out.string, err.string]
    end

    it "runs file validation commands" do
      root = Dir.mktmpdir
      json = write_file(root, "ok.json", "{// comment\n\"ok\": true}\n")
      yaml = write_file(root, "ok.yml", "---\nok: true\n")

      expect(run_cli(["jsonc", json]).first).to eq(0)
      expect(run_cli(["yaml", yaml]).first).to eq(0)
    end

    it "runs repo validation commands" do
      expect(Dotfiles::TestChecks::BundlerSupplyChain).to receive(:validate).with("/repo")
      expect(Dotfiles::TestChecks::CIWorkflowActionPins).to receive(:validate).with("/repo")
      expect(Dotfiles::TestChecks::VSCodeFixturePlan).to receive(:validate).with("{}")
      expect(Dotfiles::TestChecks::PublicSafety).to receive(:validate).with("/repo")

      expect(run_cli(["bundler-supply-chain", "/repo"]).first).to eq(0)
      expect(run_cli(["ci-workflow-action-pins", "/repo"]).first).to eq(0)
      expect(run_cli(["vscode-fixture-plan", "{}"]).first).to eq(0)
      expect(run_cli(["public-safety", "/repo"]).first).to eq(0)
    end

    it "prints usage for help and unknown commands" do
      help_status, help_out, help_err = run_cli(["--help"])
      unknown_status, unknown_out, unknown_err = run_cli(["wat"])

      expect(help_status).to eq(0)
      expect(help_out).to include("Usage: script/test-check")
      expect(help_err).to eq("")
      expect(unknown_status).to eq(2)
      expect(unknown_out).to eq("")
      expect(unknown_err).to include("Usage: script/test-check")
    end

    it "reports missing arguments and validation failures" do
      missing_status, _out, missing_err = run_cli(["jsonc"])
      invalid_status, _invalid_out, invalid_err = run_cli(["jsonc", "/missing/nope.json"])

      expect(missing_status).to eq(1)
      expect(missing_err).to include("missing argument", "Usage: script/test-check")
      expect(invalid_status).to eq(1)
      expect(invalid_err).to include("file not found")
    end
  end
end
