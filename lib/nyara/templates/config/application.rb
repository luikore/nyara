require 'bundler'
Bundler.require(:default)
require "erubis"
require 'mongoid'

configure do
  set :views, 'app/views'
  set :session, :name, '_aaa'
  set :session, :secure, true
  set :session, :expires, 30 * 60
  
  map '/', 'welcome'
end

# Configure Mongoid
Mongoid.load!(File.join(Nyara.config.root,'config/database.yml'), Nyara.config.env)