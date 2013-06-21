/* request parse callbacks */

#include "nyara.h"
#include "request.h"

static VALUE str_accept;
static VALUE method_override_key;
static VALUE nyara_http_methods;

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
      p->parse_state = PS_ERROR;
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

static void _upcase_method(VALUE str) {
  char* s = RSTRING_PTR(str);
  long len = RSTRING_LEN(str);
  for (long i = 0; i < len; i++) {
    if (s[i] >= 'a' && s[i] <= 'z') {
      s[i] = 'A' + (s[i] - 'a');
    }
  }
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
  p->parse_state = PS_HEADERS_COMPLETE;
  return 0;
}

static int on_body(http_parser* parser, const char* s, size_t len) {
  // todo
  return 0;
}

static int on_message_complete(http_parser* parser) {
  Request* p = (Request*)parser;
  p->parse_state = PS_MESSAGE_COMPLETE;
  return 0;
}

// used in event.c
http_parser_settings nyara_request_parse_settings = {
  .on_message_begin = NULL,
  .on_url = on_url,
  .on_status_complete = NULL,
  .on_header_field = on_header_field,
  .on_header_value = on_header_value,
  .on_headers_complete = on_headers_complete,
  .on_body = on_body,
  .on_message_complete = on_message_complete
};

void Init_request_parse(VALUE nyara) {
  str_accept = rb_str_new2("Accept");
  rb_gc_register_mark_object(str_accept);
  method_override_key = rb_str_new2("_method");
  OBJ_FREEZE(method_override_key);
  rb_const_set(nyara, rb_intern("METHOD_OVERRIDE_KEY"), method_override_key);
  nyara_http_methods = rb_const_get(nyara, rb_intern("HTTP_METHODS"));
}
