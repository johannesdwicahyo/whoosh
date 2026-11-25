require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
  t.warning = true
end

task :bench do
  ruby "--yjit -Ilib bench/pipeline.rb"
end

task default: :test
