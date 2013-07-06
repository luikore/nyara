module Nyara
  # test helper
  module Test
    class Response
      # whether request is success
      def success?
        status < 400
      end

      def redirect_location
        if HTTP_REDIRECT_STATUS.include?(status)
          header['Location']
        end
      end

      # C-ext methods: header, body, status, initialize(data), set_cookies
    end

    Env = Struct.new :cookie, :session, :request, :controller, :response, :response_size_limit
    class Env
      # :call-seq:
      #
      #   # change size limit of response data to 100M:
      #   @_env = Env.new 10**8
      #
      def initialize response_size_limit=5_000_000
        self.response_size_limit = response_size_limit
        self.cookie = ParamHash.new
        self.session = ParamHash.new
      end

      def process_request_data data
        client, server = Socket.pair :UNIX, :STREAM
        self.request = Ext.request_new
        Ext.request_set_fd request, server.fileno

        client << data
        self.controller = Ext.handle_request request
        response_data = client.read_nonblock response_size_limit
        self.response = Response.new response_data

        # no env when route not found
        if request.session
          # merge session
          session.clear
          session.merge! request.session

          # merge Set-Cookie
          response.set_cookies.each do |cookie_seg|
            # todo distinguish delete, value and set
            Ext.parse_url_encoded_seg cookie, cookie_seg, false
          end
        end

        server.close
        client.close
      end

      def http meth, path, headers={}, body_string_or_hash=''
        headers = (headers || {}).dup

        # serialize body
        # todo build multipart for file
        if body_string_or_hash.is_a?(Hash)
          body = body_string_or_hash.to_param
          headers['Content-Type'] = 'application/x-www-form-urlencoded'
        else
          body = body_string_or_hash.to_s
          headers['Content-Type'] ||= 'text/plain'
        end
        if body.bytesize > 0
          headers['Content-Length'] = body.bytesize
        end

        # serialize cookie / session
        if headers['Cookie']
          cookie.clear
          cookie.merge! Cookie.decode headers
        end
        Session.encode_to_cookie session, cookie
        headers['Cookie'] = Cookie.encode cookie

        request_data = ["#{meth.upcase} #{Ext.escape path, true} HTTP/1.1\r\n"]
        headers.each do |k, v|
          request_data << "#{k}: #{v}\r\n"
        end
        request_data << "\r\n"
        request_data << body
        process_request_data request_data.join
      end
    end

    def env
      @_env ||= Env.new
    end

    # :call-seq:
    #
    #   get '/', headers
    #
    def get path, header={}, body_string_or_hash=""
      env.http 'GET', path, header, body_string_or_hash
    end

    # :call-seq:
    #
    #   post '/', {}, page: 3
    #   post '/', { 'content-type' => 'application/json' }, '{"page":3}'
    #
    def post path, header={}, body_string_or_hash=""
      env.http 'POST', path, header, body_string_or_hash
    end

    def put path, header={}, body_string_or_hash=""
      env.http 'PUT', path, header, body_string_or_hash
    end

    def delete path, header={}, body_string_or_hash=""
      env.http 'DELETE', path, header, body_string_or_hash
    end

    def patch path, header={}, body_string_or_hash=""
      env.http 'PATCH', path, header, body_string_or_hash
    end

    def options path, header={}, body_string_or_hash=""
      env.http 'OPTIONS', path, header, body_string_or_hash
    end

    def path_to id, *args
      # similar to Controller#path_to, but without local query
      if args.last.is_a?(Hash)
        opts = args.pop
      end

      r = Route.global_path_template(id) % args

      if opts
        format = opts.delete :format
        r << ".#{format}" if format
        r << '?' << opts.to_param unless query.empty?
      end
      r
    end

    def cookie
      env.cookie
    end

    def session
      env.session
    end

    def request
      env.request
    end

    def response
      env.response
    end

    def redirect_location
      env.response.redirect_location
    end

    def follow_redirect
      # todo validate scheme and host
      u = URI.parse(redirect_location)
      path = [u.path, u.query].compact.join '?'
      get path
    end
  end
end
