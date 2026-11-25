module Whoosh
  # A segment tree built once at boot. Static segments win over parameters,
  # so `/orders/stats` and `/orders/:id` can coexist.
  class Router
    Node = Struct.new(:static, :param_name, :param_node, :endpoints) do
      def initialize = super({}, nil, nil, {})
    end

    PARAM_VALUE = %r{\A[^/]{1,512}\z}

    def initialize
      @root = Node.new
    end

    def add(verb, path, endpoint)
      node = @root
      segments(path).each do |segment|
        if segment.start_with?(":")
          name = segment.delete_prefix(":")
          if node.param_node && node.param_name != name
            raise DefinitionError, "#{verb} #{path}: :#{name} conflicts with :#{node.param_name} at the same position"
          end
          node.param_name = name
          node = (node.param_node ||= Node.new)
        else
          node = (node.static[segment] ||= Node.new)
        end
      end
      if node.endpoints.key?(verb)
        raise DefinitionError, "#{verb} #{path} is defined twice"
      end

      node.endpoints[verb] = endpoint
    end

    # Returns [endpoint, path_params], [:method_not_allowed, allowed_verbs] or nil.
    def match(verb, path)
      params = {}
      node = find(@root, segments(path), 0, params)
      return nil unless node && !node.endpoints.empty?

      verb = "GET" if verb == "HEAD"
      endpoint = node.endpoints[verb]
      endpoint ? [endpoint, params] : [:method_not_allowed, node.endpoints.keys]
    end

    def routes
      collect(@root, "", [])
    end

    private

    def find(node, segs, index, params)
      return(node.endpoints.empty? ? nil : node) if index == segs.size

      segment = segs[index]
      if (child = node.static[segment]) && (found = find(child, segs, index + 1, params))
        return found
      end
      if node.param_node && segment.match?(PARAM_VALUE)
        found = find(node.param_node, segs, index + 1, params)
        if found
          params[node.param_name] = unescape(segment)
          return found
        end
      end
      nil
    end

    def unescape(segment)
      return segment unless segment.include?("%")

      value = URI.decode_www_form_component(segment.gsub("+", "%2B"))
      value.valid_encoding? ? value : segment
    rescue ArgumentError
      segment
    end

    def segments(path)
      path.to_s.split("/").reject(&:empty?)
    end

    def collect(node, prefix, out)
      node.endpoints.each { |verb, ep| out << [verb, prefix.empty? ? "/" : prefix, ep] }
      node.static.each { |seg, child| collect(child, "#{prefix}/#{seg}", out) }
      collect(node.param_node, "#{prefix}/:#{node.param_name}", out) if node.param_node
      out
    end
  end
end
