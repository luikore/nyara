module Nyara
  Config = ConfigHash.new
  class << Config
    def map prefix, controller
      Route.register_controller prefix, controller
    end

    def port n
      n = n.to_i
      assert n >= 0 && n <= 65535
      Config[:port] = n
    end

    def workers n
      n = n.to_i
      assert n > 0 && n < 1000
      Config[:workers] = n
    end

    def config &p
      instance_eval &p
      unless @at_exit_hooked
        @at_exit_hooked = true
      end
    end

    alias set []=
    alias get []

    def assert expr
      raise ArgumentError unless expr
    end
  end
  Config[:env] = 'development'
end
