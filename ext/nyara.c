/* ext entrance */

#include "nyara.h"
#include <ruby/io.h>
#include <sys/socket.h>
#include <sys/resource.h>
#include <sys/fcntl.h>

rb_encoding* u8_encoding;

void nyara_set_nonblock(int fd) {
  int flags;

  if ((flags = fcntl(fd, F_GETFL)) == -1) {
    rb_sys_fail("fcntl(F_GETFL)");
  }
  if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) == -1) {
    rb_sys_fail("fcntl(F_SETFL,O_NONBLOCK)");
  }
}

static void set_fd_limit(int nofiles) {
  struct rlimit rlim;
  getrlimit (RLIMIT_NOFILE, &rlim);
  if (nofiles >= 0) {
    rlim.rlim_cur = nofiles;
    if ((unsigned int)nofiles > rlim.rlim_max)
      rlim.rlim_max = nofiles;
    setrlimit (RLIMIT_NOFILE, &rlim);
  }
}

void Init_nyara() {
  u8_encoding = rb_utf8_encoding();
  set_fd_limit(20000);

  VALUE nyara = rb_define_module("Nyara");
# include "inc/version.inc"
  rb_const_set(nyara, rb_intern("VERSION"), rb_enc_str_new(NYARA_VERSION, strlen(NYARA_VERSION), u8_encoding));

  // utils: hashes
  Init_hashes(nyara);

  // utils: method map
  volatile VALUE method_map = rb_class_new_instance(0, NULL, nyara_param_hash_class);
  rb_const_set(nyara, rb_intern("HTTP_METHODS"), method_map);
  VALUE tmp_key = Qnil;
# define METHOD_STR2NUM(n, name, string) \
    tmp_key = rb_enc_str_new(#string, strlen(#string), u8_encoding);\
    OBJ_FREEZE(tmp_key);\
    rb_hash_aset(method_map, tmp_key, INT2FIX(n));
  HTTP_METHOD_MAP(METHOD_STR2NUM);
# undef METHOD_STR2NUM
  OBJ_FREEZE(method_map);

  // utils: status codes
  volatile VALUE status_map = rb_hash_new();
  rb_const_set(nyara, rb_intern("HTTP_STATUS_CODES"), status_map);
  VALUE tmp_value = Qnil;
# define STATUS_DESC(status, desc) \
    tmp_value = rb_enc_str_new(desc, strlen(desc), u8_encoding);\
    OBJ_FREEZE(tmp_value);\
    rb_hash_aset(status_map, INT2FIX(status), tmp_value);
  HTTP_STATUS_CODES(STATUS_DESC);
# undef STATUS_DESC
  OBJ_FREEZE(status_map);

  VALUE ext = rb_define_module_under(nyara, "Ext");
  Init_accept(ext);
  Init_mime(ext);
  Init_request(nyara, ext);
  Init_request_parse(nyara);
  Init_test_response(nyara);
  Init_event(ext);
  Init_route(nyara, ext);
  Init_url_encoded(ext);
}
