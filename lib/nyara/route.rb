module Nyara
  # provide route preprocessing utils
  # the core register/search is in Request
  Route = Object.new
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
        [scope, c, c.preprocess_actions]
      end
      Request.clear_route
      process(a).each do |args|
        Request.register_route *args
      end
    end

    def clear
      # gc mark fail if wrong order?
      Request.clear_route
      @controllers = []
    end

    # private and not interacting methods

    def process preprocessed
      entries = []
      preprocessed.each do |(scope, controller, actions)|
        actions.each do |(method, path, id)|
          path = scope.sub /\/?$/, path
          prefix, suffix = analyse_path method, path
          suffix, conv = compile_re suffix
          entries << RouteEntry.new{
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
      return [//, []] unless suffix
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

    # split the path into parts and join with method
    def analyse_path method, path
      raise 'path must contain no new line' if path.index "\n"
      raise 'path must start with /' unless path.start_with? '/'
      path = path.sub(/\/$/, '')

      prefix, suffix = path.split(/(?=%[dfsux])/, 2)
      ["#{method} #{prefix}", suffix]
    end
  end
end
