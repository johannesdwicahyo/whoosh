# spec/whoosh/plugin_config_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"

RSpec.describe "Plugin config from plugins.yml" do
  it "loads plugin config from file" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config", "plugins.yml"), <<~YAML)
        lingua:
          languages: [en, id, ms]
        ner:
          enabled: false
      YAML

      app = Whoosh::App.new(root: dir)
      expect(app.plugin_registry.config_for(:lingua)).to eq({ "languages" => ["en", "id", "ms"] })
      expect(app.plugin_registry.disabled?(:ner)).to be true
    end
  end

  it "works without plugins.yml" do
    app = Whoosh::App.new(root: "/nonexistent")
    expect(app.plugin_registry).to be_a(Whoosh::Plugins::Registry)
  end
end
