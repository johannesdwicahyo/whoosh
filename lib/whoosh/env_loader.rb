# lib/whoosh/env_loader.rb
# frozen_string_literal: true

module Whoosh
  module EnvLoader
    def self.load(root)
      path = File.join(root, ".env")
      return unless File.exist?(path)

      if dotenv_available?
        require "dotenv"
        Dotenv.load(path)
        return
      end

      parse(File.read(path)).each do |key, value|
        ENV[key] ||= value
      end
    end

    def self.parse(content)
      pairs = {}
      content.each_line do |line|
        line = line.strip
        next if line.empty? || line.start_with?("#")
        key, value = line.split("=", 2)
        next unless key && value
        key = key.strip
        value = value.strip
        if (value.start_with?('"') && value.end_with?('"')) ||
           (value.start_with?("'") && value.end_with?("'"))
          value = value[1..-2]
        end
        pairs[key] = value
      end
      pairs
    end

    def self.dotenv_available?
      require "dotenv"
      true
    rescue LoadError
      false
    end
  end
end
