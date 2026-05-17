# frozen_string_literal: true

require "spec_helper"
require_relative "../../lib/dotfiles/doctor"
require_relative "../../lib/dotfiles/installer"
require_relative "../../lib/dotfiles/restorer"
require_relative "../../lib/dotfiles/test_checks"
require_relative "../../lib/dotfiles/vendor"
require_relative "../../lib/dotfiles/vsc_extension_wrapper"

RSpec.describe "Ruby script entrypoints" do
  it "runs script/install through Dotfiles::Installer" do
    runner = instance_double(Dotfiles::Installer, run: 7)
    expect(Dotfiles::Installer).to receive(:new).with(argv: ["--dry-run"]).and_return(runner)

    result = run_script(File.join(ROOT, "script/install"), ["--dry-run"])

    expect(result).to include(status: 7)
  end

  it "runs script/restore through Dotfiles::Restorer" do
    runner = instance_double(Dotfiles::Restorer, run: 3)
    expect(Dotfiles::Restorer).to receive(:new).with(argv: ["--state", "x"]).and_return(runner)

    result = run_script(File.join(ROOT, "script/restore"), ["--state", "x"])

    expect(result).to include(status: 3)
  end

  it "runs script/doctor through Dotfiles::Doctor" do
    runner = instance_double(Dotfiles::Doctor, run: 2)
    expect(Dotfiles::Doctor).to receive(:new).with(argv: []).and_return(runner)

    result = run_script(File.join(ROOT, "script/doctor"))

    expect(result).to include(status: 2)
  end

  it "runs script/vendor through Dotfiles::Vendor" do
    runner = instance_double(Dotfiles::Vendor, run: 4)
    expect(Dotfiles::Vendor).to receive(:new).with(argv: ["--dry-run"]).and_return(runner)

    result = run_script(File.join(ROOT, "script/vendor"), ["--dry-run"])

    expect(result).to include(status: 4)
  end

  it "runs script/test-check through Dotfiles::TestChecks::CLI" do
    runner = instance_double(Dotfiles::TestChecks::CLI, run: 5)
    expect(Dotfiles::TestChecks::CLI).to receive(:new).with(argv: ["--help"]).and_return(runner)

    result = run_script(File.join(ROOT, "script/test-check"), ["--help"])

    expect(result).to include(status: 5)
  end

  it "runs script/vsc-extension-bulk-install through the wrapper" do
    runner = instance_double(Dotfiles::VSCExtensionWrapper, run: true)
    expect(Dotfiles::VSCExtensionWrapper).to receive(:new).with(argv: ["--dry-run"]).and_return(runner)

    result = run_script(File.join(ROOT, "script/vsc-extension-bulk-install"), ["--dry-run"])

    expect(result).to include(status: 0)
  end
end
