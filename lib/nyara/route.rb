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
      @global_path_templates = {} # "name#id" => path
      @path_templates = {}       # klass => {any_id => path}

      a = @controllers.map do |scope, c|
        if c.is_a?(String)
          c = name2const c
        end
        name = c.controller_name || const2name(c)
        raise "#{c.inspect} is not a Nyara::Controller" unless Controller > c

        if @path_templates[c]
          raise "controller #{c.inspect} was already mapped"
        end

        route_entries = c.preprocess_actions
        @path_templates[c] = {}
        route_entries.each do |e|
          id = e.id.to_s
          path = File.join scope, e.path
          @global_path_templates[name + id] = path
          @path_templates[c][id] = path
        end

        [scope, c, route_entries]
      end

      @path_templates.keys.each do |c|
        @path_templates[c] = @global_path_templates.merge @path_templates[c]
      end

      Ext.clear_route
      process(a).each do |entry|
        entry.validate
        Ext.register_route entry
      end
    end

    def path_template klass, id
      @path_templates[klass][id]
    end

    def global_path_template id
      @global_path_templates[id]
    end

    def clear
      # gc mark fail if wrong order?
      Ext.clear_route
      @controllers = {}
      @path_templates = {}
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
        when '%z'
          conv << :to_s
          '(.+)'
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
