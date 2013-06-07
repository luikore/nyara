// parse path / query / url-encoded body
#include "nyara.h"

static char parse_half_octet(char c) {
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

static size_t parse_url_seg(VALUE path, const char*s, size_t len, char stop_char) {
  const char* last_s = s;
  long last_len = 0;

# define FLUSH_UNESCAPED\
  if (last_len) {\
    rb_str_cat(path, last_s, last_len);\
    last_s += last_len;\
    last_len = 0;\
  }

  size_t i;
  for (i = 0; i < len; i++) {
    if (s[i] == '%') {
      if (i + 2 >= len) {
        last_len++;
        continue;
      }
      char r1 = parse_half_octet(s[i + 1]);
      if (r1 < 0) {
        last_len++;
        continue;
      }
      char r2 = parse_half_octet(s[i + 2]);
      if (r2 < 0) {
        last_len++;
        continue;
      }
      i += 2;
      unsigned char r = ((unsigned char)r1 << 4) | (unsigned char)r2;
      FLUSH_UNESCAPED;
      last_s += 3;
      rb_str_cat(path, (char*)&r, 1);

    } else if (s[i] == stop_char) {
      i++;
      break;

    } else if (s[i] == '+') {
      FLUSH_UNESCAPED;
      rb_str_cat(path, " ", 1);

    } else {
      last_len++;
    }
  }
  FLUSH_UNESCAPED;
# undef FLUSH_UNESCAPED

  return i;
}

// return parsed len, s + return == start of query
size_t nyara_parse_path(VALUE output, const char* s, size_t len) {
  return parse_url_seg(output, s, len, '?');
}

// a, b, c = keys; h[a][b][c] = value
static void hash_aset_keys(VALUE output, VALUE keys, VALUE value, VALUE kv_src) {
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
            kv_src = rb_funcall(kv_src, rb_intern("inspect"), 0);
            // note: StringValueCstr requires VALUE* as param, and can raise another error if there's nul in the string
            rb_raise(rb_eRuntimeError, 
              "error parsing param %.*s: segments[%ld] is not array index (expect to be empty)",
              (int)RSTRING_LEN(kv_src), RSTRING_PTR(kv_src), i);
          }
        } else {
          if (TYPE(output) != T_ARRAY) {
            kv_src = rb_funcall(kv_src, rb_intern("inspect"), 0);
            rb_raise(rb_eRuntimeError,
              "error parsing param %.*s: segments[%ld] is not hash key (expect to be non-empty)",
              (int)RSTRING_LEN(kv_src), RSTRING_PTR(kv_src), i);
          }
        }
      } else {
        volatile VALUE child = next_is_hash_key ? rb_class_new_instance(0, NULL, nyara_param_hash_class) : rb_ary_new();
        rb_hash_aset(output, key, child);
        output = child;
      }
    } else {
      volatile VALUE child = next_is_hash_key ? rb_class_new_instance(0, NULL, nyara_param_hash_class) : rb_ary_new();
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

static VALUE ext_parse_url_encoded_seg(VALUE self, VALUE output, VALUE kv, VALUE v_nested_mode) {
  // let ruby do the split job, it's too nasty in c
  // (note if we parse_url_seg with '&' first, then there may be multiple '='s in one kv)

  const char* s = RSTRING_PTR(kv);
  long len = RSTRING_LEN(kv);
  if (!len) {
    return output;
  }

  int nested_mode = RTEST(v_nested_mode);
  volatile VALUE value = rb_str_new2("");

  // rule out the value part
  {
    const char* value_s = strnstr(s, "=", len);
    if (value_s) {
      value_s++;
      long value_len = s + len - value_s;
      long parsed = parse_url_seg(value, value_s, value_len, '&');
      if (parsed != value_len) {
        rb_raise(rb_eArgError, "separator & in param segment");
      }
      len = value_s - s - 1;
    }
    if (value_s == s) {
      rb_hash_aset(output, rb_str_new2(""), value);
      return output;
    }
  }

  volatile VALUE key = rb_str_new2("");
  if (nested_mode) {
    // todo fault-tolerant?
    long parsed = parse_url_seg(key, s, len, '[');
    if (parsed == len) {
      rb_hash_aset(output, key, value);
      return output;
    }
    s += parsed;
    len -= parsed;
    volatile VALUE keys = rb_ary_new3(1, key);
    while (len) {
      key = rb_str_new2("");
      parsed = parse_url_seg(key, s, len, ']');
      rb_ary_push(keys, key);
      s += parsed;
      len -= parsed;
      if (len) {
        if (s[0] == '[') {
          s++;
          len--;
        } else {
          rb_raise(rb_eRuntimeError, "malformed params: remaining chars in key but not starting with '['");
          return output;
        }
      }
    }
    hash_aset_keys(output, keys, value, kv);
  } else {
    parse_url_seg(key, s, len, '=');
    rb_hash_aset(output, key, value);
  }

  return output;
}

static VALUE ext_parse_path(VALUE self, VALUE output, VALUE input) {
  size_t parsed = nyara_parse_path(output, RSTRING_PTR(input), RSTRING_LEN(input));
  return ULONG2NUM(parsed);
}

void Init_url_encoded(VALUE ext) {
  rb_define_singleton_method(ext, "parse_url_encoded_seg", ext_parse_url_encoded_seg, 3);
  // for test
  rb_define_singleton_method(ext, "parse_path", ext_parse_path, 2);
}
