# frozen_string_literal: true

require "yaml"
require "erb"

module Whoosh
  class Config
    DEFAULTS = {
      "app" => {
        "name" => "Whoosh App",
        "env" => "development",
        "port" => 9292,
        "host" => "localhost"
      },
      "server" => {
        "type" => "falcon",
        "workers" => "auto",
        "timeout" => 30
      },
      "logging" => {
        "level" => "info",
        "format" => "json"
      },
      "docs" => {
        "enabled" => true
      },
      "performance" => {
        "yjit" => true,
        "yjit_exec_mem" => 64
      }
    }.freeze

    ENV_MAP = {
      "WHOOSH_PORT" => ["app", "port"],
      "WHOOSH_HOST" => ["app", "host"],
      "WHOOSH_ENV" => ["app", "env"],
      "WHOOSH_LOG_LEVEL" => ["logging", "level"],
      "WHOOSH_LOG_FORMAT" => ["logging", "format"]
    }.freeze

    attr_accessor :json_engine
    attr_reader :data

    def self.load(root:)
      new(root: root)
    end

    def initialize(root:)
      @data = deep_dup(DEFAULTS)
      @root = root
      @json_engine = :json

      load_yaml
      apply_env
    end

    def port
      @data.dig("app", "port")
    end

    def port=(value)
      @data["app"]["port"] = value.to_i
    end

    def host
      @data.dig("app", "host")
    end

    def host=(value)
      @data["app"]["host"] = value
    end

    def env
      @data.dig("app", "env")
    end

    def app_name
      @data.dig("app", "name")
    end

    def server_type
      @data.dig("server", "type")
    end

    def log_level
      @data.dig("logging", "level")
    end

    def log_format
      @data.dig("logging", "format")
    end

    def docs_enabled?
      @data.dig("docs", "enabled")
    end

    def shutdown_timeout
      @data.dig("server", "timeout") || 30
    end

    def development?
      env == "development"
    end

    def production?
      env == "production"
    end

    def test?
      env == "test"
    end

    private

    def load_yaml
      path = File.join(@root, "config", "app.yml")
      return unless File.exist?(path)

      content = ERB.new(File.read(path)).result
      yaml = YAML.safe_load(content, permitted_classes: [Symbol]) || {}
      deep_merge!(@data, yaml)
    end

    def apply_env
      ENV_MAP.each do |env_key, path|
        value = ENV[env_key]
        next unless value

        target = @data
        path[0...-1].each { |key| target = target[key] ||= {} }
        target[path.last] = coerce_value(value, @data.dig(*path))
      end
    end

    def coerce_value(value, existing)
      case existing
      when Integer then value.to_i
      when Float then value.to_f
      when TrueClass, FalseClass then %w[true 1 yes].include?(value.downcase)
      else value
      end
    end

    def deep_dup(hash)
      hash.each_with_object({}) do |(k, v), result|
        result[k] = v.is_a?(Hash) ? deep_dup(v) : v
      end
    end

    def deep_merge!(target, source)
      source.each do |key, value|
        if value.is_a?(Hash) && target[key].is_a?(Hash)
          deep_merge!(target[key], value)
        else
          target[key] = value
        end
      end
    end
  end
end
