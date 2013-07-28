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
  # * `logger`      - if set, every request is logged, and you can use `Nyara.logger` to do your own logging.
  # * `app_files`   - application source file glob patterns, they will be required automatically.
  #    In developemnt mode, this option enables automatic reloading for views and app.
  # * `before_fork` - a proc to run before forking
  # * `after_fork`  - a proc to run after forking
  #
  # #### logger example
  #
  #     # use default logger
  #     set :logger, true
  #
  #     # use daily logger, the lambda is invoked to create the logger
  #     set :logger, lambda{ ::Logger.new '/var/server.log', 'daily' }
  #
  #     # use other logger class
  #     set :logger, MySimpleLogger
  #
  #     # disable logger
  #     set :logger, false
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
      self['root'] = File.realpath File.expand_path self['root']

      # todo warn paths not under project?
      self['views'] = project_path(self['views'] || 'views')
      if self['public']
        self['public'] = project_path(self['public'])
      end

      self.logger = create_logger

      assert !self['before_fork'] || self['before_fork'].respond_to?('call')
      assert !self['after_fork'] || self['after_fork'].respond_to?('call')
    end

    attr_accessor :logger

    # Create a logger with the 'logger' option
    def create_logger
      l = self['logger']

      if l == true or l.nil?
        ::Logger.new(production? ? project_path('production.log') : STDOUT)
      elsif l.is_a?(Class)
        l.new(production? ? project_path('production.log') : STDOUT)
      elsif l.is_a?(Proc)
        l.call
      elsif l
        raise 'bad logger configure, should be: `true` / `false` / Class / Proc'
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

    def root
      self['root'].to_s
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
  set 'root', Dir.pwd
end
