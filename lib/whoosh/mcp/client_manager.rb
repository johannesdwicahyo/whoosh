# frozen_string_literal: true

module Whoosh
  module MCP
    class ClientManager
      def initialize
        @configs = {}
        @clients = {}
        @mutex = Mutex.new
      end

      def register(name, command:, **options)
        @configs[name] = { command: command, **options }
      end

      def registered?(name)
        @configs.key?(name)
      end

      def configs
        @configs.dup
      end

      def set_client(name, client)
        @mutex.synchronize { @clients[name] = client }
      end

      def get_client(name)
        @mutex.synchronize { @clients[name] }
      end

      def shutdown_all
        @mutex.synchronize do
          @clients.each_value { |c| c.close if c.respond_to?(:close) }
          @clients.clear
        end
      end
    end
  end
end
