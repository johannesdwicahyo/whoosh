# frozen_string_literal: true

module Whoosh
  class DependencyInjection
    def initialize
      @providers = {}
      @singletons = {}
      @mutex = Mutex.new
    end

    def provide(name, scope: :singleton, &block)
      @providers[name] = { block: block, scope: scope }
      @singletons.delete(name) # Clear cached value on re-register
    end

    def resolve(name, request: nil, resolving: [])
      provider = @providers[name]
      raise Errors::DependencyError, "Unknown dependency: #{name}" unless provider

      if resolving.include?(name)
        raise Errors::DependencyError, "Circular dependency detected: #{(resolving + [name]).join(' -> ')}"
      end

      case provider[:scope]
      when :singleton
        # Check cache without lock first (double-checked locking pattern)
        return @singletons[name] if @singletons.key?(name)

        # Compute outside the lock to allow recursive singleton resolution
        value = call_provider(provider[:block], request: request, resolving: resolving + [name])
        @mutex.synchronize { @singletons[name] ||= value }
        @singletons[name]
      when :request
        call_provider(provider[:block], request: request, resolving: resolving + [name])
      end
    end

    def inject_for(names, request: nil)
      names.each_with_object({}) do |name, hash|
        hash[name] = resolve(name, request: request)
      end
    end

    def validate!
      # Topological sort to detect circular deps and unknown refs at boot
      visited = {}
      sorted = []

      visit = ->(name, path) do
        return if visited[name] == :done
        raise Errors::DependencyError, "Circular dependency detected: #{(path + [name]).join(' -> ')}" if visited[name] == :visiting

        provider = @providers[name]
        raise Errors::DependencyError, "Unknown dependency: #{name} (referenced by #{path.last})" unless provider

        visited[name] = :visiting
        deps = extract_deps(provider[:block])
        deps.each { |dep| visit.call(dep, path + [name]) }
        visited[name] = :done
        sorted << name
      end

      @providers.each_key { |name| visit.call(name, []) unless visited[name] }
      sorted
    end

    def registered?(name)
      @providers.key?(name)
    end

    def close_all
      @singletons.each_value do |instance|
        instance.close if instance.respond_to?(:close)
      end
      @singletons.clear
    end

    private

    def extract_deps(block)
      block.parameters
        .select { |type, _| type == :keyreq || type == :key }
        .map(&:last)
    end

    def call_provider(block, request: nil, resolving: [])
      # Inspect block parameters to determine what to inject
      params = block.parameters
      kwargs = params.select { |type, _| type == :keyreq || type == :key }.map(&:last)

      if kwargs.any?
        deps = kwargs.each_with_object({}) do |dep_name, hash|
          hash[dep_name] = resolve(dep_name, request: request, resolving: resolving)
        end
        block.call(**deps)
      elsif params.any? { |type, _| type == :req || type == :opt }
        block.call(request)
      else
        block.call
      end
    end
  end
end
