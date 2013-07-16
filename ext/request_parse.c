/* request parse callbacks */

#include "nyara.h"
#include "request.h"
#include <ruby/re.h>

static ID id_update;
static ID id_final;
static VALUE str_accept;
static VALUE str_content_type;
static VALUE method_override_key;
static VALUE nyara_http_methods;

static int mp_header_field(multipart_parser* parser, const char* s, size_t len) {
  Request* p = multipart_parser_get_data(parser);
  if (p->last_part == Qnil) {
    p->last_part = rb_hash_new();
  }

  if (p->last_field == Qnil) {
    p->last_field = rb_enc_str_new(s, len, u8_encoding);
    p->last_value = Qnil;
  } else {
    rb_str_cat(p->last_field, s, len);
  }
  return 0;
}

static int mp_header_value(multipart_parser* parser, const char* s, size_t len) {
  Request* p = multipart_parser_get_data(parser);
  if (p->last_field == Qnil) {
    if (p->last_value == Qnil) {
      p->parse_state = PS_ERROR;
      return 1;
    }
    rb_str_cat(p->last_value, s, len);
  } else {
    nyara_headerlize(p->last_field);
    p->last_value = rb_enc_str_new(s, len, u8_encoding);
    rb_hash_aset(p->last_part, p->last_field, p->last_value);
    p->last_field = Qnil;
  }
  return 0;
}

static int mp_headers_complete(multipart_parser* parser) {
  static VALUE part_class = Qnil;
  if (part_class == Qnil) {
    VALUE nyara = rb_const_get(rb_cModule, rb_intern("Nyara"));
    part_class = rb_const_get(nyara, rb_intern("Part"));
  }

  Request* p = multipart_parser_get_data(parser);
  p->last_field = Qnil;
  p->last_value = Qnil;
  p->last_part = rb_class_new_instance(1, &p->last_part, part_class);
  return 0;
}

static int mp_part_data(multipart_parser* parser, const char* s, size_t len) {
  Request* p = multipart_parser_get_data(parser);
  rb_funcall(p->last_part, id_update, 1, rb_str_new(s, len)); // no need encoding
  return 0;
}

static int mp_part_data_end(multipart_parser* parser) {
  Request* p = multipart_parser_get_data(parser);
  rb_ary_push(p->body, rb_funcall(p->last_part, id_final, 0));
  p->last_part = Qnil;
  return 0;
}

static multipart_parser_settings multipart_settings = {
  .on_header_field = mp_header_field,
  .on_header_value = mp_header_value,
  .on_headers_complete = mp_headers_complete,

  .on_part_data_begin = NULL,
  .on_part_data = mp_part_data,
  .on_part_data_end = mp_part_data_end,

  .on_body_end = NULL
};

static int on_url(http_parser* parser, const char* s, size_t len) {
  Request* p = (Request*)parser;
  p->method = parser->method;

  if (p->path_with_query == Qnil) {
    p->path_with_query = rb_enc_str_new(s, len, u8_encoding);
  } else {
    rb_str_cat(p->path_with_query, s, len);
  }
  return 0;
}

static int on_header_field(http_parser* parser, const char* s, size_t len) {
  Request* p = (Request*)parser;
  if (p->last_field == Qnil) {
    p->last_field = rb_enc_str_new(s, len, u8_encoding);
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
    p->last_value = rb_enc_str_new(s, len, u8_encoding);
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
    nyara_parse_query(p->query, s + query_i, len - query_i);

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

static char* _parse_multipart_boundary(VALUE header) {
  static regex_t* re = NULL;
  static OnigRegion region;
  if (!re) {
    // rfc2046
    // regexp copied from rack
    const char* pattern = "\\Amultipart/.*boundary=\\\"?([^\\\";,]+)\\\"?";
    onig_new(&re, (const UChar*)pattern, (const UChar*)(pattern + strlen(pattern)),
             ONIG_OPTION_NONE, ONIG_ENCODING_ASCII, ONIG_SYNTAX_RUBY, NULL);
    onig_region_init(&region);
  }

  VALUE content_type = rb_hash_aref(header, str_content_type);
  if (content_type == Qnil) {
    return NULL;
  }

  long len = RSTRING_LEN(content_type);
  char* s = RSTRING_PTR(content_type);

  long matched_len = onig_match(re, (const UChar*)s, (const UChar*)(s + len), (const UChar*)s, &region, 0);
  if (matched_len > 0) {
    // multipart-parser needs a buffer to end with '\0', and "--" before boundary
    long boundary_len = region.end[1] - region.beg[1];
    char* boundary_bytes = ALLOC_N(char, boundary_len + 3);
    memcpy(boundary_bytes + 2, s + region.beg[1], boundary_len);
    boundary_bytes[0] = '-';
    boundary_bytes[1] = '-';
    boundary_bytes[boundary_len + 2] = '\0';
    return boundary_bytes;
  } else {
    return NULL;
  }
}

static int on_headers_complete(http_parser* parser) {
  Request* p = (Request*)parser;
  p->last_field = Qnil;
  p->last_value = Qnil;

  _parse_path_and_query(p);
  p->accept = ext_parse_accept_value(Qnil, rb_hash_aref(p->header, str_accept));
  p->parse_state = PS_HEADERS_COMPLETE;

  char* boundary = _parse_multipart_boundary(p->header);
  if (boundary) {
    p->mparser = multipart_parser_init(boundary, &multipart_settings);
    xfree(boundary);
    multipart_parser_set_data(p->mparser, p);
    p->body = rb_ary_new();
  } else {
    p->body = rb_enc_str_new("", 0, u8_encoding);
  }

  return 0;
}

static int on_body(http_parser* parser, const char* s, size_t len) {
  Request* p = (Request*)parser;
  if (p->mparser) {
    size_t parsed = multipart_parser_execute(p->mparser, s, len);
    if (parsed != len) {
      rb_raise(rb_eRuntimeError, "multipart chunk parse failure at %lu", parsed);
    }
    // todo sum total length, if too big, trigger save to tmpfile
  } else {
    rb_str_cat(p->body, s, len);
  }
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

static VALUE ext_parse_multipart_boundary(VALUE _, VALUE header) {
  char* s = _parse_multipart_boundary(header);
  if (s) {
    volatile VALUE res = rb_str_new2(s);
    xfree(s);
    return res;
  } else {
    return Qnil;
  }
}

void Init_request_parse(VALUE nyara, VALUE ext) {
  id_update = rb_intern("update");
  id_final = rb_intern("final");
  str_accept = rb_enc_str_new("Accept", strlen("Accept"), u8_encoding);
  rb_gc_register_mark_object(str_accept);
  str_content_type = rb_enc_str_new("Content-Type", strlen("Content-Type"), u8_encoding);
  rb_gc_register_mark_object(str_content_type);
  method_override_key = rb_enc_str_new("_method", strlen("_method"), u8_encoding);
  OBJ_FREEZE(method_override_key);
  rb_const_set(nyara, rb_intern("METHOD_OVERRIDE_KEY"), method_override_key);
  nyara_http_methods = rb_const_get(nyara, rb_intern("HTTP_METHODS"));

  // for test
  rb_define_singleton_method(ext, "parse_multipart_boundary", ext_parse_multipart_boundary, 1);
}
