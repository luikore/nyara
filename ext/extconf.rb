require "mkmf"

def tweak_include
  dir = File.dirname __FILE__
  multipart_dir = File.join dir, "multipart-parser-c"
  http_parser_dir = File.join dir, "http-parser"
  flags = " -I#{multipart_dir.shellescape} -I#{http_parser_dir.shellescape}"
  $CFLAGS << flags
  $CPPFLAGS << flags
end

def tweak_cflags
  mf_conf = RbConfig::MAKEFILE_CONFIG
  if mf_conf['CC'] =~ /gcc/
    $CFLAGS << ' -std=c99 -Wno-declaration-after-statement $(xflags)'
  end

  $CPPFLAGS << ' $(xflags)'
  puts "To enable debug: make xflags='-DDEBUG -O0'"
end

# for debugging low versions of gcc
def use_gcc42
  RbConfig::MAKEFILE_CONFIG['CC'] = `which gcc-4.2`.strip
  RbConfig::MAKEFILE_CONFIG['CXX'] = `which g++-4.2`.strip
end
# use_gcc42

have_kqueue = (have_header("sys/event.h") and have_header("sys/queue.h"))
have_epoll = have_func('epoll_create', 'sys/epoll.h')
abort('no kqueue nor epoll') if !have_kqueue and !have_epoll
$defs << "-DNDEBUG -D#{have_epoll ? 'HAVE_EPOLL' : 'HAVE_KQUEUE'}"

have_func('rb_ary_new_capa', 'ruby.h')

tweak_include
tweak_cflags
create_makefile 'nyara'
