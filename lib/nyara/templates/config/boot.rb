require "nyara"
require "erubis"
require 'bundler' and Bundler.setup(:default)
require 'mongoid'

NYARA_ENV = (ENV['NYARA_ENV'] || 'development').downcase.strip
app_root = File.join(File.dirname(__FILE__),"../")

# load controllers, models
Dir.glob(File.join("app/controllers/**/*")).each do |fname|
  require_relative File.join("..",fname)
end
Dir.glob(File.join("app/models/**/*")).each do |fname|
  require_relative File.join("..",fname)
end

# Configure Mongoid
Mongoid.load!(File.join(app_root,'config/database.yml'), NYARA_ENV)

configure do
  set :env, NYARA_ENV
  set :views, 'app/views'
  set :session, :name, '_aaa'
  set :session, :secure, true
  set :session, :expires, 30 * 60
  
  map '/', 'welcome'
end

# TODO: 此处不用会报 Nyara::SimpleController: no action defined (RuntimeError)
get '/' do
  send_string ''
end

# require_relative NYARA_ENV

