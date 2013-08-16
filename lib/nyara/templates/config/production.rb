configure do
  set :port, 3000
  ## worker number can be detected by CPU count
  # set :workers, 4
  set :logger, true

  set :manifest, (YAML.load_file Nyara.project_path 'public/manifest.yml')

  # todo after_fork
end
