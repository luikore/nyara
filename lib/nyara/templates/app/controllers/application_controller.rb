class ApplicationController < Nyara::Controller
  set_default_layout 'layouts/application'

  def asset_path(path)
    if Nyara.production?
      Nyara::Config['manifest'][path]
    else
      path
    end
  end
end
