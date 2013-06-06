# master require
require "eventmachine"
require "http/parser"
require "fiber"
require "cgi"

module Nyara
  class Request < EM::Connection; end
  class Accepter < EM::Connection; end
end
require_relative "../../ext/nyara"
require_relative "param_hash"
require_relative "header_hash"
require_relative "config_hash"
require_relative "controller"
require_relative "request"
require_relative "response"
require_relative "accepter"
require_relative "config"
require_relative "route"
require_relative "route_entry"

module Nyara
  HTTP_STATUS_FIRST_LINES = Hash[HTTP_STATUS_CODES.map{|k,v|[k, "HTTP/1.1 #{k} #{v}\r\n".freeze]}].freeze

  class << self
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
        GC.start
        # todo cpu count
        workers.times do
          fork {
            EM.run do
              EM.watch(server, Accepter).notify_readable = true
            end
          }
        end
        Process.waitall
      when 'test'
        # don't
      else
        EM.run do
          EM.start_server '127.0.0.1', port, Request
        end
      end
    end
  end
end
