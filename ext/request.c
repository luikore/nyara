/* request parsing and request object */

#include "nyara.h"
#include "request.h"

static VALUE str_html;
static VALUE request_class;
static VALUE sym_writing;
static VALUE str_transfer_encoding;

#define P \
  Request* p;\
  Data_Get_Struct(self, Request, p);

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
    rb_gc_mark_maybe(p->last_part);
    rb_gc_mark_maybe(p->body);

    rb_gc_mark_maybe(p->cookie);
    rb_gc_mark_maybe(p->session);
    rb_gc_mark_maybe(p->flash);

    rb_gc_mark_maybe(p->response_content_type);
    rb_gc_mark_maybe(p->response_header);
    rb_gc_mark_maybe(p->response_header_extra_lines);
    rb_gc_mark_maybe(p->watched_fds);
    rb_gc_mark_maybe(p->instance);
  }
}

static void request_free(void* pp) {
  Request* p = pp;
  if (p) {
    if (p->fd) {
      nyara_detach_fd(p->fd);
      p->fd = 0;
    }
    if (p->mparser) {
      multipart_parser_free(p->mparser);
      p->mparser = NULL;
    }
    xfree(p);
  }
}

static Request* _request_alloc() {
  Request* p = ALLOC(Request);
  http_parser_init(&(p->hparser), HTTP_REQUEST);
  p->mparser = NULL;

  p->method = HTTP_GET;
  p->fd = 0;
  p->parse_state = 0;
  p->status = 200;

  volatile VALUE header = rb_class_new_instance(0, NULL, nyara_header_hash_class);
  volatile VALUE path = rb_enc_str_new("", 0, u8_encoding);
  volatile VALUE query = rb_class_new_instance(0, NULL, nyara_param_hash_class);
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
  p->last_part = Qnil;
  p->body = Qnil;

  p->cookie = Qnil;
  p->session = Qnil;
  p->flash = Qnil;

  p->response_content_type = Qnil;
  p->response_header = Qnil;
  p->response_header_extra_lines = Qnil;

  volatile VALUE watched_fds = rb_ary_new();
  p->watched_fds = watched_fds;
  p->instance = Qnil;

  p->sleeping = false;

  p->self = Data_Wrap_Struct(request_class, request_mark, request_free, p);
  return p;
}

VALUE nyara_request_new(int fd) {
  Request* p = _request_alloc();
  p->fd = fd;
  return p->self;
}

void nyara_request_init_env(VALUE self) {
  static VALUE session_mod = Qnil;
  static VALUE flash_class = Qnil;
  static VALUE str_cookie = Qnil;
  static ID id_decode = 0;
  if (session_mod == Qnil) {
    VALUE nyara = rb_const_get(rb_cModule, rb_intern("Nyara"));
    session_mod = rb_const_get(nyara, rb_intern("Session"));
    flash_class = rb_const_get(nyara, rb_intern("Flash"));
    str_cookie = rb_enc_str_new("Cookie", strlen("Cookie"), u8_encoding);
    rb_gc_register_mark_object(str_cookie);
    id_decode = rb_intern("decode");
  }

  P;
  p->cookie = rb_class_new_instance(0, NULL, nyara_param_hash_class);
  VALUE cookie = rb_hash_aref(p->header, str_cookie);
  if (cookie != Qnil) {
    ext_parse_cookie(Qnil, p->cookie, cookie);
  }
  p->session = rb_funcall(session_mod, id_decode, 1, p->cookie);
  p->flash = rb_class_new_instance(1, &p->session, flash_class);
}

void nyara_request_term_close(VALUE self) {
  P;
  VALUE transfer_enc = rb_hash_aref(p->response_header, str_transfer_encoding);
  if (TYPE(transfer_enc) == T_STRING) {
    if (RSTRING_LEN(transfer_enc) == 7) {
      if (strncmp(RSTRING_PTR(transfer_enc), "chunked", 7) == 0) {
        // usually this succeeds, while not, it doesn't matter cause we are closing it
        if (write(p->fd, "0\r\n\r\n", 5)) {
        }
      }
    }
  }
  if (p->fd) {
    nyara_detach_fd(p->fd);
    p->fd = 0;
  }
}

static VALUE request_http_method(VALUE self) {
  P;
  // todo reduce allocation
  const char* str = http_method_str(p->method);
  return rb_enc_str_new(str, strlen(str), u8_encoding);
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

static VALUE request_cookie(VALUE self) {
  P;
  return p->cookie;
}

static VALUE request_session(VALUE self) {
  P;
  return p->session;
}

static VALUE request_flash(VALUE self) {
  P;
  return p->flash;
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

// return true if success
bool nyara_send_data(int fd, const char* buf, long len) {
  while(len) {
    long written = write(fd, buf, len);
    if (written <= 0) {
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        rb_fiber_yield(1, &sym_writing);
      } else {
        return false;
      }
    } else {
      buf += written;
      len -= written;
      if (len) {
        rb_fiber_yield(1, &sym_writing);
      }
    }
  }
  return true;
}

static VALUE ext_request_send_data(VALUE _, VALUE self, VALUE data) {
  P;
  char* buf = RSTRING_PTR(data);
  long len = RSTRING_LEN(data);
  nyara_send_data(p->fd, buf, len);
  return Qnil;
}

static VALUE ext_request_send_chunk(VALUE _, VALUE self, VALUE str) {
  long len = RSTRING_LEN(str);
  if (!len) {
    return Qnil;
  }
  P;

  char pre_buf[20]; // enough space to hold a long + 2 chars
  long pre_len = sprintf(pre_buf, "%lx\r\n", len);
  if (pre_len <= 0) {
    rb_raise(rb_eRuntimeError, "fail to format chunk length for len: %ld", len);
  }
  bool success = \
    nyara_send_data(p->fd, pre_buf, pre_len) &&
    nyara_send_data(p->fd, RSTRING_PTR(str), len) &&
    nyara_send_data(p->fd, "\r\n", 2);

  if (!success) {
    rb_sys_fail("write(2)");
  }

  return Qnil;
}

// for test: find or create a request with a fd
static VALUE ext_request_new(VALUE _) {
  return _request_alloc()->self;
}

static VALUE ext_request_set_fd(VALUE _, VALUE self, VALUE vfd) {
  P;
  int fd = NUM2INT(vfd);
  if (fd) {
    fd = dup(fd);
    nyara_set_nonblock(fd);
    p->fd = fd;
  }
  return Qnil;
}

// set internal attrs in the request object<br>
// method_num is required, others are optional
static VALUE ext_request_set_attrs(VALUE _, VALUE self, VALUE attrs) {
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
  p->body                        = ATTR("body");
  p->cookie                      = ATTR("cookie");
  p->session                     = ATTR("session");
  p->flash                       = ATTR("flash");
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
  str_html = rb_enc_str_new("html", strlen("html"), u8_encoding);
  OBJ_FREEZE(str_html);
  rb_gc_register_mark_object(str_html);
  sym_writing = ID2SYM(rb_intern("writing"));
  str_transfer_encoding = rb_enc_str_new("Transfer-Encoding", strlen("Transfer-Encoding"), u8_encoding);
  rb_gc_register_mark_object(str_transfer_encoding);

  // request
  request_class = rb_define_class_under(nyara, "Request", rb_cObject);
  rb_define_method(request_class, "http_method", request_http_method, 0);
  rb_define_method(request_class, "header", request_header, 0);
  rb_define_method(request_class, "scope", request_scope, 0);
  rb_define_method(request_class, "path", request_path, 0);
  rb_define_method(request_class, "query", request_query, 0);
  rb_define_method(request_class, "path_with_query", request_path_with_query, 0);
  rb_define_method(request_class, "accept", request_accept, 0);
  rb_define_method(request_class, "format", request_format, 0);
  rb_define_method(request_class, "cookie", request_cookie, 0);
  rb_define_method(request_class, "session", request_session, 0);
  rb_define_method(request_class, "flash", request_flash, 0);

  rb_define_method(request_class, "status", request_status, 0);
  rb_define_method(request_class, "response_content_type", request_response_content_type, 0);
  rb_define_method(request_class, "response_content_type=", request_response_content_type_eq, 1);
  rb_define_method(request_class, "response_header", request_response_header, 0);
  rb_define_method(request_class, "response_header_extra_lines", request_response_header_extra_lines, 0);

  // hide internal methods in ext
  rb_define_singleton_method(ext, "request_set_status", ext_request_set_status, 2);
  rb_define_singleton_method(ext, "request_send_data", ext_request_send_data, 2);
  rb_define_singleton_method(ext, "request_send_chunk", ext_request_send_chunk, 2);
  // for test
  rb_define_singleton_method(ext, "request_new", ext_request_new, 0);
  rb_define_singleton_method(ext, "request_set_fd", ext_request_set_fd, 2);
  rb_define_singleton_method(ext, "request_set_attrs", ext_request_set_attrs, 2);
}
