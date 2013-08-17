class HomeController < ApplicationController
  get '/' do
    render 'home/index'
  end
end
