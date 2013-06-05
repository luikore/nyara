# auto run
require_relative "nyara/nyara"

at_exit do
  Nyara::Route.compile
  Nyara.start_server
end

module Nyara
  class SimpleApp < Controller
  end
end

%w[on tag get post put delete patch options].each do |m|
  eval <<-RUBY
  def #{m} *xs, &blk
    Nyara::SimpleApp.#{m} *xs, &blk
  end
  RUBY
end

def configure &p
  Nyara::Config.config &p
end

configure do
  map '/', Nyara::SimpleApp
end
