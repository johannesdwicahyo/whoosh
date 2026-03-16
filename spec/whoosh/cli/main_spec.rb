# frozen_string_literal: true

require "spec_helper"
require "whoosh/cli/main"

RSpec.describe Whoosh::CLI::Main do
  describe "version" do
    it "prints the version" do
      output = capture_output { Whoosh::CLI::Main.start(["version"]) }
      expect(output).to include(Whoosh::VERSION)
    end
  end

  describe "registered commands" do
    it "has server command" do
      expect(Whoosh::CLI::Main.all_commands).to have_key("server")
    end

    it "has routes command" do
      expect(Whoosh::CLI::Main.all_commands).to have_key("routes")
    end

    it "has console command" do
      expect(Whoosh::CLI::Main.all_commands).to have_key("console")
    end

    it "has mcp command" do
      expect(Whoosh::CLI::Main.all_commands).to have_key("mcp")
    end

    it "has new command" do
      expect(Whoosh::CLI::Main.all_commands).to have_key("new")
    end
  end

  private

  def capture_output
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
