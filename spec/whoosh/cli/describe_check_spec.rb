# frozen_string_literal: true

require "spec_helper"
require "whoosh/cli/main"

RSpec.describe "CLI describe and check commands" do
  it "has describe command" do
    expect(Whoosh::CLI::Main.all_commands).to have_key("describe")
  end

  it "has check command" do
    expect(Whoosh::CLI::Main.all_commands).to have_key("check")
  end
end
