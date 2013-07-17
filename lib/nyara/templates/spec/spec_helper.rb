configure do
  set :env, 'test'
end
require_relative "../config/application"
require "rspec/autorun"

RSpec.configure do |config|
  # your configure here
end
