#include "nyara.h"
#include <multipart_parser.h>
#include <errno.h>
#ifndef write
#include <unistd.h>
#endif

typedef struct {
  http_parser hparser;
  multipart_parser* mparser;
  enum http_method method;
  VALUE header;
  VALUE fiber;
  VALUE scope; // mapped prefix
  VALUE path;
  VALUE param;
  VALUE last_field;
  VALUE last_value;
  VALUE self;
  int fd;
} Request;

// typedef int (*http_data_cb) (http_parser*, const char *at, size_t length);
// typedef int (*http_cb) (http_parser*);

static ID id_not_found;
static VALUE request_class;
static VALUE response_class;
static VALUE method_override_key;
static VALUE nyara_http_methods;

static VALUE fd_request_map;
#define MAX_RECEIVE_DATA 65536
static char received_data[MAX_RECEIVE_DATA];

static VALUE fiber_func(VALUE _, VALUE args) {
  VALUE instance = rb_ary_pop(args);
  VALUE meth = rb_ary_pop(args);
  rb_apply(instance, SYM2ID(meth), args);
  return Qnil;
}

static void _upcase_method(VALUE str) {
  char* s = RSTRING_PTR(str);
  long len = RSTRING_LEN(str);
  for (long i = 0; i < len; i++) {
    if (s[i] >= 'a' && s[i] <= 'z') {
      s[i] = 'A' + (s[i] - 'a');
    }
  }
}

// fixme assume url is always sent as whole (tcp window is large!)
static int on_url(http_parser* parser, const char* s, size_t len) {
  Request* p = (Request*)parser;
  p->method = parser->method;

  // matching raw path is bad idea, for example: %a0 and %A0 are different strings but same route
  p->path = rb_str_new2("");
  size_t query_i = nyara_parse_path(p->path, s, len);
  p->param = rb_class_new_instance(0, NULL, nyara_param_hash_class);
  if (query_i < len) {
    nyara_parse_param(p->param, s + query_i, len - query_i);
    // rewrite method if query contains _method=xxx
    if (p->method == HTTP_POST) {
      VALUE meth = rb_hash_aref(p->param, method_override_key);
      if (TYPE(meth) == T_STRING) {
        _upcase_method(meth);
        VALUE meth_num = rb_hash_aref(nyara_http_methods, meth);
        if (meth_num != Qnil) {
          p->method = FIX2INT(meth_num);
        }
      }
    }
  }

  volatile RouteResult result = nyara_lookup_route(p->method, p->path);
  if (RTEST(result.controller)) {
    {
      volatile VALUE response = rb_class_new_instance(1, &p->self, response_class);
      VALUE instance_args[] = {p->self, response};
      VALUE instance = rb_class_new_instance(2, instance_args, result.controller);
      rb_ary_push(result.args, instance);
    }
    // result.args is on stack, no need to worry gc
    p->fiber = rb_fiber_new(fiber_func, result.args);
    p->scope = result.scope;
    p->header = rb_class_new_instance(0, NULL, nyara_header_hash_class);
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
  if (p->last_field == Qnil) {
    p->last_field = rb_str_new(s, len);
    p->last_value = Qnil;
  } else {
    rb_str_cat(p->last_field, s, len);
  }
  return 0;
}

static int on_header_value(http_parser* parser, const char* s, size_t len) {
  Request* p = (Request*)parser;
  if (p->last_field == Qnil) {
    if (p->last_value == Qnil) {
      rb_bug("on_header_value called when neither last_field nor last_value exist");
      return 1;
    }
    rb_str_cat(p->last_value, s, len);
  } else {
    nyara_headerlize(p->last_field);
    p->last_value = rb_str_new(s, len);
    rb_hash_aset(p->header, p->last_field, p->last_value);
    p->last_field = Qnil;
  }
  return 0;
}

static int on_headers_complete(http_parser* parser) {
  Request* p = (Request*)parser;
  p->last_field = Qnil;
  p->last_value = Qnil;
  // todo resume fiber here
  return 0;
}

static const http_parser_settings request_settings = {
  .on_message_begin = NULL,
  .on_url = on_url,
  .on_status_complete = NULL,
  .on_header_field = on_header_field,
  .on_header_value = on_header_value,
  .on_headers_complete = on_headers_complete,
  .on_body = NULL,             // data_cb
  .on_message_complete = on_message_complete
};

static void request_mark(void* pp) {
  Request* p = pp;
  if (p) {
    rb_gc_mark_maybe(p->header);
    rb_gc_mark_maybe(p->fiber);
    rb_gc_mark_maybe(p->scope);
    rb_gc_mark_maybe(p->path);
    rb_gc_mark_maybe(p->param);
    rb_gc_mark_maybe(p->last_field);
    rb_gc_mark_maybe(p->last_value);
  }
}

static void request_free(void* pp) {
  Request* p = pp;
  if (p) {
    if (p->fd) {
      close(p->fd);
    }
    xfree(p);
  }
}

static Request* request_alloc() {
  Request* p = ALLOC(Request);
  http_parser_init(&(p->hparser), HTTP_REQUEST);
  p->mparser = NULL;
  p->header = Qnil;
  p->fiber = Qnil;
  p->scope = Qnil;
  p->path = Qnil;
  p->param = Qnil;
  p->last_field = Qnil;
  p->last_value = Qnil;
  p->fd = 0;
  p->self = Data_Wrap_Struct(request_class, request_mark, request_free, p);
  return p;
}

static VALUE request_alloc_func(VALUE klass) {
  return request_alloc()->self;
}

static VALUE request_close(VALUE self) {
  Request* p;
  Data_Get_Struct(self, Request, p);
  // NOTE: upon closed (when no dupes), kqueue/epoll removes the fd from queue
  rb_hash_delete(fd_request_map, INT2FIX(p->fd));
  close(p->fd);
  p->fd = 0;
  return self;
}

void nyara_handle_request(int fd) {
  Request* p;

  {
    VALUE v_fd = INT2FIX(fd);
    VALUE request = rb_hash_aref(fd_request_map, v_fd);
    if (request == Qnil) {
      p = request_alloc();
      p->fd = fd;
      rb_hash_aset(fd_request_map, v_fd, p->self);
    } else {
      Data_Get_Struct(request, Request, p);
    }
  }

  long len = read(fd, received_data, MAX_RECEIVE_DATA);
  if (len < 0) {
    if (errno != EAGAIN) {
      // todo log the bug
      request_close(p->self);
    }
  } else {
    // note: when len == 0, means eof reached, that also informs http_parser the eof
    http_parser_execute(&(p->hparser), &request_settings, received_data, len);
  }
}

// for test
static VALUE ext_handle_request(VALUE v_fd) {
  nyara_handle_request(FIX2INT(v_fd));
  return Qnil;
}

static VALUE request_http_method(VALUE self) {
  Request* p;
  Data_Get_Struct(self, Request, p);
  return rb_str_new2(http_method_str(p->method));
}

static VALUE request_header(VALUE self) {
  Request* p;
  Data_Get_Struct(self, Request, p);
  return p->header;
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

static VALUE request__param(VALUE self) {
  Request* p;
  Data_Get_Struct(self, Request, p);
  return p->param;
}

static VALUE request_send_data(VALUE self, VALUE data) {
  Request* p;
  Data_Get_Struct(self, Request, p);
  if (!p->fd) {
    rb_raise(rb_eRuntimeError, "writing to already closed fd");
  }

  char* buf = RSTRING_PTR(data);
  long len = RSTRING_LEN(data);

  while(len) {
    long written = write(p->fd, buf, len);
    if (written == 0)
      return Qnil;
    if (written == -1) {
      if (errno == EWOULDBLOCK || errno == EAGAIN) {
        // todo enqueue data
      }
      return Qnil;
    }
    buf += written;
    len -= written;
  }
  return Qnil;
}

void Init_request(VALUE nyara, VALUE ext) {
  id_not_found = rb_intern("not_found");
  method_override_key = rb_str_new2("_method");
  rb_const_set(nyara, rb_intern("METHOD_OVERRIDE_KEY"), method_override_key);
  nyara_http_methods = rb_const_get(nyara, rb_intern("HTTP_METHODS"));
  fd_request_map = rb_hash_new();
  rb_gc_register_mark_object(fd_request_map);

  // request
  request_class = rb_define_class_under(nyara, "Request", rb_cObject);
  rb_define_alloc_func(request_class, request_alloc_func);
  rb_define_method(request_class, "http_method", request_http_method, 0);
  rb_define_method(request_class, "header", request_header, 0);
  rb_define_method(request_class, "scope", request_scope, 0);
  rb_define_method(request_class, "path", request_path, 0);
  rb_define_method(request_class, "_param", request__param, 0);
  rb_define_method(request_class, "close", request_close, 0);
  rb_define_method(request_class, "send_data", request_send_data, 1);

  // response
  response_class = rb_define_class_under(nyara, "Response", rb_cObject);

  // ext
  rb_define_singleton_method(ext, "handle_request", ext_handle_request, 1);
}
