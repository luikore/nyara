# config specific to development environment
configure do
  # enable Nyara.logger
  set :logger, true

  # serve static files in public
  set :public, 'public'

  # auto reload app
  set :watch, 'app'

  # auto re-compile assets
  set :watch_assets, true
end
