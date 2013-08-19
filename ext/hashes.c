/* handy hash variants */

#include "nyara.h"
#include <ruby/st.h>
#include <assert.h>
#include "inc/str_intern.h"
#include "inc/ary_intern.h"
#include <ctype.h>

VALUE nyara_param_hash_class;
VALUE nyara_header_hash_class;
VALUE nyara_config_hash_class;

// stolen from hash.c
static bool nyara_rb_hash_has_key(VALUE hash, VALUE key) {
  if (!RHASH(hash)->ntbl)
    return false;
  if (st_lookup(RHASH(hash)->ntbl, key, 0))
    return true;
  return false;
}

// NOTE no need to add lots of methods like HashWithIndifferentAccess
//      just return simple hash like rack

static VALUE param_hash_aref(VALUE self, VALUE key) {
  if (TYPE(key) == T_SYMBOL) {
    key = rb_sym_to_s(key);
  }
  return rb_hash_aref(self, key);
}

static VALUE param_hash_key_p(VALUE self, VALUE key) {
  if (TYPE(key) == T_SYMBOL) {
    key = rb_sym_to_s(key);
  }
  return nyara_rb_hash_has_key(self, key) ? Qtrue : Qfalse;
}

static VALUE param_hash_aset(VALUE self, VALUE key, VALUE value) {
  if (TYPE(key) == T_SYMBOL) {
    key = rb_sym_to_s(key);
  }
  return rb_hash_aset(self, key, value);
}

// replace content of keys with split name
// existing prefices are not replaced for minimal allocation
static VALUE _split_name(volatile VALUE name) {
  long len = RSTRING_LEN(name);
  if (len == 0) {
    rb_raise(rb_eArgError, "name should not be empty");
  }
  char* s = RSTRING_PTR(name);

  volatile VALUE keys = rb_ary_new();
# define INSERT(s, len) \
    rb_ary_push(keys, rb_enc_str_new(s, len, u8_encoding))

  long i;
  for (i = 0; i < len; i++) {
    if (s[i] == '[') {
      if (i == 0) {
        rb_raise(rb_eArgError, "bad name (starts with '[')");
      }
      INSERT(s, i);
      i++;
      break;
    } else if (s[i] == ']') {
      rb_raise(rb_eArgError, "bad name (unmatched ']')");
    }
  }

  if (RARRAY_LEN(keys)) {
    if (s[len - 1] != ']') {
      rb_raise(rb_eArgError, "bad name (not end with ']')");
    }
    long last_j = i;
    for (long j = last_j; j < len; j++) {
      if (s[j] == ']') {
        if (j == len - 1 || s[j + 1] == '[') {
          INSERT(s + last_j, j - last_j);
          last_j = j + 2; // fine for last round
          j++;
        } else {
          rb_raise(rb_eArgError, "bad name (']' not followed by '[')");
        }
      } else if (s[j] == '[') {
        rb_raise(rb_eArgError, "bad name (nested '[')");
      }
    }
  } else {
    // single key
    rb_ary_push(keys, name);
  }
# undef INSERT
  return keys;
}

// prereq: name should be already url decoded <br>
// "a[b][][c]" ==> ["a", "b", "", "c"]
static VALUE param_hash_split_name(VALUE _, VALUE name) {
  Check_Type(name, T_STRING);
  return _split_name(name);
}

// prereq: all elements in keys are string
static VALUE param_hash_nested_aref(volatile VALUE obj, VALUE keys) {
  Check_Type(keys, T_ARRAY);
  VALUE* keys_ptr = RARRAY_PTR(keys);
  long keys_len = RARRAY_LEN(keys);

  for (long i = 0; i < keys_len; i++) {
    volatile VALUE key = keys_ptr[i];
    if (RSTRING_LEN(key)) {
      if (rb_obj_is_kind_of(obj, rb_cHash)) {
        obj = rb_hash_aref(obj, key);
      } else {
        return Qnil;
      }
    } else {
      if (rb_obj_is_kind_of(obj, rb_cArray)) {
        long arr_len = RARRAY_LEN(obj);
        if (arr_len) {
          obj = RARRAY_PTR(obj)[arr_len - 1];
        } else {
          return Qnil;
        }
      } else {
        return Qnil;
      }
    }
  }
  return obj;
}

// prereq: len > 0
static void _nested_aset(VALUE output, volatile VALUE keys, VALUE value) {
  volatile VALUE klass = rb_obj_class(output);
  VALUE* arr = RARRAY_PTR(keys);
  long len = RARRAY_LEN(keys);

  // first key seg
  if (!RSTRING_LEN(arr[0])) {
    rb_raise(rb_eRuntimeError, "array key at:0 conflicts with hash");
  }
  bool is_hash_key = true;

# define NEW_CHILD(child) \
    volatile VALUE child = (next_is_hash_key ? rb_class_new_instance(0, NULL, klass) : rb_ary_new());
# define ASSERT_HASH \
    if (TYPE(output) != T_HASH) {\
      rb_raise(rb_eTypeError, "hash key at:%ld conflicts with array", i + 1);\
    }
# define ASSERT_ARRAY \
    if (TYPE(output) != T_ARRAY) {\
      rb_raise(rb_eTypeError, "array key at:%ld conflicts with hash", i + 1);\
    }
# define CHECK_NEXT \
    if (next_is_hash_key) {\
      ASSERT_HASH;\
    } else {\
      ASSERT_ARRAY;\
    }

  // special treatment to array keys according to last 2 segments:
  // *[][foo] append new hash if already exists
  //
  // normal cases:
  // *[]      just push
  // *[foo]   find last elem first
  // *[]*     find last elem first

  // middle key segs
  for (long i = 0; i < len - 1; i++) {
    bool next_is_hash_key = RSTRING_LEN(arr[i + 1]);
    if (is_hash_key) {
      if (nyara_rb_hash_has_key(output, arr[i])) {
        output = rb_hash_aref(output, arr[i]);
        CHECK_NEXT;
      } else {
        NEW_CHILD(child);
        rb_hash_aset(output, arr[i], child);
        output = child;
      }
    } else {
      // array key, try to use the last elem
      long output_len = RARRAY_LEN(output);
      if (output_len) {
        bool append = false;
        if (i == len - 2 && next_is_hash_key) {
          volatile VALUE next_hash = RARRAY_PTR(output)[output_len - 1];
          if (nyara_rb_hash_has_key(next_hash, arr[i + 1])) {
            append = true;
          }
        }
        if (append) {
          volatile VALUE child = rb_class_new_instance(0, NULL, klass);
          rb_ary_push(output, child);
          output = child;
        } else {
          output = RARRAY_PTR(output)[output_len - 1];
          CHECK_NEXT;
        }
      } else {
        NEW_CHILD(child);
        rb_ary_push(output, child);
        output = child;
      }
    }
    is_hash_key = next_is_hash_key;
  }

# undef CHECK_NEXT
# undef ASSERT_ARRAY
# undef ASSERT_HASH
# undef NEW_CHILD

  // terminate seg
  if (is_hash_key) {
    rb_hash_aset(output, arr[len - 1], value);
  } else {
    rb_ary_push(output, value);
  }
}

// prereq: all elements in keys are string
// assume keys = [a, b, c] ==> self[a][b][c] = value
// blank keys will be translated as array keys.
// created hashes has the same class with output
static VALUE param_hash_nested_aset(VALUE output, VALUE keys, VALUE value) {
  Check_Type(keys, T_ARRAY);
  long len = RARRAY_LEN(keys);
  if (!len) {
    rb_raise(rb_eArgError, "aset 0 length key");
    return Qnil;
  }
  _nested_aset(output, keys, value);
  return output;
}

// s, len is the raw kv string
static void _cookie_kv(VALUE output, const char* s, long len) {
  // strip
  for (; len > 0; len--, s++) {
    if (!isspace(*s)) {
      break;
    }
  }
  for (; len > 0; len--) {
    if (!isspace(s[len - 1])) {
      break;
    }
  }
  if (len > 0) {
    volatile VALUE key = rb_enc_str_new("", 0, u8_encoding);
    volatile VALUE value = rb_enc_str_new("", 0, u8_encoding);
    nyara_decode_uri_kv(key, value, s, len);
    rb_hash_aset(output, key, value);
  }
}

// class method:
// insert parsing result into output
static VALUE param_hash_parse_cookie(VALUE _, VALUE output, VALUE str) {
  Check_Type(output, T_HASH);
  Check_Type(str, T_STRING);
  if (rb_obj_is_kind_of(output, nyara_header_hash_class)) {
    rb_raise(rb_eArgError, "can not parse cookie into HeaderHash");
  }
  const char* s = RSTRING_PTR(str);
  long len = RSTRING_LEN(str);

  // split with /[,;]/
  // scan in reverse order because entries on the left of the cookie has greater priority
  long i = len - 1;
  long last_i = i;
  for (; i >= 0; i--) {
    if (s[i] == ',' || s[i] == ';') {
      if (i < last_i) {
        _cookie_kv(output, s + i + 1, last_i - i);
      }
      last_i = i - 1;
    }
  }
  if (last_i > 0) {
    _cookie_kv(output, s, last_i + 1);
  }
  return output;
}

// s, len is the raw kv string
static void _param_kv(VALUE output, const char* s, long len) {
  // strip
  for (; len > 0; len--, s++) {
    if (!isspace(*s)) {
      break;
    }
  }
  for (; len > 0; len--) {
    if (!isspace(s[len - 1])) {
      break;
    }
  }
  if (len <= 0) {
    return;
  }

  volatile VALUE name = rb_enc_str_new("", 0, u8_encoding);
  volatile VALUE value = rb_enc_str_new("", 0, u8_encoding);
  nyara_decode_uri_kv(name, value, s, len);
  _nested_aset(output, _split_name(name), value);
}

// class method:
// insert parsing result into output
static VALUE param_hash_parse_param(VALUE _, VALUE output, VALUE str) {
  Check_Type(output, T_HASH);
  Check_Type(str, T_STRING);
  if (rb_obj_is_kind_of(output, nyara_header_hash_class)) {
    rb_raise(rb_eArgError, "can not parse param into HeaderHash");
  }
  const char* s = RSTRING_PTR(str);
  long len = RSTRING_LEN(str);

  // split with /[&;]/
  long i = 0;
  long last_i = i;
  for (; i < len; i++) {
    if (s[i] == '&' || s[i] == ';') {
      if (i > last_i) {
        _param_kv(output, s + last_i, i - last_i);
      }
      last_i = i + 1;
    }
  }
  if (i > last_i) {
    _param_kv(output, s + last_i, i - last_i);
  }
  return output;
}

static VALUE _tmp_str;

static VALUE _parse_query_func(VALUE output) {
  param_hash_parse_param(Qnil, output, _tmp_str);
  return Qnil;
}

// do not raise error
void nyara_parse_query(VALUE output, const char* s, long len) {
  volatile VALUE str = rb_str_new(s, len);
  _tmp_str = str;
  int err = 0;
  rb_protect(_parse_query_func, output, &err);
}

void nyara_headerlize(VALUE str) {
  char* s = (char*)RSTRING_PTR(str);
  long len = RSTRING_LEN(str);
  int border = 1;
  for (long i = 0; i < len; i++) {
    if (s[i] == '-') {
      border = 1;
      continue;
    }
    if (border) {
      // note this is most reliable way,
      // with <ctype.h> we have to deal with locale...
      if (s[i] >= 'a' && s[i] <= 'z') {
        s[i] = 'A' + (s[i] - 'a');
      }
      border = 0;
    } else {
      if (s[i] >= 'A' && s[i] <= 'Z') {
        s[i] = 'a' + (s[i] - 'A');
      }
    }
  }
}

static VALUE header_hash_tidy_key(VALUE key) {
  if (TYPE(key) == T_SYMBOL) {
    key = rb_sym_to_s(key);
  } else {
    Check_Type(key, T_STRING);
    key = rb_enc_str_new(RSTRING_PTR(key), RSTRING_LEN(key), u8_encoding);
  }
  nyara_headerlize(key);
  return key;
}

static VALUE header_hash_aref(VALUE self, VALUE key) {
  return rb_hash_aref(self, header_hash_tidy_key(key));
}

static VALUE header_hash_key_p(VALUE self, VALUE key) {
  return nyara_rb_hash_has_key(self, header_hash_tidy_key(key)) ? Qtrue : Qfalse;
}

static ID id_to_s;
static VALUE header_hash_aset(VALUE self, VALUE key, VALUE value) {
  key = header_hash_tidy_key(key);
  if (TYPE(value) != T_STRING) {
    value = rb_funcall(value, id_to_s, 0);
  }

  return rb_hash_aset(self, key, value);
}

static int _reverse_merge_func(VALUE k, VALUE v, VALUE self_st) {
  st_table* t = (st_table*)self_st;
  if (!st_is_member(t, k)) {
    st_insert(t, (st_data_t)k, (st_data_t)v);
  }
  return ST_CONTINUE;
}

static VALUE header_hash_reverse_merge_bang(VALUE self, VALUE other) {
  if (!rb_obj_is_kind_of(other, nyara_header_hash_class)) {
    rb_raise(rb_eArgError, "need a Nyara::HeaderHash");
  }
  st_table* t = rb_hash_tbl(self);
  rb_hash_foreach(other, _reverse_merge_func, (VALUE)t);
  return self;
}

static int _serialize_func(VALUE k, VALUE v, VALUE arr) {
  long vlen = RSTRING_LEN(v);
  // deleted field
  if (vlen == 0) {
    return ST_CONTINUE;
  }

  long klen = RSTRING_LEN(k);
  long capa = klen + vlen + 4;
  volatile VALUE s = rb_str_buf_new(capa);
  sprintf(RSTRING_PTR(s), "%.*s: %.*s\r\n", (int)klen, RSTRING_PTR(k), (int)vlen, RSTRING_PTR(v));
  STR_SET_LEN(s, capa);
  rb_enc_associate(s, u8_encoding);
  rb_ary_push(arr, s);
  return ST_CONTINUE;
}

static VALUE header_hash_serialize(VALUE self) {
# ifdef HAVE_RB_ARY_NEW_CAPA
  long size = (!RHASH(self)->ntbl ? RHASH(self)->ntbl->num_entries : 0);
  volatile VALUE arr = rb_ary_new_capa(size);
# else
  volatile VALUE arr = rb_ary_new();
# endif
  rb_hash_foreach(self, _serialize_func, arr);
  return arr;
}

void Init_hashes(VALUE nyara) {
  id_to_s = rb_intern("to_s");

  nyara_param_hash_class = rb_define_class_under(nyara, "ParamHash", rb_cHash);
  nyara_header_hash_class = rb_define_class_under(nyara, "HeaderHash", nyara_param_hash_class);
  nyara_config_hash_class = rb_define_class_under(nyara, "ConfigHash", nyara_param_hash_class);

  rb_define_method(nyara_param_hash_class, "[]", param_hash_aref, 1);
  rb_define_method(nyara_param_hash_class, "key?", param_hash_key_p, 1);
  rb_define_method(nyara_param_hash_class, "[]=", param_hash_aset, 2);
  rb_define_method(nyara_param_hash_class, "nested_aset", param_hash_nested_aset, 2);
  rb_define_method(nyara_param_hash_class, "nested_aref", param_hash_nested_aref, 1);
  rb_define_singleton_method(nyara_param_hash_class, "split_name", param_hash_split_name, 1);
  rb_define_singleton_method(nyara_param_hash_class, "parse_param", param_hash_parse_param, 2);
  rb_define_singleton_method(nyara_param_hash_class, "parse_cookie", param_hash_parse_cookie, 2);

  rb_define_method(nyara_header_hash_class, "[]", header_hash_aref, 1);
  rb_define_method(nyara_header_hash_class, "key?", header_hash_key_p, 1);
  rb_define_method(nyara_header_hash_class, "[]=", header_hash_aset, 2);
  rb_define_method(nyara_header_hash_class, "reverse_merge!", header_hash_reverse_merge_bang, 1);
  rb_define_method(nyara_header_hash_class, "serialize", header_hash_serialize, 0);

  // for internal use
  rb_define_method(nyara_param_hash_class, "_aset", rb_hash_aset, 2);
  rb_define_method(nyara_param_hash_class, "_aref", rb_hash_aref, 1);
}
