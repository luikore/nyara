module Nyara
  # provide route preprocessing utils
  module Route; end
  class << Route
    # note that controller may be not defined yet
    def register_controller scope, controller
      unless scope.is_a?(String)
        raise ArgumentError, "route prefix should be a string"
      end
      scope = scope.dup.freeze
      (@controllers ||= {})[scope] = controller
    end

    def compile
      visited_controllers = {}

      @str2controller ||= {}
      @str2controller.merge! @reg_str2controller

      a = @controllers.map do |scope, c|
        str = nil

        if c.is_a?(String)
          str = c
          c = compute_str2controller c
          @str2controller[str] = c
        end
        if visited_controllers[c]
          raise "controller #{c.inspect} was mapped to different prefix: #{visited_controllers[c].inspect}"
        end

        visited_controllers[c] = scope
        c.scope_prefix = scope.sub /\/\z/, ''

        [scope, c, c.preprocess_actions]
      end
      Ext.clear_route
      process(a).each do |entry|
        entry.validate
        Ext.register_route entry
      end
    end

    def clear
      # gc mark fail if wrong order?
      Ext.clear_route
      @controllers = {}
      @str2controller = {}
    end

    # for runtime query
    def str2controller str
      @str2controller[str]
    end

    Route.instance_variable_set :@reg_str2controller, {}
    # register mapping, permanent
    def register_str2controller str, controller
      @reg_str2controller[str] = controller
    end

    # private

    def compute_str2controller str
      if c = @reg_str2controller[str]
        return c
      end
      str = str.gsub /(?<=\b|_)[a-z]/, &:upcase
      str.gsub! '_', ''
      str << 'Controller'
      Module.const_get str
    end

    def process preprocessed
      entries = []
      preprocessed.each do |(scope, controller, route_entries)|
        route_entries.each do |e|
          e = e.dup # in case there is controller used in more than 1 maps
          path = scope.sub /\/?$/, e.path
          if path.empty?
            path = '/'
          end
          e.prefix, suffix = analyse_path path
          e.suffix, e.conv = compile_re suffix
          e.scope = scope
          e.controller = controller
          entries << e
        end
      end
      entries.sort_by! &:prefix
      entries.reverse!
      entries
    end

    # returns [str_re, conv]
    def compile_re suffix
      return ['', []] unless suffix
      conv = []
      re_segs = suffix.split(/(?<=%[dfsux])|(?=%[dfsux])/).map do |s|
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
        else
          Regexp.quote s
        end
      end
      ["^#{re_segs.join}$", conv]
    end

    # split the path into parts
    def analyse_path path
      raise 'path must contain no new line' if path.index "\n"
      raise 'path must start with /' unless path.start_with? '/'
      path = path.sub(/\/$/, '') if path != '/'

      path.split(/(?=%[dfsux])/, 2)
    end
  end
end
