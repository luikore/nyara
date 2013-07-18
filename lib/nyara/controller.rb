module Nyara
  Controller = Struct.new :request
  class Controller
    module ClassMethods
      # #### Call-seq
      #
      #     http :get, '/' do
      #       send_string 'hello world'
      #     end
      #
      def http method, path, &blk
        @routes ||= []
        @used_ids = {}
        method = method.to_s.upcase

        action = Route.new
        unless action.http_method = HTTP_METHODS[method]
          raise ArgumentError, "missing http method: #{method.inspect}"
        end
        action.path = path
        action.set_accept_exts @formats
        action.id = @curr_id if @curr_id
        action.classes = @curr_classes if @curr_classes
        # todo validate arity of blk (before filters also needs arity validation)
        action.blk = blk
        @routes << action

        if @curr_id
          raise ArgumentError, "action id #{@curr_id} already in use" if @used_ids[@curr_id]
          @used_ids[@curr_id] = true
          @curr_id = nil
          @meta_exist = nil
        end
        @formats = nil
      end

      # Set meta data for next action
      def meta tag=nil, opts=nil
        if @meta_exist
          raise 'contiguous meta data descriptors, should be followed by an action'
        end
        if tag.nil? and opts.nil?
          raise ArgumentError, 'expect tag or options'
        end

        if opts.nil? and tag.is_a?(Hash)
          opts = tag
          tag = nil
        end

        if tag
          selectors = tag.scan(/[\#\.]\w++(?:\-\w++)*/).to_a
          @curr_id = selectors.find{|s| s.start_with?('#') }
          @curr_id = @curr_id.to_sym if @curr_id
          @curr_classes = selectors.select{|s| s.start_with?('.') }
        end

        if opts
          # todo add opts: strong param, etag, cache-control
          @formats = opts[:formats]
        end

        @meta_exist = true
      end

      eval %w[GET POST PUT DELETE PATCH OPTIONS].map{|meth|
        <<-RUBY
          def #{meth.downcase} path, &blk
            http '#{meth}', path, &blk
          end
        RUBY
      }.join "\n"

      # Add *before* processor, invoke order is the same as definition order
      #
      # #### Call-seq
      #
      #     before '.foo', '.bar:post', ':get' do
      #       require_login
      #     end
      #
      def before *selectors, &p
        raise ArgumentError, "need a block" unless p
        @before_filters ||= {}
        selectors.each do |selector|
          selector = Route.canonicalize_callback_selector selector
          (@before_filters[selector] ||= []) << p
        end
      end

      # Set default layout
      def set_default_layout l
        @default_layout = l
      end
      attr_reader :default_layout

      # Set controller name, so you can use a shorter name to reference the controller in path helper
      def set_controller_name n
        @controller_name = n
      end
      attr_reader :controller_name

      # @private
      def nyara_compile_routes scope # :nodoc:
        raise "#{self}: no action defined" unless @routes

        curr_id = :'#0'
        next_id = proc{
          while @used_ids[curr_id]
            curr_id = curr_id.succ
          end
          @used_ids[curr_id] = true
          curr_id
        }
        next_id[]

        @path_templates = {}
        @routes.each do |e|
          e.id = next_id[] if e.id.empty?

          before_actions = e.matched_lifecycle_callbacks @before_filters
          senders = []
          before_actions.each_with_index do |blk, idx|
            method_name = "#{e.id}\##{idx}"
            senders << "send #{method_name.inspect}\n"
            define_method method_name, &blk
          end
          method_name = "#{e.id}\##{before_actions.size}"
          senders << "send #{method_name.inspect}, *xs\n"
          define_method method_name, e.blk
          class_eval <<-RUBY
            def __nyara_tmp_action *xs
              #{senders.join}
            end
            alias :#{e.id.inspect} __nyara_tmp_action
            undef __nyara_tmp_action
          RUBY

          e.compile self, scope
          e.validate
          @path_templates[e.id] = [e.path_template, e.http_method_override]
        end
        @routes
      end

      attr_accessor :path_templates
    end

    def self.inherited klass
      # note: klass will also have this inherited method

      unless klass.name.end_with?('Controller')
        raise "class #{klass.name} < Nyara::Controller -- class name must end with `Controller`"
      end

      klass.extend ClassMethods
      [:@used_ids, :@default_layout, :@before_filters, :@routes].each do |iv|
        if value = klass.superclass.instance_variable_get(iv)
          if value.is_a? Array
            value = value.map &:dup
          end
          klass.instance_variable_set iv, value.dup
        end
      end
    end

    def self.dispatch request, instance, args
      if cookie_str = request.header._aref('Cookie')
        ParamHash.parse_cookie request.cookie, cookie_str
      end
      request.flash = Flash.new(
        request.session = Session.decode(request.cookie)
      )

      if instance
        if l = Nyara.logger
          l.info "#{request.http_method} #{request.path} => #{instance.class}"
          if %W"POST PUT PATCH".include?(request.http_method)
            l.info "  params: #{instance.params.inspect}"
          end
        end
        instance.send *args
        return
      elsif request.http_method == 'GET' and Config['public']
        path = Config.public_path request.path
        if File.file?(path)
          if l = Nyara.logger
            l.info "GET #{request.path} => public 200"
          end
          instance = Controller.new request
          instance.send_file path
          return
        end
      end

      if l = Nyara.logger
        l.info "#{request.http_method} #{request.path} => 404"
      end
      Ext.request_send_data request, "HTTP/1.1 404 Not Found\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
      Fiber.yield :term_close

    rescue Exception
      instance.handle_error($!) if instance
    end

    # Path helper
    def path_to id, *args
      if args.last.is_a?(Hash)
        opts = args.pop
      end

      template, meth = self.class.path_templates[id.to_s]
      r = template % args

      if opts
        format = opts.delete :format
        r << ".#{format}" if format
        if meth and !opts.key?(:_method) and !opts.key?('_method')
          opts['_method'] = meth
        end
      elsif meth
        opts = {'_method' => meth}
      end

      if opts
        r << '?' << opts.to_query unless opts.empty?
      end
      r
    end

    # Url helper<br>
    # NOTE: host string can include port number<br>
    # TODO: user and password?
    def url_to id, *args, scheme: nil, host: nil, **opts
      scheme = scheme ? scheme.sub(/\:?$/, '://') : '//'
      host ||= request.host_with_port
      path = path_to id, *args, opts
      scheme << host << path
    end

    # Redirect to a url or path, terminates action<br>
    # `status` can be one of:
    #
    # - 300 - multiple choices (e.g. offer different languages)
    # - 301 - moved permanently
    # - 302 - found (default)
    # - 303 - see other (e.g. for results of cgi-scripts)
    # - 307 - temporary redirect
    #
    # Caveats: there's no content in a redirect response yet, if you want one, you can configure nginx to add it
    def redirect url_or_path, status=302
      status = status.to_i
      raise "unsupported redirect status: #{status}" unless HTTP_REDIRECT_STATUS.include?(status)

      r = request
      header = r.response_header
      self.status status

      uri = URI.parse url_or_path
      if uri.host.nil?
        uri.host = request.domain
        uri.port = request.port
      end
      uri.scheme = r.ssl? ? 'https' : 'http'
      header['Location'] = uri.to_s

      # similar to send_header, but without content-type
      Ext.request_send_data r, HTTP_STATUS_FIRST_LINES[r.status]
      data = header.serialize
      data.concat r.response_header_extra_lines
      data << Session.encode_set_cookie(r.session, r.ssl?)
      data << "\r\n"
      Ext.request_send_data r, data.join

      Fiber.yield :term_close
    end

    # Shortcut for `redirect url_to *xs`
    def redirect_to *xs
      redirect url_to(*xs)
    end

    # Stop processing and close connection<br>
    # Calling `halt` closes the connection at once, you may usually need to set status code and send header before halt.
    #
    # #### Example
    #
    #     status 500
    #     send_header
    #     halt
    #
    def halt
      Fiber.yield :term_close
    end

    # Request extension or generated by `Accept`
    def format
      request.format
    end

    # Request header<br>
    # NOTE to change response header, use `set_header`
    def header
      request.header
    end
    alias headers header

    # Set response header
    def set_header field, value
      request.response_header[field] = value
    end

    # Append an extra line in reponse header
    #
    # #### Call-seq
    #
    #     add_header_line "X-Myheader: here we are"
    #
    def add_header_line h
      raise 'can not modify sent header' if request.response_header.frozen?
      h = h.sub /(?<![\r\n])\z/, "\r\n"
      request.response_header_extra_lines << h
    end

    # todo args helper

    def param
      request.param
    end
    alias params param

    def cookie
      request.cookie
    end
    alias cookies cookie

    # Set cookie, if expires is +Time.now+, will remove the cookie entry
    #
    # #### Call-seq
    #
    #     set_cookie 'JSESSIONID', 'not-exist'
    #     set_cookie 'key-without-value'
    #
    # #### Default values in `opts`
    #
    #   expires: nil
    #   max_age: nil
    #   domain: nil
    #   path: nil
    #   secure: nil
    #   httponly: true
    #
    def set_cookie name, value=nil, opts={}
      if value.is_a?(Hash)
        raise ArgumentError, 'hash not allowed in cookie value, did you mean to use it as options?'
      end
      # todo default domain ?
      opts = Hash[opts.map{|k,v| [k.to_sym,v]}]
      Cookie.add_set_cookie request.response_header_extra_lines, name, value, opts
    end

    def delete_cookie name
      # todo domain ? path ?
      set_cookie name, nil, expires: Time.now, max_age: 0
    end

    def clear_cookie
      cookie.each do |k, _|
        delete_cookie k
      end
    end
    alias clear_cookies clear_cookie

    def session
      request.session
    end

    def flash
      request.flash
    end

    # Set response status
    def status n
      raise ArgumentError, "unsupported status: #{n}" unless HTTP_STATUS_FIRST_LINES[n]
      Ext.request_set_status request, n
    end

    # Set response Content-Type, if there's no `charset` in `ty`, and `ty` is not text, adds default charset
    def content_type ty
      mime_ty = MIME_TYPES[ty.to_s]
      raise ArgumentError, "bad content type: #{ty.inspect}" unless mime_ty
      request.response_content_type = mime_ty
    end

    # Send respones first line and header data, and freeze `header`, `session`, `flash.next` to forbid further changes
    def send_header template_deduced_content_type=nil
      r = request
      header = r.response_header

      Ext.request_send_data r, HTTP_STATUS_FIRST_LINES[r.status]

      header.aset_content_type \
        r.response_content_type ||
        header.aref_content_type ||
        (r.accept and MIME_TYPES[r.accept]) ||
        template_deduced_content_type ||
        'text/html'

      header.reverse_merge! OK_RESP_HEADER

      data = header.serialize
      data.concat r.response_header_extra_lines
      data << Session.encode_set_cookie(r.session, r.ssl?)
      data << "\r\n"
      Ext.request_send_data r, data.join

      # forbid further modification
      header.freeze
      r.session.freeze
      r.flash.next.freeze
    end

    # Send raw data, that is, not wrapped in chunked encoding<br>
    # NOTE: often you should call send_header before doing this.
    def send_data data
      Ext.request_send_data request, data.to_s
    end

    # Send a data chunk, it can send_header first if header is not sent.
    #
    # #### Call-seq
    #
    #     send_chunk 'hello world!'
    #
    def send_chunk data
      send_header unless request.response_header.frozen?
      Ext.request_send_chunk request, data.to_s
    end
    alias send_string send_chunk

    # Set aproppriate headers and send the file<br>
    #
    # #### Call-seq
    #
    #     send_file '/home/www/no-virus-inside.exe', disposition: 'attachment'
    #
    # #### Options
    #
    # * `disposition` - `'inline'` by default, if set to `'attachment'`, the file is presented as a download item in browser.
    # * `x_send_file` - if not false/nil, it is considered to be behind a web server.<br>
    #   Then the app sends file with only header configures,<br>
    #   which proxies the actual action to the web server,<br>
    #   which can take the advantage of system calls and reduce transfered data,<br>
    #   thus faster.
    # * `filename` - name for the downloaded file, will use basename of `file` if not set.
    # * `content_type` - defaults to the MIME type matching `file` or `filename`.
    #
    # To configure for lighttpd and apache2 mod_xsendfile (https://tn123.org/mod_xsendfile/):
    #
    #     configure do
    #       set :x_send_file, 'X-Sendfile'
    #     end
    #
    # To configure for nginx (http://wiki.nginx.org/XSendfile):
    #
    #     configure do
    #       set :x_send_file, 'X-Accel-Redirect'
    #     end
    #
    # To disable `x_send_file` while it is enabled globally:
    #
    #     send_file '/some/file', x_send_file: false
    #
    # To enable `x_send_file` while it is disabled globally:
    #
    #     send_file '/some/file', x_send_file: 'X-Sendfile'
    #
    def send_file file, disposition: 'inline', x_send_file: Config['x_send_file'], filename: nil, content_type: nil
      header = request.response_header

      unless header['Content-Type']
        unless content_type
          extname = File.extname(file)
          extname = File.extname(filename) if extname.blank? and filename
          extname.gsub!(".","")
        
          content_type = MIME_TYPES[extname] || 'application/octet-stream'
        end
        header['Content-Type'] = content_type
      end

      disposition = disposition.to_s
      if disposition != 'inline'
        if disposition != 'attachment'
          raise ArgumentError, "disposition should be inline or attachment, but got #{disposition.inspect}"
        end
      end

      filename ||= File.basename file
      header['Content-Disposition'] = "#{disposition}; filename=#{Ext.escape filename, true}"

      header['Transfer-Encoding'] = '' # delete it

      if x_send_file
        header[x_send_file] = file # todo escape name?
        send_header unless request.response_header.frozen?
      else
        # todo nonblock read file?
        data = File.binread file
        header['Content-Length'] = data.bytesize
        send_header unless request.response_header.frozen?
        Ext.request_send_data request, data
      end
      Fiber.yield :term_close
    end

    # Resume action after `seconds`
    def sleep seconds
      seconds = seconds.to_f
      raise ArgumentError, 'bad sleep seconds' if seconds < 0

      # NOTE request_wake requires request as param, so this method can not be generalized to Fiber.sleep

      Ext.request_sleep request # place sleep actions before wake
      Thread.new do
        Kernel.sleep seconds
        Ext.request_wakeup request
      end
      Fiber.yield :sleep # see event.c for the handler
    end

    # Render a template as string
    def partial view_path, locals: nil
      view = View.new self, view_path, nil, nil, {}
      view.partial
    end

    # One shot render, and terminate the action.
    #
    # #### Call-seq
    #
    #     # render a template, engine determined by extension
    #     render 'user/index', locals: {}
    #
    #     # with template source, set content type to +text/html+ if not given
    #     render erb: "<%= 1 + 1 %>"
    #
    #     # layout can be string or array
    #     render 'index', ['inner_layout', 'outer_layout']
    #
    # For steam rendering, see #stream
    def render view_path=nil, layout: self.class.default_layout, locals: nil, **opts
      view = View.new self, view_path, layout, locals, opts
      unless request.response_header.frozen?
        send_header view.deduced_content_type
      end
      view.render
    end

    # Stream rendering
    #
    # #### Call-seq
    #
    #     view = stream erb: "<% 5.times do |i| %>i<% Fiber.yield %><% end %>"
    #     view.resume # sends "0"
    #     view.resume # sends "1"
    #     view.resume # sends "2"
    #     view.end    # sends "34" and closes connection
    #
    def stream view_path=nil, layout: self.class.default_layout, locals: nil, **opts
      view = View.new self, view_path, layout, locals, opts
      unless request.response_header.frozen?
        send_header view.deduced_content_type
      end
      view.stream
    end

    # Handle error, the default is just log it.
    # You may custom your error handler by re-defining `handle_error`.
    # But remember if this fails, the whole program exits.
    #
    # #### Customization Example
    #
    #     def handle_error e
    #       case e
    #       when ActiveRecord::RecordNotFound
    #         # if we are lucky that header has not been sent yet
    #         # we can manage to change response status
    #         status 404
    #         send_header rescue nil
    #       else
    #         super
    #       end
    #     end
    #
    def handle_error e
      if l = Nyara.logger
        l.error "#{e.class}: #{e.message}"
        l.error e.backtrace.join "\n"
      end
      status 500
      send_header rescue nil
      # todo send body without Fiber.yield :term_close
    end
  end
end
