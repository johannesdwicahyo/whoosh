# frozen_string_literal: true

module Whoosh
  class Database
    @sequel_available = nil

    def self.available?
      if @sequel_available.nil?
        @sequel_available = begin
          require "sequel"
          true
        rescue LoadError
          false
        end
      end
      @sequel_available
    end

    def self.connect(url, max_connections: 10, log_level: nil)
      ensure_available!
      db = Sequel.connect(url, max_connections: max_connections)
      db.loggers << ::Logger.new($stdout) if log_level == "debug"
      db
    end

    def self.connect_from_config(config_data, logger: nil)
      db_config = config_from(config_data)
      return nil unless db_config
      ensure_available!
      connect(db_config[:url], max_connections: db_config[:max_connections], log_level: db_config[:log_level])
    end

    def self.config_from(config_data)
      db_config = config_data["database"]
      return nil unless db_config && db_config["url"]
      {
        url: db_config["url"],
        max_connections: db_config["max_connections"] || 10,
        log_level: db_config["log_level"]
      }
    end

    def self.ensure_available!
      raise Errors::DependencyError, "Database requires the 'sequel' gem" unless available?
    end
  end
end
