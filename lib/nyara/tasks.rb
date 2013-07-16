require "rake"
require_relative 'nyara'

desc "display all routes"
task :routes do
  Nyara.setup
  puts "all routes:"
  Nyara::Route.routes.each do |route|
    print (route.id || "").gsub("#","").rjust(30)," "
    print route.http_method_to_s.ljust(6)," "
    print route.path
    puts ""
  end
end