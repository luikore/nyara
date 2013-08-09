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
      last_s++;
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
//
// returns parsed length, including matrix uri params
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

// key and value are for output
// usually should be blank string
// decode into key and value
void nyara_decode_uri_kv(volatile VALUE key, volatile VALUE value, const char* kv_s, long kv_len) {
  const char* s = kv_s;
  long len = kv_len;
  if (!len) {
    rb_raise(rb_eArgError, "empty key=value segment");
  }

  // rule out the value part
  {
    // strnstr is not available on linux :(
    const char* value_s = _strnchr(s, len, '=');
    if (value_s) {
      value_s++;
      long value_len = s + len - value_s;
      long skipped = 0;
      for (;skipped < value_len; skipped++) {
        if (!isspace(value_s[skipped])) {
          break;
        }
      }
      long parsed = _decode_url_seg(value, value_s + skipped, value_len - skipped, '&');
      if (parsed != value_len - skipped) {
        rb_raise(rb_eArgError, "separator & in param segment");
      }
      len = value_s - s - 1;
    }
    // starts with '='
    if (value_s == s) {
      return;
    }
  }
  while (len > 0 && isspace(s[len - 1])) {
    len--;
  }
  _decode_url_seg(key, s, len, '=');
}

static VALUE ext_decode_uri_kv(VALUE _, VALUE str) {
  volatile VALUE k = _new_blank_str();
  volatile VALUE v = _new_blank_str();
  nyara_decode_uri_kv(k, v, RSTRING_PTR(str), RSTRING_LEN(str));
  return rb_ary_new3(2, k, v);
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

  if (ispath) {
    if (_should_escape(c) && c != '+' && c != '/') {
      buf[1] = _hex_char((unsigned char)c / 16);
      buf[2] = _hex_char((unsigned char)c % 16);
      rb_str_cat(s, buf, 3);
    } else {
      rb_str_cat(s, &c, 1);
    }
  } else {
    if (c == ' ') {
      rb_str_cat(s, plus, 1);
    } else if (_should_escape(c)) {
      buf[1] = _hex_char((unsigned char)c / 16);
      buf[2] = _hex_char((unsigned char)c % 16);
      rb_str_cat(s, buf, 3);
    } else {
      rb_str_cat(s, &c, 1);
    }
  }
}

// escape for uri path ('/', '+' are not changed)
// or component ('/', '+' are changed)
static VALUE ext_escape(VALUE _, VALUE s, VALUE v_ispath) {
  Check_Type(s, T_STRING);
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

// caveats:
// - stops at '='
// - matrix uri params and query are ignored
static VALUE ext_unescape(VALUE _, volatile VALUE s, VALUE v_is_path) {
  Check_Type(s, T_STRING);
  if (RTEST(v_is_path)) {
    volatile VALUE output = _new_blank_str();
    if (nyara_parse_path(output, RSTRING_PTR(s), RSTRING_LEN(s))) {
    }
    return output;
  } else {
    volatile VALUE output = _new_blank_str();
    _decode_url_seg(output, RSTRING_PTR(s), RSTRING_LEN(s), '=');
    return output;
  }
}

// concats result into output<br>
// returns parsed length
static VALUE ext_parse_path(VALUE self, VALUE output, VALUE input) {
  long parsed = nyara_parse_path(output, RSTRING_PTR(input), RSTRING_LEN(input));
  return ULONG2NUM(parsed);
}

void Init_url_encoded(VALUE ext) {
  rb_define_singleton_method(ext, "escape", ext_escape, 2);
  rb_define_singleton_method(ext, "unescape", ext_unescape, 2);

  // test only
  rb_define_singleton_method(ext, "decode_uri_kv", ext_decode_uri_kv, 1);
  rb_define_singleton_method(ext, "parse_path", ext_parse_path, 2);
}
