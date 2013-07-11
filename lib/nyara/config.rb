module Nyara
  # #### Options
  #
  # * `env`         - environment, default is `'development'`
  # * `port`        - listen port number
  # * `workers`     - number of workers
  # * `host`        - host name used in `url_to` helper
  # * `root`        - root path, default is `Dir.pwd`
  # * `views`       - views (templates) directory, relative to root, default is `"views"`
  # * `public`      - static files directory, relative to root, default is `"public"`
  # * `x_send_file` - header field name for `X-Sendfile` or `X-Accel-Redirect`, see [Nyara::Controller#send_file](Controller#send_file.html-instance_method) for details
  # * `session`     - see [Nyara::Session](Session.html) for sub options
  # * `prefer_erb`  - use ERB instead of ERubis for `.erb` templates
  # * `logger`      - if set, every request is logged, and you can use `Nyara.logger` to do your own logging
  #
  class NyaraConfig < ConfigHash
    # Clear all settings
    def reset
      clear
      Route.clear
    end

    # Init and check configures
    def init
      self['env'] ||= 'development'

      n = (self['port'] || 3000).to_i
      assert n >= 0 && n <= 65535
      self['port'] = n

      n = (self['workers'] || self['worker'] || ((CpuCounter.count + 1)/ 2)).to_i
      assert n > 0 && n < 1000
      self['workers'] = n

      unless self['root']
        set :root, Dir.pwd
      end
      self['root'] = File.expand_path self['root']

      self['views'] = project_path(self['views'] || 'views')
      self['public'] = project_path(self['public'] || 'public')

      if self['public']
        map '/', PublicController
      end
    end

    # Get absoute path under project path
    #
    # #### Options
    #
    # * `strict` - return `nil` if path is not under the dir
    #
    def project_path path, strict=true
      path_under 'root', path, strict
    end

    # Get absoute path under public path
    #
    # #### Options
    #
    # * `strict` - return `nil` if path is not under the dir
    #
    def public_path path, strict=true
      path_under 'public', path, strict
    end

    # Get absoute path under views path
    #
    # #### Options
    #
    # * `strict` - return `nil` if path is not under the dir
    #
    def views_path path, strict=true
      path_under 'views', path, strict
    end

    # Get path under the dir configured `Nyara.config[key]`
    #
    # #### Options
    #
    # * `strict` - return `nil` if path is not under the dir
    #
    def path_under key, path, strict=true
      dir = self[key]
      path = File.expand_path File.join(dir, path)
      if !strict or path.start_with?(dir)
        path
      end
    end

    # Pass requests under a prefix to a controller
    def map prefix, controller
      Route.register_controller prefix, controller
    end

    # Get environment
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

    # @private
    def assert expr # :nodoc:
      raise ArgumentError, "expect #{expr.inspect} to be true", caller[1..-1] unless expr
    end

    def configure &blk
      instance_eval &blk
    end
  end

  # see [NyaraConfig](Nyara/NyaraConfig.html) for options
  Config = NyaraConfig.new
end

# see [NyaraConfig](Nyara/NyaraConfig.html) for options
def configure *xs, &blk
  Nyara::Config.configure *xs, &blk
end

configure do
  set 'env', 'development'
  set 'views', 'views'
  set 'public', 'public'
end
