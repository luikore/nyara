module Nyara
  # http://www.ietf.org/rfc/rfc6265.txt (don't look at rfc2109)
  module Cookie
    extend self

    def decode header
      res = ParamHash.new
      if data = header['Cookie']
        Ext.parse_cookie res, data
      end
      res
    end

    def add_set_cookie header_lines, k, v, expires: nil, max_age: nil, domain: nil, path: nil, secure: nil, httponly: true
      r = "Set-Cookie: "
      if v.nil? or v == true
        r << "#{CGI.escape k.to_s}; "
      else
        r << "#{CGI.escape k.to_s}=#{CGI.escape v.to_s}; "
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
