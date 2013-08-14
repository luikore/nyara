desc "display all routes"
task :routes do
  Nyara.setup
  Nyara::Route.print_routes
end

desc "Run Nyara Console"
task :console do |t, args|
  puts "Loading #{ENV['NYARA_ENV']} environment (Nyara #{Nyara::VERSION})"
  require "irb"
  require 'irb/completion'
  Nyara.setup
  
  ARGV.clear
  IRB.conf[:IRB_NAME] = "nyara"
  IRB.start("config/boot")
end

