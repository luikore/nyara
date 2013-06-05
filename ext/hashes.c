// provide handy hash variants
#include <ruby.h>
#include <ruby/st.h>
#include "hashes.h"

VALUE nyara_param_hash_class;
VALUE nyara_header_hash_class;
VALUE nyara_config_hash_class;

// NOTE no need to add lots of methods like HashWithIndifferentAccess
//      just return simple hash like rack

static VALUE param_hash_aref(VALUE self, VALUE key) {
  if (TYPE(key) == T_SYMBOL) {
    key = rb_sym_to_s(key);
  }
  return rb_hash_aref(self, key);
}

static VALUE param_hash_aset(VALUE self, VALUE key, VALUE value) {
  if (TYPE(key) == T_SYMBOL) {
    key = rb_sym_to_s(key);
  }
  return rb_hash_aset(self, key, value);
}

void headerlize(VALUE str) {
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
  }
  Check_Type(key, T_STRING);
  key = rb_str_new(RSTRING_PTR(key), RSTRING_LEN(key));
  headerlize(key);
  return key;
}

static VALUE header_hash_aref(VALUE self, VALUE key) {
  return rb_hash_aref(self, header_hash_tidy_key(key));
}

ID id_to_s;
static VALUE header_hash_aset(VALUE self, VALUE key, VALUE value) {
  if (TYPE(value) != T_STRING) {
    value = rb_funcall(value, id_to_s, 0);
  }
  return rb_hash_aset(self, header_hash_tidy_key(key), value);
}

// todo move hash_aset_keys here for config_hash[a,b,c]=v

void Init_hashes(VALUE nyara) {
  id_to_s = rb_intern("to_s");

  nyara_param_hash_class = rb_define_class_under(nyara, "ParamHash", rb_cHash);
  nyara_header_hash_class = rb_define_class_under(nyara, "HeaderHash", nyara_param_hash_class);
  nyara_config_hash_class = rb_define_class_under(nyara, "ConfigHash", nyara_param_hash_class);

  rb_define_method(nyara_param_hash_class, "[]", param_hash_aref, 1);
  rb_define_method(nyara_param_hash_class, "[]=", param_hash_aset, 2);
  rb_define_method(nyara_header_hash_class, "[]", header_hash_aref, 1);
  rb_define_method(nyara_header_hash_class, "[]=", header_hash_aset, 2);
}
