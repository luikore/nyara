#include "nyara.h"
#include <ruby/re.h>
#include <string.h>
#include <ctype.h>
#include "inc/str_intern.h"

static regex_t* scan_re;
static OnigRegion* scan_region;

static const char* _strnchr(const char* s, long len, char c) {
  for (long i = 0; i < len; i++) {
    if (s[i] == c) {
      return s + i;
    }
  }
  return NULL;
}

static bool mime_match_seg(const char* m1_ptr, long m1_len, VALUE v1, VALUE v2) {
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
  if (mime_match_seg(RSTRING_PTR(m), RSTRING_LEN(m), v1, v2)) {
    return Qtrue;
  } else {
    return Qfalse;
  }
}

// returns matched ext or nil
VALUE ext_mime_match(VALUE self, VALUE request_accept, VALUE accept_mimes) {
  Check_Type(accept_mimes, T_ARRAY);

  const UChar* s = (const UChar*)RSTRING_PTR(request_accept);
  long len = RSTRING_LEN(request_accept);
  VALUE* values = RARRAY_PTR(accept_mimes);
  long values_len = RARRAY_LEN(accept_mimes);

  while (len > 0) {
    long res = onig_search(scan_re, s, s + len, s, s + len, scan_region, 0);
    if (res < 0) {
      break;
    }
    char* match_s = (char*)(s + scan_region->beg[1]);
    long match_len = scan_region->end[1] - scan_region->beg[1];

    for (long i = 0; i < values_len; i++) {
      Check_Type(values[i], T_ARRAY);
      VALUE* arr = RARRAY_PTR(values[i]);
      VALUE v1 = arr[0];
      VALUE v2 = arr[1];
      if (mime_match_seg(match_s, match_len, v1, v2)) {
        return arr[2];
      }
    }

    s += scan_region->end[0];
    len -= scan_region->end[0];
  }
  return Qnil;
}

void Init_mime(VALUE ext) {
  OnigErrorInfo err_info;
  const char* scan_pattern = "([0-9a-z+\\-\\./*]+)"  "(?:\\s*;[^,]+)?";
  onig_new(&scan_re, (const UChar*)scan_pattern, (const UChar*)(scan_pattern + strlen(scan_pattern)),
           ONIG_OPTION_NONE, ONIG_ENCODING_ASCII, ONIG_SYNTAX_RUBY, &err_info);
  scan_region = onig_region_new();
  rb_define_singleton_method(ext, "mime_match", ext_mime_match, 2);
  // for test
  rb_define_singleton_method(ext, "mime_match_seg", ext_mime_match_seg, 3);
}
