require "slim"

module Nyara
  class View
    class Slim
      def self.src template
        t = ::Slim::Template.new(nil, nil, pretty: false){ template }
        src = t.instance_variable_get :@src
        if src.start_with?('_buf = []')
          src.sub! '_buf = []', '_buf = @_nyara_view.out'
        end
        src
      end
    end
  end
end
