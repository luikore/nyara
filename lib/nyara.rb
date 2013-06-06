# auto run
require_relative "nyara/nyara"

at_exit do
  Nyara::Route.compile
  Nyara.start_server
end

module Nyara
  class SimpleController < Controller
  end
end

%w[on tag get post put delete patch options].each do |m|
  eval <<-RUBY
  def #{m} *xs, &blk
    Nyara::SimpleController.#{m} *xs, &blk
  end
  RUBY
end

configure do
  map '/', 'nyara::simple'
end
