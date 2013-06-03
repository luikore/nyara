# coding: binary

module Nyara
  # request and handler
  class Request < EM::Connection
    GET = 'GET'.freeze

    def initialize s, io
      super
      @io = io
    end

    # c-ext: receive_data
    # c-ext attrs: method, path, query, pathinfo, headers, scope
    # c-ext routing: clear_route, register_route
    # c-ext test util: inspect_route, search_route

    def build_fiber controller, args
      instance = controller.new self, Response.new(@signature)
      Fiber.new{instance.send *args}
    end

    def not_found
      puts "not found"
      send_data "HTTP/1.1 404 Not Found\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
      close_connection_after_writing
    end
  end
end
