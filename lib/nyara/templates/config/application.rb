configure do
  set :env, ENV['NYARA_ENV'] || 'development'

  set :views, 'app/views'

  set :session, :name, '_aaa'

  ## If you've configured https with nginx:
  # set :session, :secure, true

  ## Default session expires when browser closes.
  ## If you need time-based expiration, 30 minutes for example:
  # set :session, :expires, 30 * 60

  # Routing
  map '/', 'welcome'

  # Application loading order
  set :app_files, %w|
    app/controllers/application_controller.rb
    app/{helpers,models,controllers}/**/*.rb
  |

  # Environment specific configure at last
  require_relative env
end

require 'bundler'
Bundler.require Nyara.config.env

# Configure Mongoid
Mongoid.load!(Nyara.config.project_path 'config/database.yml'), Nyara.config.env)

Nyara.config.load_app
