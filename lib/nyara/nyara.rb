require "eventmachine"
require "http/parser"
require "fiber"
require "cgi"

module Nyara
  class Request < EM::Connection; end
  class Accepter < EM::Connection; end
end
require_relative "../../ext/nyara"
require_relative "controller"
require_relative "request"
require_relative "response"
require_relative "accepter"
require_relative "config"
require_relative "route"
require_relative "route_entry"

module Nyara
  class << self
    def config
      raise ArgumentError, 'block not accepted, did you mean Nyara::Config.config?' if block_given?
      Config
    end

    def start_server port
      puts "starting #{Config[:env]} server at 127.0.0.1:#{port}"
      case Config[:env].to_s
      when 'production'
        server = TCPServer.new '127.0.0.1', 3000
        server.listen 1000
        GC.start
        # todo cpu count
        3.times do
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
          EM.start_server '127.0.0.1', 3000, Request
        end
      end
    end
  end
end

# at_exit do
#   Nyara::Route.compile
#   Nyara.start_server 3000
# end
