# reload views and files

require_relative "../../lib/nyara"

if ENV['RELOAD_ROOT']
  configure do
    set :logger, false
  end
else
  puts "running outside spec, ENV['RELOAD_ROOT'] is nil, creating root dir"
  require 'tmpdir'
  require 'pry'
  ENV['RELOAD_ROOT'] = Dir.mktmpdir 'root'
  Dir.mkdir ENV['RELOAD_ROOT'] + '/views'
  File.open ENV['RELOAD_ROOT'] + '/reloadee.rb', 'w' do |f|
    f << "RELOADEE = 1"
  end
  File.open ENV['RELOAD_ROOT'] + '/views/index.slim', 'w' do |f|
    f << "== 1"
  end
end

configure do
  set :port, 3004
  set :root, ENV['RELOAD_ROOT']
  set :app_files, 'reloadee.rb'
end

get '/views' do
  render 'index'
end

get '/app' do
  send_string RELOADEE
end
