module Nyara
  class RouteEntry
    attr_accessor :http_method, :scope, :prefix, :suffix, :controller, :id, :conv
    def initialize &p
      instance_eval &p
      unless @http_method and @scope and @prefix and @suffix and @controller and @id and @conv
        missing = instance_variables.find_all{|v| !instance_variable_get(v) }
        raise ArgumentError, "missing #{missing.inspect}"
      end
    end
  end
end
