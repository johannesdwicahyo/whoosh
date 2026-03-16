# lib/whoosh/performance.rb
# frozen_string_literal: true

module Whoosh
  module Performance
    def self.enable_yjit!
      return unless defined?(RubyVM::YJIT)
      RubyVM::YJIT.enable unless yjit_enabled?
    end

    def self.yjit_enabled?
      defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
    end

    def self.optimize!
      enable_yjit!
      Serialization::Json.detect_engine!
    end
  end
end
