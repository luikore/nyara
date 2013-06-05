module Nyara
  Config = ConfigHash.new
  class << Config
    def map prefix, controller
      Route.register_controller prefix, controller
    end

    def config &p
      instance_eval &p
      unless @at_exit_hooked
        @at_exit_hooked = true
      end
    end

    alias set []=
    alias get []
  end
  Config[:env] = 'development'
end
