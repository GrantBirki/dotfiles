# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/dotfiles/manifest"

RSpec.describe "script/manifest" do
  let(:script_path) { File.join(ROOT, "script/manifest") }
  let(:entry_data) do
    {
      "id" => "bashrc",
      "source_path" => "/repo/dotfiles/.bashrc",
      "target_path" => "/home/user/.bashrc",
      "backup_path" => "/home/user/dotfiles_old/.bashrc",
      "target_parent" => "/home/user",
      "parent" => "create",
      "mode" => "symlink",
      "compare" => "exact",
      "optional" => false,
      "active" => true
    }
  end
  let(:entry) { instance_double(Dotfiles::Entry, to_h: entry_data, active?: true) }
  let(:manifest) { instance_double(Dotfiles::Manifest, validate!: true, entries: [entry]) }

  before do
    allow(Dotfiles::Manifest).to receive(:load).and_return(manifest)
  end

  it "validates by default" do
    result = run_script(script_path)

    expect(result).to include(status: 0)
    expect(result.fetch(:stdout)).to eq("Manifest OK.\n")
    expect(manifest).to have_received(:validate!)
  end

  it "validates explicitly" do
    result = run_script(script_path, ["validate"])

    expect(result).to include(status: 0)
    expect(result.fetch(:stdout)).to eq("Manifest OK.\n")
  end

  it "prints JSON entries" do
    result = run_script(script_path, ["json"])

    expect(result).to include(status: 0)
    expect(JSON.parse(result.fetch(:stdout))).to eq([entry_data])
  end

  it "prints tab-separated install entries" do
    result = run_script(script_path, ["entries"])

    expect(result).to include(status: 0)
    expect(result.fetch(:stdout)).to eq(
      "bashrc\t/repo/dotfiles/.bashrc\t/home/user/.bashrc\t" \
      "/home/user/dotfiles_old/.bashrc\t/home/user\tcreate\tsymlink\texact\n"
    )
  end

  it "skips inactive optional install entries" do
    inactive_entry = instance_double(Dotfiles::Entry, to_h: entry_data.merge("id" => "mcp"), active?: false)
    allow(manifest).to receive(:entries).and_return([inactive_entry])

    result = run_script(script_path, ["entries"])

    expect(result).to include(status: 0)
    expect(result.fetch(:stdout)).to eq("")
  end

  it "exits with usage for unknown commands" do
    result = run_script(script_path, ["wat"])

    expect(result).to include(status: 2)
    expect(result.fetch(:stderr)).to eq("Usage: script/manifest [validate|json|entries]\n")
  end

  it "exits with manifest errors" do
    allow(manifest).to receive(:validate!).and_raise(Dotfiles::Error, "broken manifest")

    result = run_script(script_path, ["validate"])

    expect(result).to include(status: 1)
    expect(result.fetch(:stderr)).to eq("broken manifest\n")
  end
end
