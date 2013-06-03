require "mkmf"

puts "building multipart-parser-c"
dir = File.dirname __FILE__
multipart_dir = File.join dir, "multipart-parser-c"
Dir.chdir multipart_dir do
  system "make" # todo nmake?
end
$CFLAGS << " -I#{multipart_dir.shellescape}"

puts "building http-parser"
http_parser_dir = File.join dir, "http-parser"
Dir.chdir http_parser_dir do
  system "make libhttp_parser.o"
end
$CFLAGS << " -I#{http_parser_dir.shellescape}"

# enable c++11
RbConfig::MAKEFILE_CONFIG['CXXFLAGS'] << ' -stdlib=libc++ -std=c++11'

create_makefile 'nyara'

puts "modifying Makefile"
makefile = File.readlines 'Makefile'
makefile.each do |line|
  if line.start_with?('OBJS =')
    line.sub!(/$/, ' http-parser/libhttp_parser.o multipart-parser-c/multipart_parser.o')
  end
end
File.open 'Makefile', 'w' do |f|
  f.puts makefile
end
