require_relative "performance_helper"
require "cgi"

param = "utm_source=feedburner&utm_medium=feed&utm_campaign=Feed%3A+haishin%2Frss%2Findex+%28#{CGI.escape 'マイコミジャーナル'}%29&utm_content=livedoor"

def ruby_parse param
  h = {}
  param.split('&').each do |s|
    k, v = s.split '='
    h[CGI.unescape(k)] = CGI.unescape(v)
  end
end

GC.disable

nyara = bench(1000){ Nyara::Ext.parse_param({}, param) }
ruby = bench(1000){ ruby_parse param }
dump nyara: nyara, ruby: ruby
