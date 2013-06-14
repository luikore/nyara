module Nyara
  Controller = Struct.new :request, :response
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
      response.header[k] = v
    end

    def add_header s
      response.add_header s
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
      Cookie.output_set_cookie response.extra_header, k, v, opts
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
      response.status = n
    end

    def send_data data
      response.send_data data
    end

    def render_header
      response.render_header
    end

    def render_string str
      str = str.to_s
      r = response
      r.header['Content-Length'] = str.bytesize
      r.render_header
      r.send_data str
      r.close
    end
  end
end
