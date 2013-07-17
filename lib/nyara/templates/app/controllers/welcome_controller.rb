class WelcomeController < ApplicationController
  get '/' do
    render 'welcome/index'
  end
end
