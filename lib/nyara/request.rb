# coding: binary

module Nyara
  # request and handler
  class Request
    # c-ext: self.alloc, receive_data

    # c-ext attrs: http_method, scope, path, raw_query, header, body

    # method predicates
    # todo method simulation
    %w[get post put delete options patch].each do |m|
      eval <<-RUBY
        def #{m}?
          http_method == "#{m.upcase}"
        end
      RUBY
    end

    # header delegates
    %w[content_length content_type referrer user_agent].each do |m|
      eval <<-RUBY
        def #{m}
          header["#{m.split('_').map(&:capitalize).join '-'}"]
        end
      RUBY
    end

    # without port
    def host
      @host ||= begin
        r = header['Host']
        if r
          r.split(':', 2).first
        else
          ''
        end
      end
    end

    def port
      @port ||= begin
        r = header['Host']
        if r
          r = r.split(':', 2).last
        end
        r ? r.to_i : 80 # or server running port?
      end
    end

    def host_with_port
      header['Host']
    end

    def xhr?
      header["Requested-With"] == "XMLHttpRequest"
    end

    def param
      @param ||= begin
        res = ParamHash.new
        if raw_query
          raw_query.split(/[&;] */n).each do |seg|
            Ext.parse_url_encoded_seg res, seg, true
          end
        end
        unless get?
          # todo validate content type of
          # application/x-www-form-urlencoded
          # multipart/form-data
          # todo wait for body
          body.split(/[&;] */n).each do |seg|
            Ext.parse_url_encoded_seg res, seg, true
          end
        end
        res
      end
    end

    def cookie
      @cookie ||= Cookie.decode header
    end

    def session
      @session ||= Session.decode cookie
    end

    # todo serialize the changed cookie

    def not_found
      puts "not found"
      send_data "HTTP/1.1 404 Not Found\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
      close_connection_after_writing
    end
  end
end
