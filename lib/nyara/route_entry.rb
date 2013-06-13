module Nyara
  class RouteEntry
    REQUIRED_ATTRS = [:http_method, :scope, :prefix, :suffix, :controller, :id, :conv]
    attr_accessor *REQUIRED_ATTRS

    # optional
    attr_accessor :accept_exts, :accept_mimes

    # tmp
    attr_accessor :path, :blk

    def initialize &p
      instance_eval &p if p
    end

    def set_accept_exts a
      @accept_exts = {}
      @accept_mimes = []
      if a
        a.each do |e|
          e = e.to_s.dup.freeze
          @accept_exts[e] = true
          if MIME_TYPES[e]
            v1, v2 = MIME_TYPES[e].split('/')
            raise "bad mime type: #{MIME_TYPES[e].inspect}" if v1.nil? or v2.nil?
            @accept_mimes << [v1, v2, e]
          end
        end
      end
      @accept_mimes = nil if @accept_mimes.empty?
      @accept_exts = nil if @accept_exts.empty?
    end

    def validate
      REQUIRED_ATTRS.each do |attr|
        unless instance_variable_get("@#{attr}")
          raise ArgumentError, "missing #{attr}"
        end
      end
      raise ArgumentError, "id must be symbol" unless id.is_a?(Symbol)
    end
  end
end
