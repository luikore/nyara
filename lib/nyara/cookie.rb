module Nyara
  # rfc6265 (don't look at rfc2109)
  module Cookie
    extend self

    # Encode to string value
    def encode h
      h.map do |k, v|
        "#{Ext.escape k.to_s, false}=#{Ext.escape v.to_s, false}"
      end.join '; '
    end

    # For test
    def decode header
      res = ParamHash.new
      if data = header['Cookie']
        ParamHash.parse_cookie res, data
      end
      res
    end

    def add_set_cookie header_lines, k, v, expires: nil, max_age: nil, domain: nil, path: nil, secure: nil, httponly: true
      r = "Set-Cookie: "
      if v.nil? or v == true
        r << "#{Ext.escape k.to_s, false}; "
      else
        r << "#{Ext.escape k.to_s, false}=#{Ext.escape v.to_s, false}; "
      end
      r << "Expires=#{expires.to_time.gmtime.rfc2822}; " if expires
      r << "Max-Age=#{max_age.to_i}; " if max_age
      # todo lint rfc1123 §2.1, rfc1034 §3.5
      r << "Domain=#{domain}; " if domain
      r << "Path=#{path}; " if path
      r << "Secure; " if secure
      r << "HttpOnly; " if httponly
      r << "\r\n"
      header_lines << r
    end
  end
end
