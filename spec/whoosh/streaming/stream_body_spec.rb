# spec/whoosh/streaming/stream_body_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe Whoosh::Streaming::StreamBody do
  it "yields chunks from producer" do
    body = Whoosh::Streaming::StreamBody.new do |out|
      out.write("chunk1")
      out.write("chunk2")
    end

    chunks = []
    body.each { |c| chunks << c }
    expect(chunks).to eq(["chunk1", "chunk2"])
  end

  it "handles producer errors gracefully" do
    body = Whoosh::Streaming::StreamBody.new do |out|
      out.write("before")
      raise "producer crash"
    end

    chunks = []
    body.each { |c| chunks << c }
    expect(chunks).to eq(["before"])
  end

  it "supports close" do
    body = Whoosh::Streaming::StreamBody.new do |out|
      out.write("data")
    end
    expect { body.close }.not_to raise_error
  end
end

RSpec.describe Whoosh::Streaming::QueueWriter do
  it "writes to queue" do
    q = SizedQueue.new(10)
    writer = Whoosh::Streaming::QueueWriter.new(q)
    writer.write("hello")
    expect(q.pop).to eq("hello")
  end

  it "ignores writes after close" do
    q = SizedQueue.new(10)
    writer = Whoosh::Streaming::QueueWriter.new(q)
    writer.close
    writer.write("ignored")
    expect(q.size).to eq(0)
  end

  it "responds to flush" do
    q = SizedQueue.new(10)
    writer = Whoosh::Streaming::QueueWriter.new(q)
    expect { writer.flush }.not_to raise_error
  end
end
