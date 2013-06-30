/* http accpet* value parser */

#include "nyara.h"
#include <ctype.h>
#include "inc/str_intern.h"

// standard:
//   http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html
// about +q+:
//   http://www.gethifi.com/blog/browser-rest-http-accept-headers
// +level+ is a waste of time:
//   http://stackoverflow.com/questions/13890996/http-accept-level

#define ACCEPT_MAX 1000

// sorted data structure

static double qarray[ACCEPT_MAX];
static long qarray_len = 0;

// return inserted pos
// the sort is "stable", which doesn't swap elements with the same q
static long qarray_insert(double v) {
  long i = qarray_len;
  for (long j = qarray_len - 1; j >= 0; j--) {
    if (qarray[j] < v) {
      i = j;
    } else {
      break;
    }
  }
  memmove(qarray + i + 1, qarray + i, sizeof(double) * (qarray_len - i));
  qarray[i] = v;
  qarray_len++;
  return i;
}

// why truncate:
// 1. normal user never send such long Aceept
// 2. qarray_insert is O(n^2) in worst case, can lead to ddos vulnerability if there are more than 50000 accept entries
static VALUE trim_space_and_truncate(volatile VALUE str) {
  long olen = RSTRING_LEN(str);
  if (olen > ACCEPT_MAX) {
    // todo log this exception
    olen = ACCEPT_MAX;
  }
  str = rb_enc_str_new(RSTRING_PTR(str), olen, u8_encoding);
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

// parse a segment, and store in a sorted array, also updates qarray
static void parse_seg(const char* s, long len, VALUE out) {
  double qval = 1;
  const char* q = find_q(s, len);
  if (q) {
    if (q == s) {
      return;
    }
    char* str_end = (char*)q + 3;
    qval = strtod(q + 3, &str_end);
    if (str_end == q + 3 || isnan(qval) || qval > 3) {
      qval = 1;
    } else if (qval <= 0) {
      return;
    }
    len = q - s;
  }
  long pos = qarray_insert(qval);
  rb_ary_push(out, Qnil); // just to increase cap
  VALUE* out_ptr = RARRAY_PTR(out);
  long out_len = RARRAY_LEN(out); // note this len is +1
  memmove(out_ptr + pos + 1, out_ptr + pos, sizeof(VALUE) * (out_len - pos - 1));
  rb_ary_store(out, pos, rb_enc_str_new(s, len, u8_encoding));
}

VALUE ext_parse_accept_value(VALUE _, volatile VALUE str) {
  if (str == Qnil) {
    return rb_ary_new();
  }

  str = trim_space_and_truncate(str);
  const char* s = RSTRING_PTR(str);
  long len = RSTRING_LEN(str);
  volatile VALUE out = rb_ary_new();
  qarray_len = 0;
  while (len > 0) {
    long seg_len = find_seg(s, len);
    if (seg_len == 0) {
      break;
    }
    parse_seg(s, seg_len, out);
    s += seg_len + 1;
    len -= seg_len + 1;
  }
  return out;
}

void Init_accept(VALUE ext) {
  rb_define_singleton_method(ext, "parse_accept_value", ext_parse_accept_value, 1);
}
