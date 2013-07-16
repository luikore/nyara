require_relative "performance_helper"
require "cgi"

S = 'abcde マfgイ'

def nyara
  Nyara::Ext.rdtsc_start
  Nyara::Ext.escape S, false
  Nyara::Ext.rdtsc
end

def cgi
  Nyara::Ext.rdtsc_start
  CGI.escape S
  Nyara::Ext.rdtsc
end

nyara
cgi

dump nyara: nyara, cgi: cgi
