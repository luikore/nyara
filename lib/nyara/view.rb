module Nyara
  module Renderable
  end

  # A support class which provides:
  # - layout / locals for rendering
  # - template search
  # - template default content-type mapping
  # - template precompile
  # - streaming
  #
  # Streaming is implemented in this way: when +Fiber.yield+ is called, we flush +View#out+ and send the data.
  # This adds a bit limitations to the layouts.
  # Consider this case (+friend+ fills into View#out, while +enemy+ doesn't):
  #
  #   friend layout { enemy layout { friend page } }
  #
  # Friend layout and friend page shares one buffer, but enemy layout just concats +buffer.join+ before we flush friend layout.
  # So the simple solution is: templates other than stream-friendly ones are not allowed to be a layout.
  #
  # Note on Erubis: to support streaming, Erubis is disabled even loaded.
  class View
    # ext (without dot) => most preferrable content type (e.g. "text/html")
    ENGINE_DEFAULT_CONTENT_TYPES = ParamHash.new

    # ext (without dot) => stream friendly
    ENGINE_STREAM_FRIENDLY = ParamHash.new

    autoload :ERB,    File.join(__dir__, "view_handlers/erb")
    autoload :Erubis, File.join(__dir__, "view_handlers/erubis")
    autoload :Haml,   File.join(__dir__, "view_handlers/haml")
    autoload :Slim,   File.join(__dir__, "view_handlers/slim")

    class Buffer < Array
      alias safe_append= <<

      def append= thingy
        self << CGI.escape_html(thingy.to_s)
      end

      def join
        r = super
        clear
        r
      end
    end

    class << self
      def init
        @root = Config['views']
        @meth2ext = {} # meth => ext (without dot)
        @meth2sig = {}
        @ext_list = Tilt.mappings.keys.delete_if(&:empty?).join ','
        if @ext_list !~ /\bslim\b/
          @ext_list = "slim,#{@ext_list}"
        end
        @ext_list = "{#{@ext_list}}"
      end
      attr_reader :root

      # NOTE: +path+ needs extension
      def on_delete path
        meth = path2meth path
        Renderable.class_eval do
          undef meth
        end

        @meth2ext.delete meth
        @meth2sig.delete meth
      end

      def on_delete_all
        meths = @meth2sig
        Renderable.class_eval do
          meths.each do |meth, _|
            undef meth
          end
        end
        @meth2sig.clear
        @meth2ext.clear
      end

      # NOTE: +path+ needs extension<br>
      # returns dot_ext for further use
      def on_update path
        meth = path2meth path
        return unless @meth2sig[meth] # has not been searched before, see also View.template

        ext = File.extname(path)[1..-1]
        return unless ext
        src = precompile ext do
          Dir.chdir(@root){ File.read path, encoding: 'utf-8' }
        end

        if src
          sig = @meth2sig[meth].map{|k| "#{k}: nil" }.join ','
          sig = '_={}' if sig.empty?
          sig = "(#{sig})" # 2.0.0-p0 requirement
          Renderable.class_eval <<-RUBY, path, 0
            def render#{sig}
              #{src}
            end
            alias :#{meth.inspect} render
          RUBY
        else
          t = Dir.chdir @root do
            # todo display template error
            Tilt.new path rescue return
          end
          # partly precompiled
          Renderable.send :define_method, meth do |locals=nil, &p|
            t.render self, locals, &p
          end
        end

        @meth2ext[meth] = ext
      end

      # define inline render method and add Content-Type mapping
      def register_engine ext, default_content_type, stream_friendly=false
        # todo figure out fname and line
        meth = engine2meth ext
        file = "file".inspect
        line = 1

        if stream_friendly
          Renderable.class_eval <<-RUBY, __FILE__, __LINE__
            def render locals={}
              @_nyara_locals = locals
              src = locals.map{|k, _| "\#{k} = @_nyara_locals[:\#{k}];" }.join
              src << View.precompile(#{ext.inspect}){ @_nyara_view.in }
              instance_eval src, #{file}, #{line}
            end
            alias :#{meth.inspect} render
          RUBY
          ENGINE_STREAM_FRIENDLY[ext] = true
        else
          Renderable.class_eval <<-RUBY, __FILE__, __LINE__
            def render locals=nil
              Tilt[#{ext.inspect}].new(#{file}, #{line}){ @_nyara_view.in }.render self, locals
            end
            alias :#{meth.inspect} render
          RUBY
        end
        ENGINE_DEFAULT_CONTENT_TYPES[ext] = default_content_type
      end

      # local keys are for first-time code generation, values not used
      # returns +[meth, ext_without_dot]+
      def template path, locals={}
        if File.extname(path).empty?
          Dir.chdir @root do
            paths = Dir.glob("#{path}.{#@ext_list}")
            if paths.size > 1
              raise ArgumentError, "more than 1 matching views: #{paths.inspect}, add file extension to distinguish them"
            end
            path = paths.first
          end
        end

        meth = path2meth path
        ext = @meth2ext[meth]
        return [meth, ext] if ext

        @meth2sig[meth] = locals.keys
        ext = on_update path
        raise "template not found or not valid in Tilt: #{path}" unless ext
        [meth, ext]
      end

      # private

      # Block is lazy invoked when it's ok to read the template source.
      def precompile ext
        case ext
        when 'slim'
          Slim.src yield
        when 'erb', 'rhtml'
          if Config['prefer_erb']
            ERB.src yield
          else
            Erubis.src yield
          end
        when 'haml'
          Haml.src yield
        end
      end

      def path2meth path
        "!!#{path}"
      end

      def engine2meth engine
        "!:#{engine}"
      end
    end

    # NOTE this is the list used in View.precompile
    %w[slim erb rhtml haml].each {|e| register_engine e, 'text/html', true }

    %w[ad adoc asciidoc erubis builder liquid mab markdown mkd md
      textile rdoc radius nokogiri wiki creole mediawiki mw
    ].each {|e| register_engine e, 'text/html' }

    register_engine 'str', 'text/plain'
    register_engine 'coffee', 'application/javascript'
    register_engine 'yajl', 'application/javascript'
    register_engine 'rcsv', 'application/csv'
    register_engine 'sass', 'text/stylesheet'
    register_engine 'scss', 'text/stylesheet'
    register_engine 'less', 'text/stylesheet'

    # If view_path not given, find template source in opts
    def initialize instance, view_path, layout, locals, opts
      locals ||= {}
      if view_path
        raise ArgumentError, "unkown options: #{opts.inspect}" unless opts.empty?
        meth, ext = View.template(view_path, locals)

        unless @deduced_content_type = ENGINE_DEFAULT_CONTENT_TYPES[ext]
          raise ArgumentError, "unkown template engine: #{ext.inspect}"
        end

        @layouts = [[meth, ext]]
      else
        raise ArgumentError, "too many options, expected only 1: #{opts.inspect}" if opts.size > 1
        ext, template = opts.first
        meth = View.engine2meth ext

        unless @deduced_content_type = ENGINE_DEFAULT_CONTENT_TYPES[ext]
          raise ArgumentError, "unkown template engine: #{ext.inspect}"
        end

        @layouts = [meth]
        @in = template
      end

      unless layout.is_a?(Array)
        layout = layout ? [layout] : []
      end
      layout.each do |l|
        pair = View.template(l)
        # see notes on View
        raise "can not use #{meth} as layout" unless ENGINE_STREAM_FRIENDLY[pair[1]]
        @layouts << pair
      end

      @locals = locals
      @instance = instance
      @instance.instance_variable_set :@_nyara_view, self
      @out = Buffer.new
    end
    attr_reader :deduced_content_type, :in, :out

    def render
      @rest_layouts = @layouts.dup
      @instance.send_chunk _render
      Fiber.yield :term_close
    end

    def _render # :nodoc:
      t, _ = @rest_layouts.pop
      if @rest_layouts.empty?
        @instance.send t, @locals
      else
        @instance.send t do
          _render
        end
      end
    end

    def stream
      @rest_layouts = @layouts.dup
      @fiber = Fiber.new do
        @rest_result = _render
        nil
      end
      self
    end

    def resume
      r = @fiber.resume
      Fiber.yield r if r
      unless @out.empty?
        @instance.send_chunk @out.join
        @out.clear
      end
    end

    def end
      while @fiber.alive?
        resume
      end
      @instance.send_chunk @rest_result
      Fiber.yield :term_close
    end
  end
end
