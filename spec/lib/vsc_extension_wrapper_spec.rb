# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/dotfiles/vsc_extension_wrapper"

RSpec.describe Dotfiles::VSCExtensionWrapper do
  let(:runner) { double("runner") }

  def run_wrapper(args)
    stdout = StringIO.new
    stderr = StringIO.new
    wrapper = described_class.new(argv: args, out: stdout, err: stderr, runner: runner)
    [wrapper.run, stdout.string, stderr.string]
  end

  it "execs script/vscode with apply by default" do
    expect(runner).to receive(:exec).with(File.join(Dotfiles::ROOT, "script/vscode"), "apply").and_return(true)

    result, stdout, stderr = run_wrapper([])

    expect(result).to eq(true)
    expect(stdout).to eq("")
    expect(stderr).to eq("")
  end

  it "translates dry-run, no-prune, and custom manifest options" do
    expect(runner).to receive(:exec)
      .with(File.join(Dotfiles::ROOT, "script/vscode"), "plan", "--no-prune", "--extensions", "custom.yml")
      .and_return(true)

    expect(run_wrapper(["--dry-run", "--no-prune", "custom.yml"]).first).to eq(true)
  end

  it "prints usage and exits for help or invalid arguments" do
    expect do
      run_wrapper(["--help"])
    end.to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }

    expect do
      run_wrapper(["--wat"])
    end.to raise_error(SystemExit) { |error| expect(error.status).to eq(2) }

    expect do
      run_wrapper(["one.yml", "two.yml"])
    end.to raise_error(SystemExit) { |error| expect(error.status).to eq(2) }
  end
end
