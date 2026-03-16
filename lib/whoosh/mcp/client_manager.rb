# frozen_string_literal: true

require "open3"
require "json"

module Whoosh
  module MCP
    class ClientManager
      def initialize
        @configs = {}
        @clients = {}
        @pids = {}
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

      def spawn_client(name)
        config = @configs[name]
        raise Whoosh::Errors::DependencyError, "Unknown MCP client: #{name}" unless config

        stdin, stdout, stderr, wait_thr = Open3.popen3(config[:command])

        client = Client.new(stdin: stdin, stdout: stdout)

        @mutex.synchronize do
          @clients[name] = client
          @pids[name] = { pid: wait_thr.pid, thread: wait_thr, stderr: stderr }
        end

        client
      end

      def pids
        @mutex.synchronize { @pids.transform_values { |v| v[:pid] } }
      end

      def shutdown_all
        @mutex.synchronize do
          @clients.each_value { |c| c.close if c.respond_to?(:close) }
          @pids.each_value do |info|
            begin
              Process.kill("TERM", info[:pid])
              info[:thread]&.join(5)
            rescue Errno::ESRCH, Errno::ECHILD
            end
            info[:stderr]&.close rescue nil
          end
          @clients.clear
          @pids.clear
        end
      end
    end
  end
end
