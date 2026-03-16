# frozen_string_literal: true

module Whoosh
  class Router
    class TrieNode
      attr_accessor :handlers, :children, :param_name, :is_param

      def initialize
        @children = {}
        @handlers = {}
        @param_name = nil
        @is_param = false
      end
    end

    def initialize
      @root = TrieNode.new
      @routes = []
      @frozen = false
    end

    def add(method, path, handler, **metadata)
      raise "Router is frozen — cannot add routes after boot" if @frozen

      node = @root
      segments = split_path(path)

      segments.each do |segment|
        if segment.start_with?(":")
          child = node.children[:_param] ||= TrieNode.new
          child.is_param = true
          child.param_name = segment[1..].to_sym
          node = child
        else
          node = node.children[segment] ||= TrieNode.new
        end
      end

      node.handlers[method] = { handler: handler, metadata: metadata }
      @routes << { method: method, path: path, handler: handler, metadata: metadata }
    end

    def match(method, path)
      # Trailing slash (e.g. "/health/") is treated as a distinct path from "/health"
      return nil if path.end_with?("/") && path != "/"

      node = @root
      params = {}
      segments = split_path(path)

      segments.each do |segment|
        if node.children[segment]
          node = node.children[segment]
        elsif node.children[:_param]
          node = node.children[:_param]
          params[node.param_name] = segment
        else
          return nil
        end
      end

      entry = node.handlers[method]
      return nil unless entry

      { handler: entry[:handler], params: params, metadata: entry[:metadata] }
    end

    def routes
      @routes.map do |route|
        { method: route[:method], path: route[:path], metadata: route[:metadata] }
      end
    end

    def freeze!
      @frozen = true
    end

    private

    def split_path(path)
      path.split("/").reject(&:empty?)
    end
  end
end
