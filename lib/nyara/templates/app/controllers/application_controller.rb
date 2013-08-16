class ApplicationController < Nyara::Controller
  set_default_layout 'layouts/application'

  def asset_path(path)
    return path if Nyara.config.env == "development"
    manifest[path]
  end

private
  def manifest
    @manifest ||= begin
      env = Linner.env
      manifest_file = File.join(env.public_folder, env.manifest)
      YAML.load File.read(manifest_file)
    end
  end
end
