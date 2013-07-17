configure do
  set :env, 'test'
end
require_relative "../config/application"
require "rspec"
