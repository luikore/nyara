module Nyara
  # other options:
  # - session (see also Session)
  # - host
  # - views
  # - public
  Config = ConfigHash.new
  class << Config
    # clear all settings
    def reset
      clear
      Route.clear
    end

    # init and check configures
    def init
      n = (self['port'] || 3000).to_i
      assert n >= 0 && n <= 65535
      self['port'] = n

      n = (self['workers'] || self['worker'] || ((CpuCounter.count + 1)/ 2)).to_i
      assert n > 0 && n < 1000
      self['workers'] = n

      unless self['root']
        set :root, Dir.pwd
      end

      if self['public']
        map '/', PublicController
      end
    end

    # get absoute path under +Nyara.config[:root]+ <br>
    # if +strict+, return nil if path is not under project dir<br>
    # NOTE if you want to use this method in configure time, you need to configure :root first, here's an example:
    #
    #   configure do
    #     set :root, File.expand_path(__dir__)
    #     set :public, project_path('public')
    #   end
    #
    def project_path path, strict=true
      raise 'please set :root first' unless self['root']
      path_under 'root', path, strict
    end

    # get absoute path under +Nyara.config[:public]+ <br>
    # if +strict+, return nil if path is not under public dir<br>
    # if :public option not set, returns nil
    def public_path path, strict=true
      return unless self['public']
      path_under 'public', path, strict
    end

    # get absoute path under +Nyara.config[:views]+ <br>
    # if +strict+, return nil if path is not under views dir<br>
    # if :views option not set, returns nil
    def views_path path, strict=true
      return unless self['views']
      path_under 'views', path, strict
    end

    # get path under the dir configured +Nyara.config[key]+ <br>
    # if +strict+, return nil if path is not under the dir
    def path_under key, path, strict=true
      dir = self[key]
      path = File.expand_path File.join(dir, path)
      if !strict or path.start_with?(dir)
        path
      end
    end

    # pass requests under a prefix to a controller
    def map prefix, controller
      Route.register_controller prefix, controller
    end

    # get environment
    def env
      self['env'].to_s
    end

    def development?
      e = env
      e.empty? or e == 'development'
    end

    def production?
      env == 'production'
    end

    def test?
      env == 'test'
    end

    alias set []=
    alias get []

    def assert expr # :nodoc:
      raise ArgumentError, "expect #{expr.inspect} to be true", caller[1..-1] unless expr
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
  set 'env', 'development'
  set 'views', 'views'
  set 'public', 'public'
end
