# connect remote server, and read / write data

require_relative "../../lib/nyara"
require "pry"
require "open-uri"

configure do
  set :port, 3003
  set :logger, false
end

get '/' do
  data = open "http://baidu.com", &:read
  send_string data
end
