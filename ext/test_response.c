/* response parse callbacks, for test helper */

#include "nyara.h"

typedef struct {
  http_parser hparser;
  VALUE header;
  VALUE body;
  VALUE last_field;
  VALUE last_value;
  VALUE set_cookies;
} Response;

static VALUE str_set_cookie;
static VALUE nyara_http_methods;

static int on_header_field(http_parser* parser, const char* s, size_t len) {
  Response* p = (Response*)parser;
  if (p->last_field == Qnil) {
    p->last_field = rb_enc_str_new(s, len, u8_encoding);
    p->last_value = Qnil;
  } else {
    rb_str_cat(p->last_field, s, len);
  }
  return 0;
}

static int on_header_value(http_parser* parser, const char* s, size_t len) {
  Response* p = (Response*)parser;
  if (p->last_field == Qnil) {
    if (p->last_value == Qnil) {
      // todo show where
      rb_raise(rb_eRuntimeError, "parse error");
      return 1;
    }
    rb_str_cat(p->last_value, s, len);
  } else {
    nyara_headerlize(p->last_field);
    p->last_value = rb_enc_str_new(s, len, u8_encoding);
    if (RTEST(rb_funcall(p->last_field, rb_intern("=="), 1, str_set_cookie))) {
      rb_ary_push(p->set_cookies, p->last_value);
    } else {
      rb_hash_aset(p->header, p->last_field, p->last_value);
    }
    p->last_field = Qnil;
  }
  return 0;
}

static int on_headers_complete(http_parser* parser) {
  Response* p = (Response*)parser;
  p->last_field = Qnil;
  p->last_value = Qnil;
  return 0;
}

static int on_body(http_parser* parser, const char* s, size_t len) {
  Response* p = (Response*)parser;
  if (p->body == Qnil) {
    p->body = rb_enc_str_new(s, len, u8_encoding);
  } else {
    rb_str_cat(p->body, s, len);
  }
  return 0;
}

static int on_message_complete(http_parser* parser) {
  Response* p = (Response*)parser;
  p->last_field = Qnil;
  p->last_value = Qnil;
  return 0;
}

static http_parser_settings response_parse_settings = {
  .on_message_begin = NULL,
  .on_url = NULL,
  .on_status_complete = NULL,
  .on_header_field = on_header_field,
  .on_header_value = on_header_value,
  .on_headers_complete = on_headers_complete,
  .on_body = on_body,
  .on_message_complete = on_message_complete
};

static void response_mark(void* pp) {
  Response* p = pp;
  if (p) {
    rb_gc_mark_maybe(p->header);
    rb_gc_mark_maybe(p->body);
    rb_gc_mark_maybe(p->last_field);
    rb_gc_mark_maybe(p->last_value);
    rb_gc_mark_maybe(p->set_cookies);
  }
}

static VALUE response_alloc(VALUE klass) {
  Response* p = ALLOC(Response);
  http_parser_init(&(p->hparser), HTTP_RESPONSE);
  volatile VALUE header = rb_class_new_instance(0, NULL, nyara_header_hash_class);
  volatile VALUE set_cookies = rb_ary_new();
  p->header = header;
  p->body = Qnil;
  p->last_field = Qnil;
  p->last_value = Qnil;
  p->set_cookies = set_cookies;
  return Data_Wrap_Struct(klass, response_mark, xfree, p);
}

static VALUE response_initialize(VALUE self, VALUE data) {
  Check_Type(data, T_STRING);
  Response* p;
  Data_Get_Struct(self, Response, p);
  http_parser_execute(&(p->hparser), &response_parse_settings, RSTRING_PTR(data), RSTRING_LEN(data));
  return self;
}

static VALUE response_header(VALUE self) {
  Response* p;
  Data_Get_Struct(self, Response, p);
  return p->header;
}

static VALUE response_body(VALUE self) {
  Response* p;
  Data_Get_Struct(self, Response, p);
  return p->body;
}

static VALUE response_status(VALUE self) {
  Response* p;
  Data_Get_Struct(self, Response, p);
  return INT2FIX(p->hparser.status_code);
}

static VALUE response_set_cookies(VALUE self) {
  Response* p;
  Data_Get_Struct(self, Response, p);
  return p->set_cookies;
}

void Init_test_response(VALUE nyara) {
  str_set_cookie = rb_enc_str_new("Set-Cookie", strlen("Set-Cookie"), u8_encoding);
  rb_gc_register_mark_object(str_set_cookie);

  nyara_http_methods = rb_const_get(nyara, rb_intern("HTTP_METHODS"));
  VALUE test = rb_define_module_under(nyara, "Test");
  VALUE response = rb_define_class_under(test, "Response", rb_cObject);
  rb_define_alloc_func(response, response_alloc);
  rb_define_method(response, "initialize", response_initialize, 1);
  rb_define_method(response, "header", response_header, 0);
  rb_define_method(response, "body", response_body, 0);
  rb_define_method(response, "status", response_status, 0);
  rb_define_method(response, "set_cookies", response_set_cookies, 0);
}
