module Nyara
  class RouteEntry
    REQUIRED_ATTRS = [:http_method, :scope, :prefix, :suffix, :controller, :id, :conv]
    attr_reader *REQUIRED_ATTRS
    attr_writer :http_method, :id
    # NOTE `id` is stored in symbol for C-side conenience, but returns as string for Ruby-side goodness
    def id
      @id.to_s
    end

    # optional
    attr_accessor :accept_exts, :accept_mimes

    # @private
    attr_accessor :path, :blk

    def initialize &p
      instance_eval &p if p
    end

    def path_template
      File.join @scope, (@path.gsub '%z', '%s')
    end

    # Compute prefix, suffix, conv<br>
    # NOTE route_entries may be inherited, so late-setting controller is necessary
    def compile controller, scope
      @controller = controller
      @scope = scope

      path = scope.sub /\/?$/, @path
      if path.empty?
        path = '/'
      end
      @prefix, suffix = analyse_path path
      @suffix, @conv = compile_re suffix
    end

    # Compute accept_exts, accept_mimes
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
      raise ArgumentError, "id must be symbol" unless @id.is_a?(Symbol)
    end

    # ---
    # private
    # +++

    # #### Returns
    #
    #     [str_re, conv]
    #
    def compile_re suffix
      return ['', []] unless suffix
      conv = []
      re_segs = suffix.split(/(?<=%[dfsuxz])|(?=%[dfsuxz])/).map do |s|
        case s
        when '%d'
          conv << :to_i
          '(-?[0-9]+)'
        when '%f'
          conv << :to_f
          # just copied from scanf
          '([-+]?(?:0[xX](?:\.\h+|\h+(?:\.\h*)?)[pP][-+]\d+|\d+(?![\d.])|\d*\.\d*(?:[eE][-+]?\d+)?))'
        when '%u'
          conv << :to_i
          '([0-9]+)'
        when '%x'
          conv << :hex
          '(\h+)'
        when '%s'
          conv << :to_s
          '([^/]+)'
        when '%z'
          conv << :to_s
          '(.*)'
        else
          Regexp.quote s
        end
      end
      ["^#{re_segs.join}$", conv]
    end

    # Split the path into 2 parts: <br>
    # a fixed prefix and a variable suffix
    def analyse_path path
      raise 'path must contain no new line' if path.index "\n"
      raise 'path must start with /' unless path.start_with? '/'
      path = path.sub(/\/$/, '') if path != '/'

      path.split(/(?=%[dfsuxz])/, 2)
    end
  end
end
