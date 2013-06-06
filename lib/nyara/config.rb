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

    def development?
      env = self[:env].to_s
      env.empty? or env == 'development'
    end

    def production?
      self[:env].to_s == 'production'
    end

    def test?
      self[:env].to_s == 'test'
    end

    alias set []=
    alias get []

    def assert expr
      raise ArgumentError unless expr
    end

    # todo env aware configure
    def configure &blk
      instance_eval &blk
    end
  end
end

def configure *xs, &blk
  Nyara::Config.configure *xs, &blk
end

configure do
  set :env, 'development'
end
