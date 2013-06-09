# master require
require "fiber"
require "cgi"
require "openssl"
require "json"
require "base64"
require "socket"

require_relative "../../ext/nyara"
require_relative "param_hash"
require_relative "header_hash"
require_relative "config_hash"
require_relative "controller"
require_relative "request"
require_relative "response"
require_relative "cookie"
require_relative "session"
require_relative "config"
require_relative "route"
require_relative "route_entry"

module Nyara
  HTTP_STATUS_FIRST_LINES = Hash[HTTP_STATUS_CODES.map{|k,v|[k, "HTTP/1.1 #{k} #{v}\r\n".freeze]}].freeze

  class << self
    def trap sig, &blk
      raise ArgumentError, 'need a block' unless blk
      sig = sig.to_s if sig.is_a?(Symbol)
      sig = Signal.list[sig] if sig.is_a?(String)
      raise ArgumentError, 'signal not supported' unless Signal.signame(sig)
      Ext.trap sig, blk
    end

    def config
      raise ArgumentError, 'block not accepted, did you mean Nyara::Config.config?' if block_given?
      Config
    end

    def start_server
      port = Config[:port] || 3000
      workers = Config[:workers] || 3


      puts "starting #{Config[:env]} server at 127.0.0.1:#{port}"
      case Config[:env].to_s

      when 'production'
        server = TCPServer.new '127.0.0.1', port
        server.listen 1000
        trap :INT do
          @workers.each do |w|
            Process.kill :KILL, w
          end
        end
        GC.start
        # todo cpu count
        @workers = workers.times.map do
          fork {
            Ext.init_queue
            Ext.run_queue server.fileno
          }
        end
        Process.waitall

      when 'test'
        # don't

      else
        trap :INT do
          exit!
        end
        server = TCPServer.new '127.0.0.1', port
        server.listen 1000
        Ext.init_queue
        Ext.run_queue server.fileno
      end
    end
  end
end
