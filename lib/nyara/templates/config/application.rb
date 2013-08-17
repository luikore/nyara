require 'bundler'
Bundler.require :default, ENV['NYARA_ENV'] || 'development'

configure do
  set :env, ENV['NYARA_ENV'] || 'development'

  set :port, ENV['NYARA_PORT']

  # directory containing view templates
  set :views, 'app/views'

  ## change cookie based session name
  # set :session, :name, '_aaa'

  ## if you've configured https with nginx:
  # set :session, :secure, true

  ## default session expires when browser closes.
  ## if you need time-based expiration, 30 minutes for example:
  # set :session, :expires, 30 * 60

  # you can regenerate session key with `nyara g session.key`
  set 'session', 'key', File.read(project_path 'config/session.key')

  # map requests to controllers
  map '/', 'WelcomeController'

  # environment specific configure at last
  require_relative env
end

# load app
Dir.glob %w|
  app/controllers/application_controller.rb
  app/{helpers,models,controllers}/**/*.rb
| do |file|
  require_relative "../#{file}"
end

# load database
Mongoid.load!(Nyara.config.project_path('config/database.yml'), Nyara.config.env)

# compile routes and finish misc setup stuffs
Nyara.setup
