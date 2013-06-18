module Nyara
  # Contain render methods
  module Renderable
  end

  Controller = Struct.new :request
  class Controller
    module ClassMethods
      # Connect HTTP +method+, +path+ with +blk+ action
      def http method, path, &blk
        @route_entries ||= []
        @used_ids = {}

        action = RouteEntry.new
        action.http_method = HTTP_METHODS[method]
        action.path = path
        action.set_accept_exts @accept
        action.id = @curr_id.to_sym if @curr_id
        action.blk = blk
        @route_entries << action

        if @curr_id
          raise ArgumentError, "action id #{@curr_id} already in use" if @used_ids[@curr_id]
          @used_ids[@curr_id] = true
          @curr_id = nil
          @meta_exist = nil
        end
        @accept = nil
      end

      # Set meta data for next action
      def meta tag=nil, opts=nil
        if @meta_exist
          raise 'contiguous meta data descriptors, should follow by an action'
        end
        if tag.nil? and opts.nil?
          raise ArgumentError, 'expect tag or options'
        end

        if opts.nil? and tag.is_a?(Hash)
          opts = tag
          tag = nil
        end

        if tag
          # todo scan class
          id = tag[/\#\w++(\-\w++)*/]
          @curr_id = id
        end

        if opts
          # todo add opts: strong param, etag, cache-control
          @accept = opts[:accept]
        end

        @meta_exist = true
      end

      # HTTP GET
      def get path, &blk
        http 'GET', path, &blk
      end

      # HTTP POST
      def post path, &blk
        http 'POST', path, &blk
      end

      # HTTP PUT
      def put path, &blk
        http 'PUT', path, &blk
      end

      # HTTP DELETE
      def delete path, &blk
        http 'DELETE', path, &blk
      end

      # HTTP PATCH
      def patch path, &blk
        http 'PATCH', path, &blk
      end

      # HTTP OPTIONS
      # todo generate options response for a url
      # see http://tools.ietf.org/html/rfc5789
      def options path, &blk
        http 'OPTIONS', path, &blk
      end

      # ---
      # todo http method: trace ?
      # +++

      # Set default layout
      def layout l
        @default_layout = l
      end
      attr_reader :default_layout

      # Set controller name, so you can use a shorter name to reference the controller in path helper
      def set_name n
        @controller_name = n
      end
      attr_reader :controller_name

      # :nodoc:
      def preprocess_actions
        raise "#{self}: no action defined" unless @route_entries

        curr_id = :'#0'
        next_id = proc{
          while @used_ids[curr_id]
            curr_id = curr_id.succ
          end
          @used_ids[curr_id] = true
          curr_id
        }
        next_id[]

        @route_entries.each do |e|
          e.id ||= next_id[]
          define_method e.id, &e.blk
        end
        @route_entries
      end
    end

    include Renderable

    # :nodoc:
    def self.inherited klass
      # klass will also have this inherited method
      # todo check class name
      klass.extend ClassMethods
      [:@route_entries, :@usred_ids, :@default_layout].each do |iv|
        klass.instance_variable_set iv, klass.superclass.instance_variable_get(iv)
      end
    end

    # Path helper
    def path_for id, *args
      if args.last.is_a?(Hash)
        opts = args.pop
      end

      r = Route.path_template(self.class, id) % args

      if opts
        r << ".#{opts[:format]}" if opts[:format]
        query = opts.map do |k, v|
          next if k == :format
          "#{CGI.escape k.to_s}=#{CGI.escape v}"
        end
        query.compact!
        r << '?' << query.join('&') unless query.empty?
      end
      r
    end

    # Url helper
    # NOTE: host can include port
    def url_for id, *args, scheme: nil, host: Config['host'], **opts
      scheme = scheme ? scheme.sub(/\:?$/, '://') : '//'
      host ||= 'localhost'
      path = path_for id, *args, opts
      scheme << host << path
    end

    def header
      request.header
    end
    alias headers header

    def set_header k, v
      request.response_header[k] = v
    end

    def add_header_line h
      raise 'can not modify sent header' if request.response_header.frozen?
      h = h.sub /(?<![\r\n])\z/, "\r\n"
      request.response_header_extra_lines << s
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

    def set_cookie k, v=nil, opts
      # todo default domain ?
      opts = Hash[opts.map{|k,v| [k.to_sym,v]}]
      Cookie.output_set_cookie response.response_header_extra_lines, k, v, opts
    end

    def delete_cookie k
      # todo domain ? path ?
      set_cookie k, expires: Time.now, max_age: 0
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

    # Set response status
    def status n
      request.status = n
    end

    # Set response Content-Type, if there's no +charset+ in +ty+, and +ty+ is not text, adds default charset
    def content_type ty
      mime_ty = MIME_TYPES[ty.to_s]
      raise ArgumentError, "bad content type: #{ty.inspect}" unless mime_ty
      r.response_content_type = mime_ty
    end

    # Send respones first line and header data, and freeze +header+ to forbid further changes
    def send_header template_deduced_content_type=nil
      r = request
      header = r.response_header

      Ext.send_data r, HTTP_STATUS_FIRST_LINES[r.status]

      header._ast_content_type \
        r.response_content_type ||
        header.aref_content_type ||
        (r.accept and MIME_TYPES[r.accept]) ||
        template_deduced_content_type

      header.reverse_merge! OK_RESP_HEADER

      data = header.map do |k, v|
        "#{k}: #{v}\r\n"
      end
      data.concat r.response_header_extra_lines
      data << "\r\n"
      Ext.send_data r, data.join

      # forbid further modification
      header.freeze
    end

    # Send raw data, that is, not wrapped in chunked encoding<br>
    # NOTE: often you should call send_header before doing this.
    def send_data data
      Ext.send_data request, data.to_s
    end

    # Send a data chunk, it can send_header first if header is not sent.
    # 
    # :call-seq:
    #
    #   send_chunk 'hello world!'
    def send_chunk data
      send_header unless request.response_header.frozen?
      Ext.send_chunk request, data.to_s
    end
    alias send_string send_chunk

    # Send file
    def send_file file
      if behind_proxy? # todo
        header['X-Sendfile'] = file # todo escape name?
        # todo content type and disposition
        header['Content-Type'] = determine_ct_by_file_name
        send_header unless request.response_header.frozen?
      else
        data = File.binread file
        header['Content-Type'] = determine_ct_by_file_name
        send_header unless request.response_header.frozen?
        send_data data
      end
      Fiber.yield :term_close # is it right? content type changed
    end

    # Resume action after +seconds+
    def wait seconds
      Fiber.yield seconds.to_f # todo
    end

    # One shot render, and terminate the action.
    #
    # :call-seq:
    #
    #   # render a template, engine determined by extension
    #   render 'user/index', locals: {}
    #
    #   # with template source, set content type to +text/html+ if not given
    #   render erb: "<%= 1 + 1 %>"
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
    # :call-seq:
    #
    #   view = stream erb: "<% 5.times do |i| %>i<% Fiber.yield %><% end %>"
    #   view.resume # sends "0"
    #   view.resume # sends "1"
    #   view.resume # sends "2"
    #   view.end    # sends "34" and closes connection
    def stream view_path=nil, layout: self.class.default_layout, locals: nil, **opts
      view = View.new self, view_path, layout, locals, opts
      unless request.response_header.frozen?
        send_header view.deduced_content_type
      end
      view.stream
    end
  end
end
