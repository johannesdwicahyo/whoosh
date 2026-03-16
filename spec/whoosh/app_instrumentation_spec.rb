# spec/whoosh/app_instrumentation_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack/test"

RSpec.describe "App instrumentation" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  it "emits error events on unhandled exceptions" do
    errors = []
    application.on_event(:error) { |data| errors << data }

    application.get "/boom" do
      raise "explosion"
    end

    get "/boom"
    expect(last_response.status).to eq(500)
    expect(errors.length).to eq(1)
    expect(errors.first[:error].message).to eq("explosion")
  end

  it "provides instrumentation instance" do
    expect(application.instrumentation).to be_a(Whoosh::Instrumentation)
  end
end
