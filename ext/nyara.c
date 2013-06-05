#include <ruby.h>
#include <ruby/io.h>
#include <sys/socket.h>
#include <http_parser.h>
#include <multipart_parser.h>
#include "route.h"
#include "url_encoded.h"
#include "hashes.h"

typedef struct {
  http_parser hparser;
  multipart_parser* mparser;
  VALUE headers;
  VALUE params;
  VALUE fiber;
  VALUE scope; // mapped prefix
  VALUE path;
  VALUE query;
  VALUE last_field;
  VALUE self;
} Request;

// typedef int (*http_data_cb) (http_parser*, const char *at, size_t length);
// typedef int (*http_cb) (http_parser*);

static ID id_not_found;
static ID id_search;
static VALUE response_class;

static VALUE fiber_func(VALUE _, VALUE args) {
  VALUE instance = rb_ary_pop(args);
  VALUE meth = rb_ary_pop(args);
  rb_funcall(instance, SYM2ID(meth), (int)RARRAY_LEN(args), RARRAY_PTR(args));
  return Qnil;
}

static int on_url(http_parser* parser, const char* s, size_t len) {
  Request* p = (Request*)parser;

  // matching raw path is bad idea, for example: %a0 and %A0 are different strings but same route
  p->path = rb_str_new2("");
  size_t query_i = parse_path(p->path, s, len);
  volatile RouteResult result = lookup_route(parser->method, p->path);
  if (RTEST(result.controller)) {
    {
      VALUE response_args[] = {rb_iv_get(p->self, "@signature")};
      volatile VALUE response = rb_class_new_instance(1, response_args, response_class);
      VALUE instance_args[] = {p->self, response};
      VALUE instance = rb_class_new_instance(2, instance_args, result.controller);
      rb_ary_push(result.args, instance);
    }
    // result.args is on stack, no need to worry gc
    p->fiber = rb_fiber_new(fiber_func, result.args);
    p->scope = result.scope;

    if (query_i < len) {
      p->query = rb_str_new(s + query_i, len - query_i);
    }
    p->headers = rb_class_new_instance(0, NULL, nyara_param_hash_class);
    return 0;
  } else {
    rb_funcall(p->self, id_not_found, 0);
    return 1;
  }
}

static int on_message_complete(http_parser* parser) {
  Request* p = (Request*)parser;
  if (p->fiber == Qnil) {
    return 1;
  } else {
    rb_fiber_resume(p->fiber, 0, NULL);
    return 0;
  }
}

static int on_header_field(http_parser* parser, const char* s, size_t len) {
  Request* p = (Request*)parser;
  p->last_field = rb_str_new(s, len);
  return 0;
}

static int on_header_value(http_parser* parser, const char* s, size_t len) {
  Request* p = (Request*)parser;
  rb_hash_aset(p->headers, p->last_field, rb_str_new(s, len));
  p->last_field = Qnil;
  return 0;
}

static const http_parser_settings request_settings = {
  .on_message_begin = NULL,
  .on_url = on_url,
  .on_status_complete = NULL,
  .on_header_field = on_header_field,
  .on_header_value = on_header_value,
  .on_headers_complete = NULL, // cb
  .on_body = NULL,             // data_cb
  .on_message_complete = on_message_complete
};

static void request_mark(void* pp) {
  Request* p = pp;
  if (p) {
    rb_gc_mark_maybe(p->headers);
    rb_gc_mark_maybe(p->params);
    rb_gc_mark_maybe(p->fiber);
    rb_gc_mark_maybe(p->scope);
    rb_gc_mark_maybe(p->path);
    rb_gc_mark_maybe(p->query);
    rb_gc_mark_maybe(p->last_field);
  }
}

static VALUE request_alloc_func(VALUE klass) {
  Request* p = ALLOC(Request);
  http_parser_init(&(p->hparser), HTTP_REQUEST);
  p->headers = Qnil;
  p->params = Qnil;
  p->fiber = Qnil;
  p->scope = Qnil;
  p->path = Qnil;
  p->query = Qnil;
  p->last_field = Qnil;
  p->self = Data_Wrap_Struct(klass, request_mark, free, p);
  return p->self;
}

// hack to get around the stupid EM::Connection.new
static VALUE request_alloc(VALUE klass, VALUE signature, VALUE io) {
  VALUE self = request_alloc_func(klass);
  rb_iv_set(self, "@signature", signature);
  rb_iv_set(self, "@io", io);
  return self;
}

static VALUE request_receive_data(VALUE self, VALUE data) {
  Request* p;
  Data_Get_Struct(self, Request, p);
  char* s = RSTRING_PTR(data);
  long len = RSTRING_LEN(data);
  http_parser_execute(&(p->hparser), &request_settings, s, len);
  return Qnil;
}

static VALUE request_http_method(VALUE self) {
  Request* p;
  Data_Get_Struct(self, Request, p);
  return rb_str_new2(http_method_str(p->hparser.method));
}

static VALUE request_headers(VALUE self) {
  Request* p;
  Data_Get_Struct(self, Request, p);
  return p->headers;
}

static VALUE request_scope(VALUE self) {
  Request* p;
  Data_Get_Struct(self, Request, p);
  return p->scope;
}

static VALUE request_path(VALUE self) {
  Request* p;
  Data_Get_Struct(self, Request, p);
  return p->path;
}

static VALUE request_query(VALUE self) {
  Request* p;
  Data_Get_Struct(self, Request, p);
  return p->query;
}

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
  id_not_found = rb_intern("not_found");
  id_search = rb_intern("search");
  VALUE nyara = rb_define_module("Nyara");

  // utils: hashes
  Init_hashes(nyara);

  // utils: method map
  volatile VALUE method_map = rb_class_new_instance(0, NULL, nyara_param_hash_class);
  rb_const_set(nyara, rb_intern("HTTP_METHODS"), method_map);
# define METHOD_STR2NUM(n, name, string) rb_hash_aset(method_map, rb_str_new2(#string), INT2FIX(n));
  HTTP_METHOD_MAP(METHOD_STR2NUM);
# undef METHOD_STR2NUM

  // request
  VALUE request = rb_const_get(nyara, rb_intern("Request"));
  rb_define_alloc_func(request, request_alloc_func);
  rb_define_singleton_method(request, "alloc", request_alloc, 2);
  rb_define_method(request, "receive_data", request_receive_data, 1);
  rb_define_method(request, "http_method", request_http_method, 0);
  rb_define_method(request, "headers", request_headers, 0);
  rb_define_method(request, "header", request_headers, 0); // for convenience
  rb_define_method(request, "scope", request_scope, 0);
  rb_define_method(request, "path", request_path, 0);
  rb_define_method(request, "query", request_query, 0);

  // response
  response_class = rb_define_class_under(nyara, "Response", rb_cObject);

  // accepter
  VALUE accepter = rb_const_get(nyara, rb_intern("Accepter"));
  rb_define_method(accepter, "try_accept", accepter_try_accept, 1);

  // ext & misc
  VALUE ext = rb_define_module_under(nyara, "Ext");
  Init_route(nyara, ext);
  Init_url_encoded(ext);
}
