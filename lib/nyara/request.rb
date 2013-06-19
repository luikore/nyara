# coding: binary

module Nyara
  # request and handler
  class Request
    # c-ext: http_method, scope, path, matched_accept, header
    #        status, response_content_type, response_header, response_header_extra_lines
    # todo: body, move all underline methods into Ext

    class << self
      undef new
    end

    # method predicates
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

    def scheme
      @scheme ||= begin
        h = header
        if h['X-Forwarded-Ssl'] == 'on'
          'https'
        elsif s = h['X-Forwarded-Scheme']
          s
        elsif s = h['X-Forwarded-Proto']
          s.split(',')[0]
        else
          'http'
        end
      end
    end

    def ssl?
      scheme == 'https'
    end

    def domain
      @domain ||= begin
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

    def host
      header['Host']
    end

    def xhr?
      header["Requested-With"] == "XMLHttpRequest"
    end

    def accept
      @accept ||= Ext.parse_accept_value header['Accept']
    end

    def accept_language
      @accept_language ||= Ext.parse_accept_value header['Accept-Language']
    end

    def accept_charset
      @accept_charset ||= Ext.parse_accept_encoding header['Accept-Charset']
    end

    def accept_encoding
      @accept_encoding ||= Ext.parse_accept_encoding header['Accept-Encoding']
    end

    FORM_METHODS = %w[
      POST
      PUT
      DELETE
      PATCH
    ]

    FORM_MEDIA_TYPES = %w[
      application/x-www-form-urlencoded
      multipart/form-data
    ]

    def form?
      if type = header['Content-Type']
        FORM_METHODS.include?(http_method) and
        FORM_MEDIA_TYPES.include?(type)
      else
        post?
      end
    end

    def param
      @param ||= begin
        query_param = Ext.request_param self
        if form?
          Ext.parse_param query_param, body
        end
        query_param
      end
    end

    def cookie
      @cookie ||= Cookie.decode header
    end

    def session
      @session ||= Session.decode cookie
    end

    # todo serialize the changed cookie

    # todo rename and move it into Ext
    def not_found
      puts "not found"
      Ext.send_data self, "HTTP/1.1 404 Not Found\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
      Ext.close self
    end
  end
end
