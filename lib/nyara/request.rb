# coding: binary

module Nyara
  # request and handler
  class Request
    # c-ext: self.alloc, receive_data

    # c-ext attrs: http_method, scope, path, query, header[s], body
    # note: path is unescaped
    # note: query is raw

    def params
      @params ||= begin
        # todo wait for body
        Ext.parse_query(get? ? query : body)
      end
    end

    def not_found
      puts "not found"
      send_data "HTTP/1.1 404 Not Found\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
      close_connection_after_writing
    end
  end
end
