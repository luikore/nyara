#include <ruby.h>
#include <string.h>
#include <ctype.h>
#include "inc/str_intern.h"

// v_s is changed to the first part, and the second part is returned
static VALUE ext_extract_mime_seg_bang(VALUE self, VALUE v_s) {
  char* s = RSTRING_PTR(v_s);
  long len = RSTRING_LEN(v_s);
  long i = 0;
  for (; i < len; i++) {
    if (isalnum(s[i])) {
      break;
    }
  }
  if (i == len) {
    return Qnil;
  }

  long j = i;
  for (; j < len; j++) {
    if (!isalnum(s[j]) && !strchr("+-./*", s[j])) {
      break;
    }
  }
  if (j > i) {
    memmove(s, s + i, j - i);
    // split string
    len = j - i;
    for (i = 0; i < len; i++) {
      if (s[i] == '/') {
        STR_SET_LEN(v_s, i);
        return rb_str_new(s + i + 1, len - i - 1); // can be zero len, still ok
      }
    }
    STR_SET_LEN(v_s, i);
    return rb_str_new2("");
  }

  return Qnil;
}

static VALUE ext_mime_match_p(VALUE self, VALUE v1, VALUE v2, VALUE m1, VALUE m2) {
  const char* v1_ptr = RSTRING_PTR(v1);
  const char* v2_ptr = RSTRING_PTR(v2);
  const char* m1_ptr = RSTRING_PTR(m1);
  const char* m2_ptr = RSTRING_PTR(m2);
  const long  v1_len = RSTRING_LEN(v1);
  const long  v2_len = RSTRING_LEN(v2);
  const long  m1_len = RSTRING_LEN(m1);
  const long  m2_len = RSTRING_LEN(m2);

# define EQL_STAR(s, len) (len == 1 && s[0] == '*')
# define EQL(s1, len1, s2, len2) (len1 == len2 && strncmp(s1, s2, len1) == 0)

  /*
  if m1 == '*'
    if m2.nil? || m2 == '*'
      return true
    elsif m2 == v2
      return true
    else
      return false
    end
  end
  return false if v1 != m1
  return true if m2.nil? || m2 == '*'
  m2 == v2
  */

  if (EQL_STAR(m1_ptr, m1_len)) {
    if (m2_len == 0 || EQL_STAR(m2_ptr, m2_len)) {
      return Qtrue;
    } else if (EQL(m2_ptr, m2_len, v2_ptr, v2_len)) {
      return Qtrue;
    } else {
      return Qfalse;
    }
  }
  if (!EQL(v1_ptr, v1_len, m1_ptr, m1_len)) {
    return Qfalse;
  }
  if (m2_len == 0 || EQL_STAR(m2_ptr, m2_len)) {
    return Qtrue;
  }
  if (EQL(m2_ptr, m2_len, v2_ptr, v2_len)) {
    return Qtrue;
  } else {
    return Qfalse;
  }
}

void Init_mime(VALUE ext) {
  rb_define_singleton_method(ext, "extract_mime_seg!", ext_extract_mime_seg_bang, 1);
  rb_define_singleton_method(ext, "mime_match?", ext_mime_match_p, 2);
}
