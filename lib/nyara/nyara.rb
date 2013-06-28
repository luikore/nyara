# patch core classes first
require_relative "patches/mini_support"

# master require
require "fiber"
require "cgi"
require "uri"
require "openssl"
require "base64"
require "socket"
require "tilt"

require_relative "../../ext/nyara"
require_relative "hashes/param_hash"
require_relative "hashes/header_hash"
require_relative "hashes/config_hash"
require_relative "mime_types"
require_relative "controller"
require_relative "request"
require_relative "cookie"
require_relative "session"
require_relative "config"
require_relative "route"
require_relative "route_entry"
require_relative "view"
require_relative "cpu_counter"

module Nyara
  HTTP_STATUS_FIRST_LINES = Hash[HTTP_STATUS_CODES.map{|k,v|[k, "HTTP/1.1 #{k} #{v}\r\n".freeze]}].freeze

  HTTP_REDIRECT_STATUS = [300, 301, 302, 303, 307]

  # base header response for 200
  # caveat: these entries can not be deleted
  OK_RESP_HEADER = HeaderHash.new
  OK_RESP_HEADER['Content-Type'] = 'text/html; charset=UTF-8'
  OK_RESP_HEADER['Cache-Control'] = 'no-cache'
  OK_RESP_HEADER['Transfer-Encoding'] = 'chunked'
  OK_RESP_HEADER['X-XSS-Protection'] = '1; mode=block'
  OK_RESP_HEADER['X-Content-Type-Options'] = 'nosniff'
  OK_RESP_HEADER['X-Frame-Options'] = 'SAMEORIGIN'

  class << self
    def config
      raise ArgumentError, 'block not accepted, did you mean Nyara::Config.config?' if block_given?
      Config
    end

    def start_server
      port = Config[:port] || 3000

      puts "starting #{Config[:env]} server at 0.0.0.0:#{port}"
      case Config[:env].to_s
      when 'production'
        patch_tcp_socket
        start_production_server port
      when 'test'
        # don't
      else
        patch_tcp_socket
        start_development_server port
      end
    end

    def patch_tcp_socket
      puts "patching TCPSocket"
      require_relative "patches/tcp_socket"
    end

    def start_production_server port
      workers = Config[:workers] || ((CpuCounter.count + 1)/ 2)

      puts "workers: #{workers}"
      server = TCPServer.new '0.0.0.0', port
      server.listen 1000
      trap :INT do
        @workers.each do |w|
          Process.kill :KILL, w
        end
      end
      GC.start
      @workers = workers.times.map do
        fork {
          Ext.init_queue
          Ext.run_queue server.fileno
        }
      end
      Process.waitall
    end

    def start_development_server port
      t = Thread.new do
        server = TCPServer.new '0.0.0.0', port
        server.listen 1000
        Ext.init_queue
        Ext.run_queue server.fileno
      end
      t.join
    end
  end
end
