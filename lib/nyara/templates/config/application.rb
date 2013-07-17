require 'bundler'
Bundler.require(:default)

configure do
  set :env, ENV['NYARA_ENV'] || 'development'
  require_relative env

  set :views, 'app/views'

  set :session, :name, '_aaa'

  ## If you've configured https with nginx:
  # set :session, :secure, true

  ## Default session expires when browser closes.
  ## if you need timed expire, 30 minutes for example:
  # set :session, :expires, 30 * 60

  map '/', 'welcome'

  # Configure Mongoid
  Mongoid.load!(project_path 'config/database.yml'), env)

end
