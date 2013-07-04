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
      (@controllers ||= []) << [scope, controller]
    end

    def compile
      @global_path_templates = {} # "name#id" => path
      mapped_controllers = {}

      route_entries = @controllers.flat_map do |scope, c|
        if c.is_a?(String)
          c = name2const c
        end
        name = c.controller_name || const2name(c)
        raise "#{c.inspect} is not a Nyara::Controller" unless Controller > c

        if mapped_controllers[c]
          raise "controller #{c.inspect} was already mapped"
        end
        mapped_controllers[c] = true

        c.compile_route_entries(scope).each do |e|
          @global_path_templates[name + e.id] = e.path_template
        end
      end
      route_entries.sort_by! &:prefix
      route_entries.reverse!

      mapped_controllers.each do |c, _|
        c.path_templates = @global_path_templates.merge c.path_templates
      end

      Ext.clear_route
      route_entries.each do |e|
        Ext.register_route e
      end
    end

    def global_path_template id
      @global_path_templates[id]
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
