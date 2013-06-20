/* request parsing and request object */

#include "nyara.h"
#include <ruby/encoding.h>
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
  VALUE accept; // mime array sorted with q
  VALUE format; // string ext without dot
  VALUE fiber;
  VALUE scope; // mapped prefix
  VALUE path_with_query;
  VALUE path;
  VALUE query;
  VALUE last_field;
  VALUE last_value;
  VALUE self;
  int fd;

  // response
  int status;
  VALUE response_content_type;
  VALUE response_header;
  VALUE response_header_extra_lines;
} Request;

// typedef int (*http_data_cb) (http_parser*, const char *at, size_t length);
// typedef int (*http_cb) (http_parser*);

static ID id_not_found;
static VALUE str_html;
static rb_encoding* u8_encoding;
static VALUE request_class;
static VALUE method_override_key;
static VALUE str_accept;
static VALUE nyara_http_methods;

static VALUE fd_request_map;
#define MAX_RECEIVE_DATA 65536
static char received_data[MAX_RECEIVE_DATA];

static VALUE _fiber_func(VALUE _, VALUE args) {
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

static inline void _close_fd(int fd) {
  rb_hash_delete(fd_request_map, INT2FIX(fd));
  close(fd);
}

static int on_url(http_parser* parser, const char* s, size_t len) {
  Request* p = (Request*)parser;
  p->method = parser->method;

  if (p->path_with_query == Qnil) {
    p->path_with_query = rb_str_new(s, len);
  } else {
    rb_str_cat(p->path_with_query, s, len);
  }
  return 0;
}

static int on_message_complete(http_parser* parser) {
  Request* p = (Request*)parser;
  if (p->fiber == Qnil) {
    return 1;
  } else {
    VALUE state = rb_fiber_resume(p->fiber, 0, NULL);
    if (state == Qnil) { // terminated (todo check raise error)
      if (p->status == 200) {
        write(p->fd, "0\r\n\r\n", 5);
      }
      _close_fd(p->fd);
      p->fd = 0;
    } else if (SYM2ID(state) == rb_intern("term_close")) {
      write(p->fd, "0\r\n\r\n", 5);
      _close_fd(p->fd);
      p->fd = 0;
    }
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

// may override POST by _method in query
static void _parse_path_and_query(Request* p) {
  char* s = RSTRING_PTR(p->path_with_query);
  long len = RSTRING_LEN(p->path_with_query);
  long query_i = nyara_parse_path(p->path, s, len);
  if (query_i < len) {
    nyara_parse_param(p->query, s + query_i, len - query_i);

    // do method override with _method=xxx in query
    if (p->method == HTTP_POST) {
      VALUE meth = rb_hash_aref(p->query, method_override_key);
      if (TYPE(meth) == T_STRING) {
        _upcase_method(meth);
        VALUE meth_num = rb_hash_aref(nyara_http_methods, meth);
        if (meth_num != Qnil) {
          p->method = FIX2INT(meth_num);
        }
      }
    }
  }
}

static int on_headers_complete(http_parser* parser) {
  Request* p = (Request*)parser;
  p->last_field = Qnil;
  p->last_value = Qnil;

  _parse_path_and_query(p);
  p->accept = ext_parse_accept_value(Qnil, rb_hash_aref(p->header, str_accept));
  volatile RouteResult result = nyara_lookup_route(p->method, p->path, p->accept);
  if (RTEST(result.controller)) {
    rb_ary_push(result.args, rb_class_new_instance(1, &(p->self), result.controller));
    // result.args is on stack, no need to worry gc
    p->fiber = rb_fiber_new(_fiber_func, result.args);
    p->scope = result.scope;
    p->format = result.format;
    p->response_header = rb_class_new_instance(0, NULL, nyara_header_hash_class);
    p->response_header_extra_lines = rb_ary_new();
    return 0;
  }
  rb_funcall(p->self, id_not_found, 0);
  return 1;
}

static http_parser_settings request_settings = {
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
    rb_gc_mark_maybe(p->accept);
    rb_gc_mark_maybe(p->format);
    rb_gc_mark_maybe(p->fiber);
    rb_gc_mark_maybe(p->scope);
    rb_gc_mark_maybe(p->path_with_query);
    rb_gc_mark_maybe(p->path);
    rb_gc_mark_maybe(p->query);
    rb_gc_mark_maybe(p->last_field);
    rb_gc_mark_maybe(p->last_value);
    rb_gc_mark_maybe(p->response_content_type);
    rb_gc_mark_maybe(p->response_header);
    rb_gc_mark_maybe(p->response_header_extra_lines);
  }
}

static void request_free(void* pp) {
  Request* p = pp;
  if (p) {
    if (p->fd) {
      _close_fd(p->fd);
    }
    xfree(p);
  }
}

static Request* request_alloc() {
  Request* p = ALLOC(Request);
  http_parser_init(&(p->hparser), HTTP_REQUEST);
  volatile VALUE header = rb_class_new_instance(0, NULL, nyara_header_hash_class);
  volatile VALUE path = rb_enc_str_new("", 0, u8_encoding);
  volatile VALUE query = rb_class_new_instance(0, NULL, nyara_param_hash_class);
  p->mparser = NULL;
  p->header = header;
  p->accept = Qnil;
  p->format = Qnil;
  p->fiber = Qnil;
  p->scope = Qnil;
  p->path_with_query = Qnil;
  p->path = path;
  p->query = query;
  p->last_field = Qnil;
  p->last_value = Qnil;
  p->fd = 0;
  p->status = 200;
  p->response_content_type = Qnil;
  p->response_header = Qnil;
  p->response_header_extra_lines = Qnil;
  p->self = Data_Wrap_Struct(request_class, request_mark, request_free, p);
  return p;
}

static VALUE request_alloc_func(VALUE klass) {
  return request_alloc()->self;
}

/* client entrance
invoke order:
- find/create request
- http_parser_execute
- on_headers_complete => 404 or create request
- on_message_complete => run action
*/
void nyara_handle_request(int fd) {
  Request* p = NULL;
  bool first_time = false;

  {
    VALUE v_fd = INT2FIX(fd);
    VALUE request = rb_hash_aref(fd_request_map, v_fd);
    if (request == Qnil) {
      p = request_alloc();
      p->fd = fd;
      rb_hash_aset(fd_request_map, v_fd, p->self);
      first_time = true;
    } else {
      Data_Get_Struct(request, Request, p);
    }
  }

  long len = read(fd, received_data, MAX_RECEIVE_DATA);
  if (len < 0) {
    if (errno != EAGAIN) {
      // todo log the bug
      if (p->fd) {
        _close_fd(p->fd);
        p->fd = 0;
      }
    }
  } else {
    if (first_time && !len) {
      // todo log this exception
      return;
    }
    // note: when len == 0, means eof reached, that also informs http_parser the eof
    http_parser_execute(&(p->hparser), &request_settings, received_data, len);
  }
}

#define P \
  Request* p;\
  Data_Get_Struct(self, Request, p);

static VALUE request_http_method(VALUE self) {
  P;
  return rb_str_new2(http_method_str(p->method));
}

static VALUE request_header(VALUE self) {
  P;
  return p->header;
}

static VALUE request_scope(VALUE self) {
  P;
  return p->scope;
}

static VALUE request_path(VALUE self) {
  P;
  return p->path;
}

static VALUE request_query(VALUE self) {
  P;
  return p->query;
}

static VALUE request_path_with_query(VALUE self) {
  P;
  return p->path_with_query;
}

static VALUE request_accept(VALUE self) {
  P;
  return p->accept;
}

static VALUE request_format(VALUE self) {
  P;
  return p->format == Qnil ? str_html : p->format;
}

static VALUE request_status(VALUE self) {
  P;
  return INT2FIX(p->status);
}

static VALUE request_response_content_type(VALUE self) {
  P;
  return p->response_content_type;
}

static VALUE request_response_content_type_eq(VALUE self, VALUE ct) {
  P;
  p->response_content_type = ct;
  return self;
}

static VALUE request_response_header(VALUE self) {
  P;
  return p->response_header;
}

static VALUE request_response_header_extra_lines(VALUE self) {
  P;
  return p->response_header_extra_lines;
}

static VALUE ext_request_set_status(VALUE _, VALUE self, VALUE n) {
  P;
  p->status = NUM2INT(n);
  return n;
}

static VALUE ext_send_data(VALUE _, VALUE self, VALUE data) {
  P;
  char* buf = RSTRING_PTR(data);
  long len = RSTRING_LEN(data);

  while(len) {
    long written = write(p->fd, buf, len);
    if (written == 0)
      return Qnil;
    if (written == -1) {
      if (errno == EWOULDBLOCK || errno == EAGAIN) {
        // todo enqueue data and set state
      }
      return Qnil;
    }
    buf += written;
    len -= written;
  }
  return Qnil;
}

static VALUE ext_send_chunk(VALUE _, VALUE self, VALUE str) {
  long len = RSTRING_LEN(str);
  if (!len) {
    return Qnil;
  }
  // todo len overflow?
  P;
  long res = dprintf(p->fd, "%lx\r\n%.*s\r\n", len, (int)len, RSTRING_PTR(str));
  if (res < 0) {
    rb_raise(rb_eRuntimeError, "%s", strerror(errno));
  }
  return Qnil;
}

// for test: find or create a request with a fd
static VALUE ext_handle_request(VALUE _, VALUE v_fd) {
  int fd = FIX2INT(v_fd);
  nyara_handle_request(fd);
  return rb_hash_aref(fd_request_map, v_fd);
}

// set internal attrs in the request object
static VALUE ext_set_request_attrs(VALUE _, VALUE self, VALUE attrs) {
# define ATTR(key) rb_hash_delete(attrs, ID2SYM(rb_intern(key)))
# define HEADER_HASH_NEW rb_class_new_instance(0, NULL, nyara_header_hash_class)
  P;

  VALUE method_num = ATTR("method_num");
  if (method_num == Qnil) {
    rb_raise(rb_eArgError, "bad method_num");
  }
  p->method                      = NUM2INT(method_num);
  p->path                        = ATTR("path");
  p->query                       = ATTR("query");
  p->fiber                       = ATTR("fiber");
  p->scope                       = ATTR("scope");
  p->header                      = ATTR("header");
  p->format                      = ATTR("format");
  p->response_header             = ATTR("response_header");
  p->response_header_extra_lines = ATTR("response_header_extra_lines");

  if (!RTEST(p->header)) p->header = HEADER_HASH_NEW;
  if (!RTEST(p->response_header)) p->response_header = HEADER_HASH_NEW;
  if (!RTEST(p->response_header_extra_lines)) p->response_header_extra_lines = rb_ary_new();

  if (!RTEST(rb_funcall(attrs, rb_intern("empty?"), 0))) {
    VALUE attrs_inspect = rb_funcall(attrs, rb_intern("inspect"), 0);
    rb_raise(rb_eArgError, "unkown attrs: %.*s", (int)RSTRING_LEN(attrs_inspect), RSTRING_PTR(attrs_inspect));
  }
  return self;
# undef HEADER_HASH_NEW
# undef ATTR
}

void Init_request(VALUE nyara, VALUE ext) {
  id_not_found = rb_intern("not_found");
  str_html = rb_str_new2("html");
  OBJ_FREEZE(str_html);
  rb_gc_register_mark_object(str_html);
  u8_encoding = rb_utf8_encoding();
  method_override_key = rb_str_new2("_method");
  rb_const_set(nyara, rb_intern("METHOD_OVERRIDE_KEY"), method_override_key);
  nyara_http_methods = rb_const_get(nyara, rb_intern("HTTP_METHODS"));
  fd_request_map = rb_hash_new();
  rb_gc_register_mark_object(fd_request_map);
  str_accept = rb_str_new2("Accept");
  rb_gc_register_mark_object(str_accept);

  // request
  request_class = rb_define_class_under(nyara, "Request", rb_cObject);
  rb_define_alloc_func(request_class, request_alloc_func);
  rb_define_method(request_class, "http_method", request_http_method, 0);
  rb_define_method(request_class, "header", request_header, 0);
  rb_define_method(request_class, "scope", request_scope, 0);
  rb_define_method(request_class, "path", request_path, 0);
  rb_define_method(request_class, "query", request_query, 0);
  rb_define_method(request_class, "path_with_query", request_path_with_query, 0);
  rb_define_method(request_class, "accept", request_accept, 0);
  rb_define_method(request_class, "format", request_format, 0);

  rb_define_method(request_class, "status", request_status, 0);
  rb_define_method(request_class, "response_content_type", request_response_content_type, 0);
  rb_define_method(request_class, "response_content_type=", request_response_content_type_eq, 1);
  rb_define_method(request_class, "response_header", request_response_header, 0);
  rb_define_method(request_class, "response_header_extra_lines", request_response_header_extra_lines, 0);

  // hide internal methods in ext
  rb_define_singleton_method(ext, "request_set_status", ext_request_set_status, 2);
  rb_define_singleton_method(ext, "send_data", ext_send_data, 2);
  rb_define_singleton_method(ext, "send_chunk", ext_send_chunk, 2);
  // for test
  rb_define_singleton_method(ext, "handle_request", ext_handle_request, 1);
  rb_define_singleton_method(ext, "set_request_attrs", ext_set_request_attrs, 2);
}
