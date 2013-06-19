/* efficient Accpet-* value parser in C */

#include "nyara.h"
#include <ctype.h>
#include "inc/str_intern.h"

// only Accept allows level
//   http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html

static VALUE trim_space(VALUE str) {
  long olen = RSTRING_LEN(str);
  str = rb_str_new(RSTRING_PTR(str), olen);
  char* s = RSTRING_PTR(str);
  long len = 0;
  for (long i = 0; i < olen; i++) {
    if (!isspace(s[i])) {
      s[len++] = s[i];
    }
  }
  STR_SET_LEN(str, len);
  return str;
}

// stopped by ',' or EOS, return seg_len
static long find_seg(const char* s, long len) {
  long i = 0;
  for (; i < len; i++) {
    if (s[i] == ',') {
      break;
    }
  }
  return i;
}

// return first pointer to ';q='
static const char* find_q(const char* s, long len) {
  for (long i = 0; i < (len - 2); i++) {
    if (s[i] == ';' && s[i+1] == 'q' && s[i+2] == '=') {
      return s + i;
    }
  }
  return NULL;
}

// parse a segment, and +out[value] = q+
void parse_seg(VALUE out, const char* s, long len) {
  const char* q = find_q(s, len);
  if (q) {
    if (q == s) {
      return;
    }
    double qval = strtod(q + 3, NULL);
    if (qval > 1) {
      qval = 1;
    } else if (qval < 0) {
      qval = 0;
    }
    rb_hash_aset(out, rb_str_new(s, q - s), DBL2NUM(qval));
  } else {
    rb_hash_aset(out, rb_str_new(s, len), INT2FIX(1));
  }
}

VALUE parse_accept_value(VALUE _, VALUE str) {
  str = trim_space(str);
  const char* s = RSTRING_PTR(str);
  long len = RSTRING_LEN(str);
  volatile VALUE out = rb_hash_new();
  while (len > 0) {
    long seg_len = find_seg(s, len);
    if (seg_len == 0) {
      break;
    }
    parse_seg(out, s, seg_len);
    s += seg_len + 1;
    len -= seg_len + 1;
  }
  return out;
}

void Init_accept(VALUE ext) {
  rb_define_singleton_method(ext, "parse_accept_value", parse_accept_value, 1);
}
