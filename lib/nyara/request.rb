# coding: binary

module Nyara
  # request and handler
  class Request
    # c-ext attrs: http_method, scope, path, _param, header, body

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

    # accept precedence:
    #   if the first matching item in 'Accept' header is ambiguous, use the first configured
    #   else use item
    def accept
      raise 'need to config :accept option with `meta` before using this' unless _accept
      _accept
    end

    def accept_language
      if a = header['Accept-Language']
        a.split ','
      else
        []
      end
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
        if form?
          Ext.parse_param _param, body
        end
        _param
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
      send_data "HTTP/1.1 404 Not Found\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
      close
    end
  end
end
