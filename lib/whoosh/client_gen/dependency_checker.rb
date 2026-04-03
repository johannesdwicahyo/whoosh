# lib/whoosh/client_gen/dependency_checker.rb
# frozen_string_literal: true

module Whoosh
  module ClientGen
    class DependencyChecker
      DEPENDENCIES = {
        react_spa: [{ cmd: "node", check: "node --version", min_version: "18" }],
        expo: [
          { cmd: "node", check: "node --version", min_version: "18" },
          { cmd: "npx", check: "npx expo --version", min_version: nil }
        ],
        ios: [{ cmd: "xcodebuild", check: "xcodebuild -version", min_version: "15" }],
        flutter: [{ cmd: "flutter", check: "flutter --version", min_version: "3" }],
        htmx: [],
        telegram_bot: [{ cmd: "ruby", check: "ruby --version", min_version: "3.2" }],
        telegram_mini_app: [{ cmd: "node", check: "node --version", min_version: "18" }]
      }.freeze

      def self.check(client_type)
        deps = DEPENDENCIES[client_type.to_sym] || []
        return { ok: true, dependencies: [], missing: [] } if deps.empty?

        missing = []
        deps.each do |dep|
          output = `#{dep[:check]} 2>/dev/null`.strip
          if output.empty?
            missing << dep
          elsif dep[:min_version]
            version = output.scan(/(\d+)\./)[0]&.first
            if version && version.to_i < dep[:min_version].to_i
              missing << dep.merge(found_version: version)
            end
          end
        end

        {
          ok: missing.empty?,
          dependencies: deps.map { |d| d[:cmd] },
          missing: missing
        }
      end

      def self.dependency_for(client_type)
        DEPENDENCIES[client_type.to_sym] || []
      end
    end
  end
end
