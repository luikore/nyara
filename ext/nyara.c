#include "nyara.h"
#include <ruby/io.h>
#include <sys/socket.h>

static VALUE accepter_try_accept(VALUE self, VALUE io) {
  rb_io_t *fptr;
  GetOpenFile(io, fptr);
  int fd = fptr->fd;
  int client_fd = accept(fd, NULL, NULL);
  if (client_fd < 0) {
    // todo handle fd overflow
    return Qnil;
  }
  return INT2FIX(client_fd);
}

void Init_nyara() {
  VALUE nyara = rb_define_module("Nyara");

  // utils: hashes
  Init_hashes(nyara);

  // utils: method map
  volatile VALUE method_map = rb_class_new_instance(0, NULL, nyara_param_hash_class);
  rb_const_set(nyara, rb_intern("HTTP_METHODS"), method_map);
  VALUE tmp_key = Qnil;
# define METHOD_STR2NUM(n, name, string) \
    tmp_key = rb_str_new2(#string);\
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
    tmp_value = rb_str_new2(desc);\
    OBJ_FREEZE(tmp_value);\
    rb_hash_aset(status_map, INT2FIX(status), tmp_value);
  HTTP_STATUS_CODES(STATUS_DESC);
# undef STATUS_DESC
  OBJ_FREEZE(status_map);

  // request
  Init_request(nyara);
  
  // accepter
  VALUE accepter = rb_const_get(nyara, rb_intern("Accepter"));
  rb_define_method(accepter, "try_accept", accepter_try_accept, 1);

  // ext & misc
  VALUE ext = rb_define_module_under(nyara, "Ext");
  Init_route(nyara, ext);
  Init_url_encoded(ext);
}
