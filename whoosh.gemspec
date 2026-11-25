require_relative "lib/whoosh/version"

Gem::Specification.new do |spec|
  spec.name        = "whoosh"
  spec.version     = Whoosh::VERSION
  spec.authors     = ["Johannes Dwi Cahyo Kristanto"]
  spec.email       = [] # TODO: the address you want public on RubyGems
  spec.summary     = "An opinionated, secure-by-default JSON API framework for Rack: standalone or mounted in Rails, Sinatra, Hanami."
  spec.description = <<~DESC
    Whoosh is a small JSON API framework built straight on the Rack spec.
    Endpoints are deny-by-default: every one must declare who may call it,
    what input it accepts and what output it returns, or the app refuses to
    boot. It ships one error envelope, request IDs, body and page-size limits,
    rate limiting, idempotency keys, cursor pagination, CORS and security
    headers, and generates OpenAPI from the same schemas. Its only runtime
    dependency is bigdecimal.
  DESC
  spec.homepage = "https://github.com/johannesdwicahyo/whoosh" # TODO: confirm
  spec.license  = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "bigdecimal" # bundled gem since Ruby 3.4; Rails already depends on it
end
