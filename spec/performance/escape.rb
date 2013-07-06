require_relative "performance_helper"
require "cgi"

s = 'abcde マfgイ'

GC.disable

nyara = bench(10000){ Nyara::Ext.escape s, false }
cgi = bench(10000){ CGI.escape s }
dump nyara: nyara, cgi: cgi
