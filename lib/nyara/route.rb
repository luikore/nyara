module Nyara
  class Route
    REQUIRED_ATTRS = [:http_method, :scope, :prefix, :suffix, :controller, :id, :conv]
    attr_reader *REQUIRED_ATTRS
    attr_writer :http_method, :id
    # NOTE `id` is stored in symbol for C-side conenience, but returns as string for Ruby-side goodness
    def id
      @id.to_s
    end

    # optional
    attr_accessor :accept_exts, :accept_mimes, :classes

    # @private
    attr_accessor :path, :blk

    def initialize &p
      instance_eval &p if p
    end

    # http_method in string form
    def http_method_to_s
      m, _ = HTTP_METHODS.find{|k,v| v == http_method}
      m
    end

    # nil for get / post
    def http_method_override
      m = http_method_to_s
      if m != 'GET' and m != 'POST'
        m
      end
    end

    # enum all combinations of matching selectors
    def selectors
      if classes
        [id, *classes, *classes.map{|k| "#{k}:#{http_method_to_s}"}, ":#{http_method_to_s}"]
      else
        [id, ":#{http_method_to_s}"]
      end
    end

    # find blocks in filters that match selectors
    def matched_lifecycle_callbacks filters
      actions = []
      selectors = selectors()
      if selectors and filters
        # iterate with filter's order to preserve define order
        filters.each do |sel, blks|
          actions.concat blks if selectors.include?(sel)
        end
      end
      actions
    end

    def path_template
      File.join @scope, (@path.gsub '%z', '%s')
    end

    # Compute prefix, suffix, conv<br>
    # NOTE routes may be inherited, so late-setting controller is necessary
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

    TOKEN = /%(?:[sz]|(?>\.\d+)?[dfux])/
    FORWARD_SPLIT = /(?=#{TOKEN})/

    # #### Returns
    #
    #     [str_re, conv]
    #
    def compile_re suffix
      return ['', []] unless suffix
      conv = []
      segs = suffix.split(FORWARD_SPLIT).flat_map do |s|
        if (s =~ TOKEN) == 0
          part1 = s[TOKEN]
          [part1, s.slice(part1.size..-1)]
        else
          s
        end
      end
      re_segs = segs.map do |s|
        case s
        when /\A%(?>\.\d+)?([dfux])\z/
          case $1
          when 'd'
            conv << :to_i
            '(-?\d+)'
          when 'f'
            conv << :to_f
            # just copied from scanf
            '([-+]?(?:0[xX](?:\.\h+|\h+(?:\.\h*)?)[pP][-+]\d+|\d+(?![\d.])|\d*\.\d*(?:[eE][-+]?\d+)?))'
          when 'u'
            conv << :to_i
            '(\d+)'
          when 'x'
            conv << :hex
            '(\h+)'
          end
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

      path.split(FORWARD_SPLIT, 2)
    end
  end

  # class methods
  class << Route
    # #### Param
    #
    # * `controller` - string or class which inherits [Nyara::Controller](Controller.html)
    #
    # NOTE controller may be not defined when register_controller is called
    def register_controller scope, controller
      unless scope.is_a?(String)
        raise ArgumentError, "route prefix should be a string"
      end
      scope = scope.dup.freeze
      (@controllers ||= []) << [scope, controller]
    end

    def compile
      @global_path_templates = {} # "name#id" => path
      mapped_controllers = {}

      routes = @controllers.flat_map do |scope, c|
        if c.is_a?(String)
          c = name2const c
        end
        name = c.controller_name || const2name(c)
        raise "#{c.inspect} is not a Nyara::Controller" unless Controller > c

        if mapped_controllers[c]
          raise "controller #{c.inspect} was already mapped"
        end
        mapped_controllers[c] = true

        c.nyara_compile_routes(scope).each do |e|
          @global_path_templates[name + e.id] = e.path_template
        end
      end
      routes.sort_by! &:prefix
      routes.reverse!

      mapped_controllers.each do |c, _|
        c.path_templates = @global_path_templates.merge c.path_templates
      end

      Ext.clear_route
      routes.each do |e|
        Ext.register_route e
      end
    end

    def global_path_template id
      @global_path_templates[id]
    end

    # remove `.klass` and `:method` from selector, and validate selector format
    def canonicalize_callback_selector selector
      /\A
        (?<id>\#\w++(?:\-\w++)*)?
        (?<klass>\.\w++(?:\-\w++)*)?
        (?<method>:\w+)?
      \z/x =~ selector
      unless id or klass or method
        raise ArgumentError, "bad selector: #{selector.inspect}", caller[1..-1]
      end
      id.presence or selector.sub(/:\w+\z/, &:upcase)
    end

    def clear
      # gc mark fail if wrong order?
      Ext.clear_route
      @controllers = []
    end

    # private

    def const2name c
      name = c.to_s.sub /Controller$/, ''
      name.gsub!(/(?<!\b)[A-Z]/){|s| "_#{s.downcase}" }
      name.gsub!(/[A-Z]/, &:downcase)
      name
    end

    def name2const name
      name = name.gsub /(?<=\b|_)[a-z]/, &:upcase
      name.gsub! '_', ''
      name << 'Controller'
      Module.const_get name
    end
  end
end
