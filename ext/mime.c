#include "nyara.h"
#include <string.h>
#include <ctype.h>
#include "inc/str_intern.h"

static const char* _strnchr(const char* s, long len, char c) {
  for (long i = 0; i < len; i++) {
    if (s[i] == c) {
      return s + i;
    }
  }
  return NULL;
}

// m1, m2: request
// v1, v2: action
static bool _mime_match_seg(const char* m1_ptr, long m1_len, VALUE v1, VALUE v2) {
  const char* m2_ptr = _strnchr(m1_ptr, m1_len, '/');
  long m2_len;
  if (m2_ptr) {
    m2_ptr++;
    m2_len = m1_len - (m2_ptr - m1_ptr);
    m1_len = (m2_ptr - m1_ptr) - 1;
  } else {
    m2_len = 0;
  }

  const char* v1_ptr = RSTRING_PTR(v1);
  const char* v2_ptr = RSTRING_PTR(v2);
  const long  v1_len = RSTRING_LEN(v1);
  const long  v2_len = RSTRING_LEN(v2);

# define EQL_STAR(s, len) (len == 1 && s[0] == '*')
# define EQL(s1, len1, s2, len2) (len1 == len2 && strncmp(s1, s2, len1) == 0)

  if (EQL_STAR(m1_ptr, m1_len)) {
    if (m2_len == 0 || EQL_STAR(m2_ptr, m2_len)) {
      return true;
    } else if (EQL(m2_ptr, m2_len, v2_ptr, v2_len)) {
      return true;
    } else {
      return false;
    }
  }
  if (!EQL(v1_ptr, v1_len, m1_ptr, m1_len)) {
    return false;
  }
  if (m2_len == 0 || EQL_STAR(m2_ptr, m2_len)) {
    return true;
  }
  return EQL(m2_ptr, m2_len, v2_ptr, v2_len);

# undef EQL
# undef EQL_STAR
}

// for test
static VALUE ext_mime_match_seg(VALUE self, VALUE m, VALUE v1, VALUE v2) {
  if (_mime_match_seg(RSTRING_PTR(m), RSTRING_LEN(m), v1, v2)) {
    return Qtrue;
  } else {
    return Qfalse;
  }
}

// +request_accept+ is an array of mime types
// +action_accept+ is an array of split mime type and format, e.g. +[['application', 'javascript', 'js']]+
// returns matched format or nil
VALUE ext_mime_match(VALUE self, VALUE request_accept, VALUE action_accept) {
  Check_Type(request_accept, T_ARRAY);
  Check_Type(action_accept, T_ARRAY);

  VALUE* requests = RARRAY_PTR(request_accept);
  long requests_len = RARRAY_LEN(request_accept);
  VALUE* values = RARRAY_PTR(action_accept);
  long values_len = RARRAY_LEN(action_accept);

  for (long j = 0; j < requests_len; j++) {
    char* s = RSTRING_PTR(requests[j]);
    long len = RSTRING_LEN(requests[j]);
    for (long i = 0; i < values_len; i++) {
      Check_Type(values[i], T_ARRAY);
      VALUE* arr = RARRAY_PTR(values[i]);
      if (_mime_match_seg(s, len, arr[0], arr[1])) {
        return arr[2];
      }
    }
  }
  return Qnil;
}

void Init_mime(VALUE ext) {
  rb_define_singleton_method(ext, "mime_match", ext_mime_match, 2);
  // for test
  rb_define_singleton_method(ext, "mime_match_seg", ext_mime_match_seg, 3);
}
