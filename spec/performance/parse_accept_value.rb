require_relative "performance_helper"
$0 = '' # don't let sinatra boot the server
require "sinatra"

v = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
env = {'HTTP_ACCEPT' => env}

GC.disable

nyara = bench(10000){ Nyara::Ext.parse_accept_value v }
sinatra = bench_raw(10000){ Sinatra::Request.new(env.dup).accept }
sinatra_baseline = bench_raw(10000){ Sinatra::Request.new(env.dup) }
print Marshal.dump(nyara: nyara, sinatra: (sinatra - sinatra_baseline))
