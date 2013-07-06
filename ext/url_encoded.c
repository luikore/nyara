/* url-encoded parsing */

#include "nyara.h"
#include <ctype.h>

static char _half_octet(char c) {
  // there's a faster way but not validating the range:
  //   #define hex2c(c) ((c | 32) % 39 - 9)
  if (c >= '0' && c <= '9') {
    return c - '0';
  } else if (c >= 'A' && c <= 'F') {
    return c - 'A' + 10;
  } else if (c >= 'a' && c <= 'f') {
    return c - 'a' + 10;
  } else {
    return -1;
  }
}

static long _decode_url_seg(VALUE output, const char*s, long len, char stop_char) {
  const char* last_s = s;
  long last_len = 0;

# define FLUSH_UNESCAPED\
  if (last_len) {\
    rb_str_cat(output, last_s, last_len);\
    last_s += last_len;\
    last_len = 0;\
  }

  long i;
  for (i = 0; i < len; i++) {
    if (s[i] == '%') {
      if (i + 2 >= len) {
        last_len++;
        continue;
      }
      char r1 = _half_octet(s[i + 1]);
      if (r1 < 0) {
        last_len++;
        continue;
      }
      char r2 = _half_octet(s[i + 2]);
      if (r2 < 0) {
        last_len++;
        continue;
      }
      i += 2;
      unsigned char r = ((unsigned char)r1 << 4) | (unsigned char)r2;
      FLUSH_UNESCAPED;
      last_s += 3;
      rb_str_cat(output, (char*)&r, 1);

    } else if (s[i] == stop_char) {
      i++;
      break;

    } else if (s[i] == '+') {
      FLUSH_UNESCAPED;
      rb_str_cat(output, " ", 1);

    } else {
      last_len++;
    }
  }
  FLUSH_UNESCAPED;
# undef FLUSH_UNESCAPED

  return i;
}

// s should contain no space
// return parsed len, s + return == start of query
// NOTE it's similar to _decode_url_seg, but:
// - "+" is not escaped
// - matrix uri params (segments starting with ";") are ignored
long nyara_parse_path(VALUE output, const char* s, long len) {
  const char* last_s = s;
  long last_len = 0;

# define FLUSH_UNESCAPED\
  if (last_len) {\
    rb_str_cat(output, last_s, last_len);\
    last_s += last_len;\
    last_len = 0;\
  }

  long i;
  for (i = 0; i < len; i++) {
    if (s[i] == '%') {
      if (i + 2 >= len) {
        last_len++;
        continue;
      }
      char r1 = _half_octet(s[i + 1]);
      if (r1 < 0) {
        last_len++;
        continue;
      }
      char r2 = _half_octet(s[i + 2]);
      if (r2 < 0) {
        last_len++;
        continue;
      }
      i += 2;
      unsigned char r = ((unsigned char)r1 << 4) | (unsigned char)r2;
      FLUSH_UNESCAPED;
      last_s += 3;
      rb_str_cat(output, (char*)&r, 1);

    } else if (s[i] == ';') {
      // skip matrix uri params
      i++;
      for (; i < len; i++) {
        if (s[i] == '?') {
          i++;
          break;
        }
      }
      break;

    } else if (s[i] == '?') {
      i++;
      break;

    } else {
      last_len++;
    }
  }
  FLUSH_UNESCAPED;
# undef FLUSH_UNESCAPED

  return i;
}

static VALUE ext_parse_path(VALUE self, VALUE output, VALUE input) {
  long parsed = nyara_parse_path(output, RSTRING_PTR(input), RSTRING_LEN(input));
  return ULONG2NUM(parsed);
}

static void _error(const char* msg, const char* s, long len, long segment_i) {
  rb_raise(rb_eRuntimeError,
    "error parsing \"%.*s\": segments[%ld] is %s",
    (int)len, s, segment_i, msg);
}

static VALUE _new_child(long hash) {
  return hash ? rb_class_new_instance(0, NULL, nyara_param_hash_class) : rb_ary_new();
}

// a, b, c = keys; h[a][b][c] = value
// the last 2 args are for error report
static void _aset_keys(VALUE output, VALUE keys, VALUE value, const char* kv_s, long kv_len) {
  VALUE* arr = RARRAY_PTR(keys);
  long len = RARRAY_LEN(keys);
  if (!len) {
    rb_bug("bug: aset 0 length key");
    return;
  }

  // first key seg
  volatile VALUE key = arr[0];
  long is_hash_key = 1;

  // middle key segs
  for (long i = 0; i < len - 1; i++) {
    key = arr[i];
    long next_is_hash_key = RSTRING_LEN(arr[i + 1]);
    if (is_hash_key) {
      if (nyara_rb_hash_has_key(output, key)) {
        output = rb_hash_aref(output, key);
        if (next_is_hash_key) {
          if (TYPE(output) != T_HASH) {
            // note: StringValueCStr requires VALUE* as param, and can raise another error if there's nul in the string
            _error("not array index (expect to be empty)", kv_s, kv_len, i);
          }
        } else {
          if (TYPE(output) != T_ARRAY) {
            _error("not hash key (expect to be non-empty)", kv_s, kv_len, i);
          }
        }
      } else {
        volatile VALUE child = _new_child(next_is_hash_key);
        rb_hash_aset(output, key, child);
        output = child;
      }
    } else {
      volatile VALUE child = _new_child(next_is_hash_key);
      rb_ary_push(output, child);
      output = child;
    }
    is_hash_key = next_is_hash_key;
  }

  // terminate key seg: add value
  key = arr[len - 1];
  if (is_hash_key) {
    rb_hash_aset(output, key, value);
  } else {
    rb_ary_push(output, value);
  }
}

static const char* _strnchr(const char* s, long len, char c) {
  for (long i = 0; i < len; i++) {
    if (s[i] == c) {
      return s + i;
    }
  }
  return NULL;
}

static inline VALUE _new_blank_str() {
  return rb_enc_str_new("", 0, u8_encoding);
}

static void _url_encoded_seg(VALUE output, const char* kv_s, long kv_len, int nested_mode) {
  // (note if we _decode_url_seg with '&' first, then there may be multiple '='s in one kv)
  const char* s = kv_s;
  long len = kv_len;
  if (!len) {
    return;
  }

  volatile VALUE value = _new_blank_str();

  // rule out the value part
  {
    // strnstr is not available on linux :(
    const char* value_s = _strnchr(s, len, '=');
    if (value_s) {
      value_s++;
      long value_len = s + len - value_s;
      long parsed = _decode_url_seg(value, value_s, value_len, '&');
      if (parsed != value_len) {
        rb_raise(rb_eArgError, "separator & in param segment");
      }
      len = value_s - s - 1;
    }
    // starts with '='
    if (value_s == s) {
      rb_hash_aset(output, _new_blank_str(), value);
      return;
    }
  }

  volatile VALUE key = _new_blank_str();
  if (nested_mode) {
    // todo fault-tolerant?
    long parsed = _decode_url_seg(key, s, len, '[');
    if (parsed == len) {
      rb_hash_aset(output, key, value);
      return;
    }
    s += parsed;
    len -= parsed;
    volatile VALUE keys = rb_ary_new3(1, key);
    while (len) {
      key = _new_blank_str();
      parsed = _decode_url_seg(key, s, len, ']');
      rb_ary_push(keys, key);
      s += parsed;
      len -= parsed;
      if (len) {
        if (s[0] == '[') {
          s++;
          len--;
        } else {
          rb_raise(rb_eRuntimeError, "malformed params: remaining chars in key but not starting with '['");
          return;
        }
      }
    }
    _aset_keys(output, keys, value, kv_s, kv_len);
  } else {
    _decode_url_seg(key, s, len, '=');
    rb_hash_aset(output, key, value);
  }

  return;
}

static VALUE ext_parse_url_encoded_seg(VALUE self, VALUE output, VALUE kv, VALUE v_nested_mode) {
  _url_encoded_seg(output, RSTRING_PTR(kv), RSTRING_LEN(kv), RTEST(v_nested_mode));
  return output;
}

void nyara_parse_param(VALUE output, const char* s, long len) {
  // split with /[&;] */
  long last_i = 0;
  long i = 0;
  for (; i < len; i++) {
    if (s[i] == '&' || s[i] == ';') {
      if (i > last_i) {
        _url_encoded_seg(output, s + last_i, i - last_i, 1);
      }
      while(i + 1 < len && s[i + 1] == ' ') {
        i++;
      }
      last_i = i + 1;
    }
  }
  if (i > last_i) {
    _url_encoded_seg(output, s + last_i, i - last_i, 1);
  }
}

static VALUE ext_parse_param(VALUE self, VALUE output, VALUE s) {
  nyara_parse_param(output, RSTRING_PTR(s), RSTRING_LEN(s));
  return output;
}

static VALUE _cookie_seg_str_new(const char* s, long len) {
  // trim tailing space
  for (; len > 0; len--) {
    if (s[len - 1] != ' ') {
      break;
    }
  }
  return rb_enc_str_new(s, len, u8_encoding);
}

VALUE ext_parse_cookie(VALUE self, VALUE output, VALUE str) {
  volatile VALUE arr = rb_ary_new();
  const char* s = RSTRING_PTR(str);
  long len = RSTRING_LEN(str);

  // split with / *[,;] */
  long last_i = 0;
  long i = 0;
  for (; i < len; i++) {
    if (s[i] == ',' || s[i] == ';') {
      // char* and len parse_seg
      if (i > last_i) {
        rb_ary_push(arr, _cookie_seg_str_new(s + last_i, i - last_i));
      }
      while(i + 1 < len && s[i + 1] == ' ') {
        i++;
      }
      last_i = i + 1;
    }
  }
  if (i > last_i) {
    rb_ary_push(arr, _cookie_seg_str_new(s + last_i, i - last_i));
  }

  VALUE* arr_p = RARRAY_PTR(arr);
  for (long j = RARRAY_LEN(arr) - 1; j >= 0; j--) {
    _url_encoded_seg(output, RSTRING_PTR(arr_p[j]), RSTRING_LEN(arr_p[j]), 0);
  }
  return output;
}

static bool _should_escape(char c) {
  return !isalnum(c) && c != '_' && c != '.' && c != '-';
}

// prereq: n always < 16
static char _hex_char(unsigned char n) {
  if (n < 10) {
    return '0' + n;
  } else {
    return 'A' + (n - 10);
  }
}

static void _concat_char(VALUE s, char c, bool ispath) {
  static char buf[3] = {'%', 0, 0};
  static char plus[1] = {'+'};

  if (c == ' ') {
    rb_str_cat(s, plus, 1);
  } else if (ispath ? (_should_escape(c) && c != '+' && c != '/') : _should_escape(c)) {
    buf[1] = _hex_char((unsigned char)c / 16);
    buf[2] = _hex_char((unsigned char)c % 16);
    rb_str_cat(s, buf, 3);
  } else {
    rb_str_cat(s, &c, 1);
  }
}

// escape for uri path ('/', '+' are not changed) or component ('/', '+' are changed)
static VALUE ext_escape(VALUE _, VALUE s, VALUE v_ispath) {
  long len = RSTRING_LEN(s);
  const char* ptr = RSTRING_PTR(s);
  volatile VALUE res = rb_str_buf_new(len);
  bool ispath = RTEST(v_ispath);
  for (long i = 0; i < len; i++) {
    _concat_char(res, ptr[i], ispath);
  }
  rb_enc_associate(res, u8_encoding);
  return res;
}

void Init_url_encoded(VALUE ext) {
  rb_define_singleton_method(ext, "parse_param", ext_parse_param, 2);
  rb_define_singleton_method(ext, "parse_cookie", ext_parse_cookie, 2);
  rb_define_singleton_method(ext, "escape", ext_escape, 2);
  // for test
  rb_define_singleton_method(ext, "parse_url_encoded_seg", ext_parse_url_encoded_seg, 3);
  rb_define_singleton_method(ext, "parse_path", ext_parse_path, 2);
}
