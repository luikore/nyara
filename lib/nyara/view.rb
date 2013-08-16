module Nyara
  # A support class which provides:
  #
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
  #     friend_layout { enemy_layout { friend_page } }
  #
  # Friend layout and friend page shares one buffer, but enemy layout just concats +buffer.join+ before we flush friend layout.
  # So the simple solution is: templates other than stream-friendly ones are not allowed to be a layout.
  class View
    # Path extension (without dot) => most preferrable content type (e.g. "text/html")
    ENGINE_DEFAULT_CONTENT_TYPES = ParamHash.new

    # Path extension (without dot) => stream friendly
    ENGINE_STREAM_FRIENDLY = ParamHash.new

    # meth name => method obj
    RENDER = {}

    # nested level => layout render, 0 means no layout
    LAYOUT = {}

    autoload :ERB,    File.join(__dir__, "view_handlers/erb")
    autoload :Erubis, File.join(__dir__, "view_handlers/erubis")
    autoload :Haml,   File.join(__dir__, "view_handlers/haml")
    autoload :Slim,   File.join(__dir__, "view_handlers/slim")

    class Buffer < Array
      def initialize parent=nil
        @parent = parent
      end
      attr_reader :parent

      alias safe_append= <<

      def append= thingy
        self << CGI.escape_html(thingy.to_s)
      end

      alias _join join
      def join
        r = super
        clear
        r
      end

      def push_level
        Buffer.new self
      end

      def pop_level
        @parent << _join
      end

      def flush instance
        parents = [self]
        buf = self
        while buf = buf.parent
          parents << buf
        end
        parents.reverse_each do |buf|
          instance.send_chunk buf._join
          buf.clear
        end
      end
    end

    module Renderable
      def self.make_render_method file, line, sig, src
        class_eval <<-RUBY, file, line
          def render#{sig}
            #{src}
          end
        RUBY
        instance_method :render
      end

      def self.make_layout_method nested_level=0
        sig = 'e'
        src = "e.call locals"
        nested_level.times do |i|
          sig << ", e#{i}"
          src = "e#{i}.call{ #{src} }"
        end
        sig = "#{sig}"
        class_eval <<-RUBY
          def layout #{sig}, locals
            #{src}
          end
        RUBY
        instance_method(:layout).bind self
      end
    end

    class TiltRenderable
      def initialize tilt
        @tilt = tilt
      end

      def bind instance
        @instance = instance
        self
      end

      def call locals=nil, &p
        inst = @instance
        @instance = nil
        @tilt.render inst, locals, &p
      end
    end

    class << self
      def init
        RENDER.delete_if{|k, v| k.start_with?('!') }
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

      # NOTE: `path` needs extension
      def on_removed path
        meth = path2meth path
        RENDER.delete meth

        @meth2ext.delete meth
        @meth2sig.delete meth
      end

      def on_removed_all
        meths = @meth2sig
        meths.each do |meth, _|
          RENDER.delete meth
        end
        @meth2sig.clear
        @meth2ext.clear
      end

      # NOTE: `path` needs extension<br>
      #
      # #### Returns
      #
      # dot_ext for further use
      def on_modified path
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
          RENDER[meth] = Renderable.make_render_method path, 0, sig, src
        else
          t = Dir.chdir @root do
            Tilt.new path
          end
          # partly precompiled
          RENDER[meth] = TiltRenderable.new t
        end

        @meth2ext[meth] = ext
      end

      # Define inline render method and add Content-Type mapping
      def register_engine ext, default_content_type, stream_friendly=false
        # todo figure out fname and line
        meth = engine2meth ext
        file = "file".inspect
        line = 1

        if stream_friendly
          RENDER[meth] = Renderable.make_render_method __FILE__, __LINE__, '(locals={})', <<-RUBY
            @_nyara_locals = locals
            src = locals.map{|k, _| "\#{k} = @_nyara_locals[:\#{k}];" }.join
            src << View.precompile(#{ext.inspect}){ @_nyara_view.in }
            instance_eval src, #{file}, #{line}
          RUBY
          ENGINE_STREAM_FRIENDLY[ext] = true
        else
          RENDER[meth] = Renderable.make_render_method __FILE__, __LINE__, '(locals=nil)', <<-RUBY
            Tilt[#{ext.inspect}].new(#{file}, #{line}){ @_nyara_view.in }.render self, locals
          RUBY
        end
        ENGINE_DEFAULT_CONTENT_TYPES[ext] = default_content_type
      end

      # Local keys are for first-time code generation, values not used
      #
      # #### Returns
      #
      # `[meth_obj, ext_without_dot]`
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
        return [RENDER[meth], ext] if ext

        @meth2sig[meth] = locals.keys
        ext = on_modified path if path
        raise "template not found or not valid in Tilt: #{path}" unless ext
        [RENDER[meth], ext]
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
        "!#{path}"
      end

      def engine2meth engine
        ":#{engine}"
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
      else
        raise ArgumentError, "too many options, expected only 1: #{opts.inspect}" if opts.size > 1
        ext, @in = opts.first

        unless @deduced_content_type = ENGINE_DEFAULT_CONTENT_TYPES[ext]
          raise ArgumentError, "unkown template engine: #{ext.inspect}"
        end

        meth = RENDER[View.engine2meth(ext)]
      end

      @args = [meth.bind(instance)]
      unless layout.is_a?(Array)
        layout = layout ? [layout] : []
      end
      layout.each do |l|
        pair = View.template(l)
        # see notes on View
        raise "can not use #{pair[1]} as layout" unless ENGINE_STREAM_FRIENDLY[pair[1]]
        @args << pair.first.bind(instance)
      end

      @layout_render = (LAYOUT[@args.size] ||= Renderable.make_layout_method(@args.size - 1))
      @args << locals

      @instance = instance
      @instance.instance_variable_set :@_nyara_view, self
      @out = Buffer.new
    end
    attr_reader :deduced_content_type, :in, :out

    def partial
      @out = @out.push_level
      res = @layout_render.call *@args
      @out = @out.pop_level
      res
    end

    def render
      @instance.send_chunk @layout_render.call *@args
      Fiber.yield :term_close
    end

    def stream
      @fiber = Fiber.new do
        @rest_result = @layout_render.call *@args
        nil
      end
      self
    end

    def resume
      r = @fiber.resume
      Fiber.yield r if r
      unless @out.empty?
        @out.flush @instance
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
