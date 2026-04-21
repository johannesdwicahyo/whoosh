# spec/edge_cases/middleware_streaming_config_edge_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "tmpdir"

RSpec.describe "Middleware edge cases" do
  it "applies middleware in correct order" do
    order = []
    mw1 = Class.new { define_method(:initialize) { |app| @app = app }; define_method(:call) { |env| order << :first; @app.call(env) } }
    mw2 = Class.new { define_method(:initialize) { |app| @app = app }; define_method(:call) { |env| order << :second; @app.call(env) } }

    stack = Whoosh::Middleware::Stack.new
    stack.use(mw1)
    stack.use(mw2)
    app = stack.build(->(env) { [200, {}, ["ok"]] })
    app.call(Rack::MockRequest.env_for("/"))
    expect(order).to eq([:first, :second])
  end

  it "RequestLimit allows GET without content-length" do
    app = Whoosh::Middleware::RequestLimit.new(->(env) { [200, {}, ["ok"]] }, max_bytes: 10)
    status, _, _ = app.call(Rack::MockRequest.env_for("/test"))
    expect(status).to eq(200)
  end

  it "CORS handles missing Origin gracefully" do
    app = Whoosh::Middleware::Cors.new(->(env) { [200, {}, ["ok"]] })
    _, headers, _ = app.call(Rack::MockRequest.env_for("/test"))
    expect(headers["access-control-allow-origin"]).to be_nil
  end
end

RSpec.describe "Streaming edge cases" do
  it "SSE ignores writes after close" do
    io = StringIO.new
    sse = Whoosh::Streaming::SSE.new(io)
    sse.close
    sse << "ignored"
    io.rewind
    expect(io.read).not_to include("ignored")
  end

  it "SSE handles event with nil data" do
    io = StringIO.new
    sse = Whoosh::Streaming::SSE.new(io)
    sse.event("test", nil)
    io.rewind
    expect(io.read).to include("event: test")
  end

  it "LlmStream ignores writes after finish" do
    io = StringIO.new
    stream = Whoosh::Streaming::LlmStream.new(io)
    stream.finish
    stream << "ignored"
    io.rewind
    expect(io.read).not_to include("ignored")
  end

  it "LlmStream skips empty string chunks (avoids noisy tool-call preludes)" do
    io = StringIO.new
    stream = Whoosh::Streaming::LlmStream.new(io)
    stream << ""
    io.rewind
    expect(io.read).to eq("")
  end
end

RSpec.describe "Config edge cases" do
  it "handles empty YAML file" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config", "app.yml"), "")
      config = Whoosh::Config.load(root: dir)
      expect(config.port).to eq(9292)
    end
  end

  it "handles YAML with only comments" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config", "app.yml"), "# just a comment\n")
      config = Whoosh::Config.load(root: dir)
      expect(config.port).to eq(9292)
    end
  end
end
