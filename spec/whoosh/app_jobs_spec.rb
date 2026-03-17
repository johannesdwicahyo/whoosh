# spec/whoosh/app_jobs_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "rack/test"

class AppJobTestJob < Whoosh::Job
  def perform(value:)
    { result: value * 2 }
  end
end

RSpec.describe "App jobs integration" do
  include Rack::Test::Methods

  let(:application) { Whoosh::App.new }
  def app = application.to_rack

  before do
    application.get "/enqueue" do |req|
      job_id = AppJobTestJob.perform_async(value: 21)
      { job_id: job_id }
    end
  end

  it "enqueues jobs from endpoints" do
    get "/enqueue"
    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)["job_id"]).to match(/\A[a-f0-9-]+\z/)
  end

  it "configures Jobs at boot" do
    app
    expect(Whoosh::Jobs.configured?).to be true
  end

  it "workers process jobs" do
    app
    job_id = AppJobTestJob.perform_async(value: 10)
    sleep 0.5  # Give worker thread time to process

    record = Whoosh::Jobs.find(job_id)
    expect(record[:status]).to eq(:completed)
    expect(record[:result]).to eq({ "result" => 20 })
  end
end
