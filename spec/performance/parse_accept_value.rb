require_relative "performance_helper"
require "sinatra/base"

V = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
E = {'HTTP_ACCEPT' => V}

def nyara
  Nyara::Ext.rdtsc_start
  Nyara::Ext.parse_accept_value V
  Nyara::Ext.rdtsc
end

def sinatra_baseline
  Nyara::Ext.rdtsc_start
  Sinatra::Request.new(E.dup)
  Nyara::Ext.rdtsc
end

def sinatra
  Nyara::Ext.rdtsc_start
  Sinatra::Request.new(E.dup).accept
  Nyara::Ext.rdtsc
end

nyara
sinatra
sinatra_baseline

dump nyara: nyara, sinatra: (sinatra - sinatra_baseline)
