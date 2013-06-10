module Nyara
  Controller = Struct.new :request, :response
  class Controller
    module ClassMethods
      def on method, path, &blk
        @actions ||= []
        @used_ids = {}
        @actions << [method, path, @curr_id, blk]
        if @curr_id
          raise ArgumentError, "action id #{@curr_id} already in use" if @used_ids[@curr_id]
          @used_ids[@curr_id] = true
          @curr_id = nil
          @meta_exist = nil
        end
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
          # todo add opts: strong param, etag, cache, dot separated param, repeated param
        end

        @meta_exist = true
      end

      def get path, &blk
        on 'GET', path, &blk
      end

      def post path, &blk
        on 'POST', path, &blk
      end

      def put path, &blk
        on 'PUT', path, &blk
      end

      def delete path, &blk
        on 'DELETE', path, &blk
      end

      def patch path, &blk
        on 'PATCH', path, &blk
      end

      # todo generate options response for a url
      # see http://tools.ietf.org/html/rfc5789
      def options path, &blk
        on 'OPTIONS', path, &blk
      end

      # [[method, path, id]]
      def preprocess_actions
        raise "#{self}: no action defined" unless @actions

        @curr_id = '#0'
        next_id = proc{
          while @used_ids[@curr_id]
            @curr_id = @curr_id.succ
          end
          @used_ids[@curr_id] = true
          @curr_id
        }
        next_id[]

        @actions.map do |action|
          method, path, id, blk = action
          unless id
            id = next_id[]
            action[2] = id
          end
          # todo path helper
          define_method id, &blk
          [method, path, id]
        end
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
      request.send_data data.to_s
    end

    def render_header
      response.render_header
    end

    def render_string str
      str = str.to_s
      r = response
      r.header['Content-Length'] = str.bytesize
      r.render_header
      request.send_data str
      request.close
    end
  end
end
