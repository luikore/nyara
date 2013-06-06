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
      # todo, get controller class if it is string
      a = @controllers.map do |(scope, c)|
        if c.is_a?(String)
          c = str2controller c
        end
        [scope, c, c.preprocess_actions]
      end
      Ext.clear_route
      process(a).each do |entry|
        Ext.register_route entry
      end
    end

    def clear
      # gc mark fail if wrong order?
      Ext.clear_route
      @controllers = []
    end

    def str2controller str
      if @str2controller_map
        if c = @str2controller_map[str]
          return c
        end
      end
      str = str.gsub /(?<=\b|_)[a-z]/, &:upcase
      str.gsub! '_', ''
      str << 'Controller'
      Module.const_get str
    end

    def register_str2controller str, controller
      @str2controller_map ||= {}
      @str2controller_map[str] = controller
    end

    # private

    def process preprocessed
      entries = []
      preprocessed.each do |(scope, controller, actions)|
        actions.each do |(method, relative_path, id)|
          path = scope.sub /\/?$/, relative_path
          if path.empty?
            path = '/'
          end
          prefix, suffix = analyse_path path
          suffix, conv = compile_re suffix
          entries << RouteEntry.new{
            @http_method = HTTP_METHODS[method]
            @scope = scope
            @prefix = prefix
            @suffix = suffix
            @controller = controller
            @id = id.to_sym
            @conv = conv
          }
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
