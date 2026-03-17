# spec/whoosh/cli/reload_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "whoosh/cli/main"

RSpec.describe "CLI server --reload" do
  it "has reload option" do
    cmd = Whoosh::CLI::Main.all_commands["server"]
    expect(cmd.options.keys).to include(:reload)
  end
end
