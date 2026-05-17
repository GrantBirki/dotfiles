# frozen_string_literal: true

require_relative "manifest"

module Dotfiles
  class VSCExtensionWrapper
    attr_reader :argv, :out, :err, :runner

    def initialize(argv:, out: $stdout, err: $stderr, runner: Kernel)
      @argv = argv.dup
      @out = out
      @err = err
      @runner = runner
      @dry_run = false
      @prune = true
      @extensions_path = nil
    end

    def run
      parse_args!
      runner.exec(File.join(ROOT, "script/vscode"), *vscode_args)
    end

    private

    def parse_args!
      until argv.empty?
        arg = argv.shift
        case arg
        when "--dry-run", "-n"
          @dry_run = true
        when "--no-prune"
          @prune = false
        when "--help", "-h"
          err.print usage
          raise SystemExit, 0
        when /\A-/
          err.puts "Unknown option: #{arg}"
          err.print usage
          raise SystemExit, 2
        else
          @extensions_path = arg
          raise_usage!("Only one extension manifest path may be provided.") unless argv.empty?
        end
      end
    end

    def raise_usage!(message)
      err.puts message
      err.print usage
      raise SystemExit, 2
    end

    def vscode_args
      args = [@dry_run ? "plan" : "apply"]
      args << "--no-prune" unless @prune
      args.concat(["--extensions", @extensions_path]) if @extensions_path
      args
    end

    def usage
      <<~USAGE
        Usage: script/vsc-extension-bulk-install [--dry-run] [--no-prune] [path/to/extensions.yml]

        Compatibility wrapper around `script/vscode`.
      USAGE
    end
  end
end
