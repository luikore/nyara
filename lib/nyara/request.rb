# coding: binary

module Nyara
  # request and handler
  class Request
    # c-ext: self.alloc, receive_data

    # c-ext attrs: http_method, scope, path, raw_query, headers, body

    eval(%w[get post put delete options patch].map do |m|
      <<-RUBY
        def #{m}?
          http_method == "#{m.upcase}"
        end
      RUBY
    end.join "\n")

    alias header headers

    def params
      @params ||= begin
        # todo wait for body
        data = get? ? raw_query : body
        res = ParamHash.new
        data.split('&').each do |seg|
          Ext.parse_param_seg res, seg, true
        end
        res
      end
    end
    alias param params

    def not_found
      puts "not found"
      send_data "HTTP/1.1 404 Not Found\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
      close_connection_after_writing
    end
  end
end
