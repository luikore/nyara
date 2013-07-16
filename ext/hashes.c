/* handy hash variants */

#include "nyara.h"
#include <ruby/st.h>
#include "inc/str_intern.h"
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

// prereq: name should be already url decoded <br>
// "a[b][][c]" ==> ["a", "b", "", "c"]
static VALUE param_hash_split_name(VALUE _, VALUE name) {
  Check_Type(name, T_STRING);
  long len = RSTRING_LEN(name);
  if (len == 0) {
    rb_raise(rb_eArgError, "name should not be empty");
  }
  char* s = RSTRING_PTR(name);

  // NOTE it's OK to compare utf-8 string with ascii chars, because utf-8 code units are either:
  // - byte with 0 in highest nibble, which is ascii char
  // - bytes with 1 in highest nibble, which can not be eql to any ascii char

  volatile VALUE keys = rb_ary_new();
  long i;
  for (i = 0; i < len; i++) {
    if (s[i] == '[') {
      if (i == 0) {
        rb_raise(rb_eArgError, "bad name (starts with '[')");
      }
      volatile VALUE key = rb_enc_str_new(s, i, u8_encoding);
      rb_ary_push(keys, key);
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
          volatile VALUE key = rb_enc_str_new(s + last_j, j - last_j, u8_encoding);
          rb_ary_push(keys, key);
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
  return keys;
}

// assume keys = [a, b, c] ==> self[a][b][c] = value
// blank keys will be translated as array keys.
// created hashes has the same class with output
// todo make 2 versions, one for public use
static VALUE param_hash_nested_aset(VALUE output, volatile VALUE keys, VALUE value) {
  Check_Type(keys, T_ARRAY);
  VALUE* arr = RARRAY_PTR(keys);
  long len = RARRAY_LEN(keys);
  if (!len) {
    rb_raise(rb_eArgError, "aset 0 length key");
    return Qnil;
  }
  volatile VALUE klass = rb_obj_class(output);

  // first key seg
  long is_hash_key = 1;

  // middle key segs
  for (long i = 0; i < len - 1; i++) {
    long next_is_hash_key = RSTRING_LEN(arr[i + 1]);
#   define NEW_CHILD(child) \
      volatile VALUE child = (next_is_hash_key ? rb_class_new_instance(0, NULL, klass) : rb_ary_new());

    if (is_hash_key) {
      if (nyara_rb_hash_has_key(output, arr[i])) {
        output = rb_hash_aref(output, arr[i]);
        if (next_is_hash_key) {
          if (TYPE(output) != T_HASH) {
            rb_raise(rb_eRuntimeError, "hash key at:%ld conflicts with array", i + 1);
          }
        } else {
          if (TYPE(output) != T_ARRAY) {
            rb_raise(rb_eRuntimeError, "array key at:%ld conflicts with hash", i + 1);
          }
        }
      } else {
        NEW_CHILD(child);
        rb_hash_aset(output, arr[i], child);
        output = child;
      }
    } else {
      NEW_CHILD(child);
      rb_ary_push(output, child);
      output = child;
    }
    is_hash_key = next_is_hash_key;
#   undef NEW_CHILD
  }

  // terminate key seg: add value
  if (is_hash_key) {
    rb_hash_aset(output, arr[len - 1], value);
  } else {
    rb_ary_push(output, value);
  }
  return output;
}

// s, len is the raw kv string
// returns trailing length
static void _kv(VALUE output, const char* s, long len, bool nested_mode) {
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
    if (nested_mode) {
      volatile VALUE keys = param_hash_split_name(Qnil, key);
      param_hash_nested_aset(output, keys, value);
    } else {
      rb_hash_aset(output, key, value);
    }
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
        _kv(output, s + i + 1, last_i - i, false);
      }
      last_i = i - 1;
    }
  }
  if (last_i > 0) {
    _kv(output, s, last_i + 1, false);
  }
  return output;
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
        _kv(output, s + last_i, i - last_i, true);
      }
      last_i = i + 1;
    }
  }
  if (i > last_i) {
    _kv(output, s + last_i, i - last_i, true);
  }
  return output;
}

static VALUE _tmp_str;

static VALUE _parse_cookie_func(VALUE output) {
  param_hash_parse_cookie(Qnil, output, _tmp_str);
  return Qnil;
}

void nyara_parse_cookie(VALUE output, VALUE str) {
  _tmp_str = str;
  int err = 0;
  rb_protect(_parse_cookie_func, output, &err);
}

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

static int header_hash_merge_func(VALUE k, VALUE v, VALUE self_st) {
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
  rb_hash_foreach(other, header_hash_merge_func, (VALUE)t);
  return self;
}

static int header_hash_serialize_func(VALUE k, VALUE v, VALUE arr) {
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
  rb_hash_foreach(self, header_hash_serialize_func, arr);
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
  rb_define_singleton_method(nyara_param_hash_class, "split_name", param_hash_split_name, 1);
  rb_define_singleton_method(nyara_param_hash_class, "parse_param", param_hash_parse_param, 2);
  rb_define_singleton_method(nyara_param_hash_class, "parse_cookie", param_hash_parse_cookie, 2);

  rb_define_method(nyara_header_hash_class, "[]", header_hash_aref, 1);
  rb_define_method(nyara_header_hash_class, "key?", header_hash_key_p, 1);
  rb_define_method(nyara_header_hash_class, "[]=", header_hash_aset, 2);
  rb_define_method(nyara_header_hash_class, "reverse_merge!", header_hash_reverse_merge_bang, 1);
  rb_define_method(nyara_header_hash_class, "serialize", header_hash_serialize, 0);

  // for internal use
  rb_define_method(nyara_header_hash_class, "_aset", rb_hash_aset, 2);
  rb_define_method(nyara_header_hash_class, "_aref", rb_hash_aref, 1);
}
