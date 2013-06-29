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

      # C-ext methods: header, body, status, initialize(data)
    end

    Env = Struct.new :client, :server, :session, :request, :controller, :response
    class Env
      def initialize
        self.client, self.server = Socket.pair :UNIX, :STREAM
        self.request = Ext.request_new
        Ext.request_set_fd request, server.fileno
        self.session = ParamHash.new
      end

      def process_request_data data, response_limit=50_000_000
        client << data
        self.controller = Ext.handle_request request
        response_data = client.read_nonblock response_limit
        self.response = Response.new response_data
        server.close
        client.close
      end
    end

    def http meth, path, headers={}, body_params=''
      @_env = Env.new
      request_info = ["#{meth.upcase} #{path} HTTP/1.1\r\n"]

      headers = headers.dup
      headers['Cookie'] ||= ParamHash.new

      Session.encode @_env.session, headers['Cookie']
      headers.each do |k, v|
        request_info << "#{k}: #{v}\r\n"
      end
      request_info << "\r\n"

      if body_params.is_a?(Hash)
        body_params.to_param
      else
        request_info << body_params
      end

      @_env.process_request_data request_info.join
    end

    def get *xs
      http 'GET', *xs
    end

    def post *xs
      http 'POST', *xs
    end

    def put *xs
      http 'PUT', *xs
    end

    def delete *xs
      http 'DELETE', *xs
    end

    def patch *xs
      http 'PATCH', *xs
    end

    def options *xs
      http 'OPTIONS', *xs
    end

    def path_to id, opts
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

    def session
      @_env.session
    end

    def request
      @_env.request
    end

    def response
      @_env.response
    end
  end
end
