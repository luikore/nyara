# connect remote server, and read / write data

require_relative "../../lib/nyara"
require "pry"
require "open-uri"

configure do
  port 3003
end

get '/' do
  data = open "http://baidu.com", &:read
  send_string data
end
