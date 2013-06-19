/* efficient Accpet-* value parser in C */

#include "nyara.h"
#include <ctype.h>
#include "inc/str_intern.h"

// standard:
//   http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html
// about +q+:
//   http://www.gethifi.com/blog/browser-rest-http-accept-headers
// +level+ is a waste of time:
//   http://stackoverflow.com/questions/13890996/http-accept-level

// sorted data structure
typedef struct {
  double* qs;
  long len;
  long cap;
} QArray;

static QArray qarray_new() {
  QArray qa = {ALLOC_N(double, 10), 0, 10};
  return qa;
}

// return inserted pos
static long qarray_insert(QArray* qa, double v) {
  if (qa->len == qa->cap) {
    qa->cap *= 2;
    REALLOC_N(qa->qs, double, qa->cap);
  }
  long i = 0;
  for (; i < qa->len; i++) {
    if (qa->qs[i] < v) {
      memmove(qa->qs + i + 1, qa->qs + i, sizeof(double) * (qa->len - i));
      break;
    }
  }
  qa->qs[i] = v;
  qa->len++;
  return i;
}

static void qarray_delete(QArray* qa) {
  xfree(qa->qs);
}

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
static void parse_seg(const char* s, long len, VALUE out, QArray* qa) {
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
  long pos = qarray_insert(qa, qval);
  rb_ary_push(out, Qnil); // just to increase cap
  VALUE* out_ptr = RARRAY_PTR(out);
  long out_len = RARRAY_LEN(out); // note this len is +1
  memmove(out_ptr + pos + 1, out_ptr + pos, sizeof(VALUE) * (out_len - pos - 1));
  rb_ary_store(out, pos, rb_str_new(s, len));
}

VALUE ext_parse_accept_value(VALUE _, VALUE str) {
  str = trim_space(str);
  const char* s = RSTRING_PTR(str);
  long len = RSTRING_LEN(str);
  volatile VALUE out = rb_ary_new();
  QArray qa = qarray_new();
  while (len > 0) {
    long seg_len = find_seg(s, len);
    if (seg_len == 0) {
      break;
    }
    parse_seg(s, seg_len, out, &qa);
    s += seg_len + 1;
    len -= seg_len + 1;
  }
  qarray_delete(&qa);
  return out;
}

void Init_accept(VALUE ext) {
  rb_define_singleton_method(ext, "parse_accept_value", ext_parse_accept_value, 1);
}
