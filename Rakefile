require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
  t.warning = true
end

task :bench do
  ruby "--yjit -Ilib bench/pipeline.rb"
end

namespace :bench do
  desc "HTTP benchmark against Grape and a Rails controller (needs wrk)"
  task :http do
    Bundler.with_unbundled_env { ruby "bench/http/run.rb" }
  end
end

task default: :test
