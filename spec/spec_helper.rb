# frozen_string_literal: true

require "coverage"

ROOT = File.expand_path("..", __dir__)
COVERAGE_TARGETS = (
  Dir[File.join(ROOT, "lib/dotfiles/*.rb")] +
  %w[
    script/doctor
    script/install
    script/manifest
    script/restore
    script/test-check
    script/vendor
    script/vsc-extension-bulk-install
    script/vscode
  ].map { |path| File.join(ROOT, path) }
).map { |path| File.realpath(path) }.freeze

Coverage.start(lines: true)

require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require "yaml"

require "rspec"

SCRIPT_COVERAGE = {}

module ScriptRunner
  def run_script(path, argv = [])
    original_argv = ARGV.dup
    original_stdout = $stdout
    original_stderr = $stderr
    stdout = StringIO.new
    stderr = StringIO.new
    status = 0

    ARGV.replace(argv)
    $stdout = stdout
    $stderr = stderr

    begin
      load path
    rescue SystemExit => e
      status = e.status
    ensure
      record_script_coverage(path)
      ARGV.replace(original_argv)
      $stdout = original_stdout
      $stderr = original_stderr
    end

    {
      status: status,
      stdout: stdout.string,
      stderr: stderr.string
    }
  end

  def record_script_coverage(path)
    normalized_target = File.realpath(path)
    coverage = Coverage.peek_result
    coverage.each do |coverage_path, data|
      normalized_path = File.realpath(coverage_path)
      next unless normalized_path == normalized_target

      lines = data.is_a?(Hash) ? data.fetch(:lines) : data
      aggregate_lines(normalized_path, lines)
    rescue Errno::ENOENT
      next
    end
  end

  def aggregate_lines(path, lines)
    aggregate = SCRIPT_COVERAGE[path] ||= []
    lines.each_with_index do |count, index|
      next if count.nil?

      aggregate[index] = aggregate[index].to_i + count
    end
  end
end

RSpec.configure do |config|
  config.include ScriptRunner
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }

  config.after(:suite) do
    result = Coverage.result
    coverage_by_path = result.to_h do |path, data|
      normalized = File.realpath(path)
      lines = data.is_a?(Hash) ? data.fetch(:lines) : data
      [normalized, lines]
    rescue Errno::ENOENT
      [File.expand_path(path), data.is_a?(Hash) ? data.fetch(:lines) : data]
    end
    SCRIPT_COVERAGE.each do |path, lines|
      coverage_by_path[path] = lines
    end

    uncovered = []
    COVERAGE_TARGETS.each do |path|
      lines = coverage_by_path[path]
      unless lines
        uncovered << "#{path}: not loaded by specs"
        next
      end

      File.readlines(path).each_with_index do |_source_line, index|
        count = lines[index]
        next if count.nil? || count.positive?

        uncovered << "#{path}:#{index + 1}"
      end
    end

    next if uncovered.empty?

    warn "\nRuby line coverage is below 100%:"
    warn uncovered.join("\n")
    exit 1
  end
end
