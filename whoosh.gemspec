# frozen_string_literal: true

require_relative "lib/whoosh/version"

Gem::Specification.new do |spec|
  spec.name = "whoosh"
  spec.version = Whoosh::VERSION
  spec.authors = ["Johannes Dwi Cahyo"]
  spec.summary = "AI-first Ruby API framework"
  spec.description = "A fast, secure Ruby API framework inspired by FastAPI with built-in MCP support, auto-generated OpenAPI docs, and seamless AI gem ecosystem integration."
  spec.homepage = "https://github.com/johannesdwicahyo/whoosh"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4.0"

  spec.files = Dir["lib/**/*", "LICENSE", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["whoosh"]
  spec.require_paths = ["lib"]

  spec.add_dependency "base64", "~> 0.2"
  spec.add_dependency "rack", "~> 3.0"
  spec.add_dependency "dry-schema", "~> 1.13"
  spec.add_dependency "dry-types", "~> 1.7"
  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "rackup", "~> 2.1"
  spec.add_dependency "webrick", "~> 1.8"

  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "rack-test", "~> 2.1"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "benchmark-ips", "~> 2.13"
end
