require_relative "performance_helper"
require "cgi"

def ruby_parse
  Nyara::Ext.rdtsc_start
  h = {}
  $param.split('&').each do |s|
    k, v = s.split '='
    h[CGI.unescape(k)] = CGI.unescape(v)
  end
  Nyara::Ext.rdtsc
end

def nyara_parse
  Nyara::Ext.rdtsc_start
  Nyara::ParamHash.parse_param({}, $param)
  Nyara::Ext.rdtsc
end

$param = "utm_source=feedburner&utm_medium=feed&utm_campaign=Feed%3A+haishin%2Frss%2Findex+%28#{CGI.escape 'マイコミジャーナル'}%29&utm_content=livedoor"
ruby_parse
nyara_parse

dump nyara: nyara_parse, ruby: ruby_parse
