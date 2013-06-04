#include <ruby.h>

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

// return parsed len, s + return == start of query
size_t parse_path(VALUE path, const char*s, size_t len) {
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

    } else if (s[i] == '?') {
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

static VALUE ext_parse_path(VALUE self, VALUE output, VALUE input) {
  size_t parsed = parse_path(output, RSTRING_PTR(input), RSTRING_LEN(input));
  return ULONG2NUM(parsed);
}

void Init_escape(VALUE ext) {
  // for test
  rb_define_singleton_method(ext, "parse_path", ext_parse_path, 2);
}
