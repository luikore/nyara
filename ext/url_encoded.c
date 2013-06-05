// parse path / query / url-encoded body
#include <ruby.h>
#include "url_encoded.h"
#include "hashes.h"
#include <assert.h>

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
size_t parse_path(VALUE output, const char* s, size_t len) {
  return parse_url_seg(output, s, len, '?');
}

// stolen from hash.c
static int rb_hash_has_key(VALUE hash, VALUE key) {
  if (!RHASH(hash)->ntbl)
    return 0;
  if (st_lookup(RHASH(hash)->ntbl, key, 0))
    return 1;
  return 0;
}

// a, b, c = keys; h[a][b][c] = value
static void hash_aset_keys(VALUE output, VALUE keys, VALUE value) {
  VALUE* arr = RARRAY_PTR(keys);
  long len = RARRAY_LEN(keys);
  assert(len);
  VALUE key = arr[0];
  for (long i = 0; i < len - 1; i++) {
    key = arr[i];
    if (rb_hash_has_key(output, key)) {
      output = rb_hash_aref(output, key);
      Check_Type(output, T_HASH);
    } else {
      volatile VALUE child = rb_class_new_instance(0, NULL, nyara_param_hash_class);
      rb_hash_aset(output, key, child);
      output = child;
    }
  }
  rb_hash_aset(output, key, value);
}

static VALUE ext_parse_param_seg(VALUE output, VALUE kv, VALUE v_nested_mode) {
  // let ruby do the split job, it's too nasty in c
  // (note if we parse_url_seg with '&' first, then there may be multiple '='s in one kv)

  const char* s = RSTRING_PTR(kv);
  long len = RSTRING_LEN(kv);
  int nested_mode = RTEST(v_nested_mode);
  volatile VALUE value = rb_str_new2("");

  // rule out the value part
  {
    const char* value_s = strstr(s, "=");
    long key_len = value_s ? value_s - s - 1 : len;
    if (value_s) {
      parse_url_seg(value, value_s + 1, len - key_len - 1, '&');
    }
    if (value_s == s) {
      rb_hash_aset(output, rb_str_new2(""), value);
      return Qnil;
    }
    len = key_len;
  }

  volatile VALUE key = rb_str_new2("");
  if (nested_mode) {
    // todo fault-tolerant?
    long parsed = parse_url_seg(key, s, len, '[');
    s += parsed;
    len -= parsed;
    if (parsed == len) {
      rb_hash_aset(output, key, value);
      return Qnil;
    }
    volatile VALUE keys = rb_ary_new3(1, key);
    while (len) {
      key = rb_str_new2("");
      parsed = parse_url_seg(key, s, len, ']');
      s += parsed;
      len -= parsed;
      rb_ary_push(keys, key);
      if (len) {
        if (s[0] == '[') {
          s++;
          len--;
        } else {
          // there are remaining chars in key but not starting with '['
          rb_raise(rb_eRuntimeError, "malformat params");
          return Qnil;
        }
      }
    }
    hash_aset_keys(output, keys, value);
  } else {
    parse_url_seg(key, s, len, '=');
    rb_hash_aset(output, key, value);
  }

  return Qnil;
}

static VALUE ext_parse_path(VALUE self, VALUE output, VALUE input) {
  size_t parsed = parse_path(output, RSTRING_PTR(input), RSTRING_LEN(input));
  return ULONG2NUM(parsed);
}

void Init_url_encoded(VALUE ext) {
  rb_define_singleton_method(ext, "parse_param_seg", ext_parse_param_seg, 3);
  // for test
  rb_define_singleton_method(ext, "parse_path", ext_parse_path, 2);
}
