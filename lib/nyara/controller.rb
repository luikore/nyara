module Nyara
  Controller = Struct.new :request
  class Controller
    module ClassMethods
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

      # set controller name, useful in path helper
      def name n
        Route.register_str2controller n, self
        @name = n
      end

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

      def get path, &blk
        http 'GET', path, &blk
      end

      def post path, &blk
        http 'POST', path, &blk
      end

      def put path, &blk
        http 'PUT', path, &blk
      end

      def delete path, &blk
        http 'DELETE', path, &blk
      end

      def patch path, &blk
        http 'PATCH', path, &blk
      end

      # todo generate options response for a url
      # see http://tools.ietf.org/html/rfc5789
      def options path, &blk
        http 'OPTIONS', path, &blk
      end

      # todo http method: trace ?

      # define methods
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
          # todo path helper
          define_method e.id, &e.blk
        end
        @route_entries
      end
    end

    def self.inherited klass
      # klass will also have this inherited method
      klass.extend ClassMethods
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

    def status n
      request.status = n
    end

    def send_header
      r = request

      Ext.send_data r, HTTP_STATUS_FIRST_LINES[r.status]

      header = r.response_header
      if r.status == 200
        header.reverse_merge! OK_RESP_HEADER
        if r.accept
          header._aset 'Content-Type', "#{MIME_TYPES[r.accept]}; charset=UTF-8"
        end
      end
      data = header.map do |k, v|
        "#{k}: #{v}\r\n"
      end
      data.concat r.response_header_extra_lines
      data << "\r\n"
      Ext.send_data r, data.join

      # forbid further modification
      header.freeze
    end

    def send_raw_data data
      Ext.send_data request, data.to_s
    end

    def send_data data
      send_header unless request.response_header.frozen?
      Ext.send_chunk request, data.to_s
    end

    def render view=nil, string: nil, file: nil
      if view
        raise ArgumentError, "too many args, need only one: view | string: str | file: file" if string or file
      elsif string
        raise ArgumentError, "too many args, need only one: view | string: str | file: file" if file
        string = string.to_s
      else
        raise ArgumentError, "require arg: view | string: str | file: file" unless file
        string = File.read file
        # todo x-sendfile
      end

      send_header unless request.response_header.frozen?
      Ext.send_chunk request, string
      Fiber.yield :term_close
    end
  end
end
