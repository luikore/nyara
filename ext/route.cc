extern "C" {
#include "nyara.h"
}
#include <ruby/re.h>
#include <vector>
#include <map>
#include "str_intern.h"

struct RouteEntry {
  // note on order: scope is supposed to be the last, but when searching, is_sub is checked first
  bool is_sub; // = last_prefix.start_with? prefix
  char* prefix;
  long prefix_len;
  regex_t *suffix_re;
  VALUE controller;
  VALUE id; // symbol, doesn't need mark
  std::vector<ID> conv;
  VALUE scope;
  char* suffix; // only for inspect
  long suffix_len;

  // don't make it destructor, or it could be called twice if on stack
  void dealloc() {
    if (prefix) {
      xfree(prefix);
      prefix = NULL;
    }
    if (suffix_re) {
      onig_free(suffix_re);
      suffix_re = NULL;
    }
    if (suffix) {
      xfree(suffix);
      suffix = NULL;
    }
  }
};

typedef std::vector<RouteEntry> RouteEntries;
static std::map<enum http_method, RouteEntries*> route_map;
static OnigRegion region; // we can reuse the region without worrying thread safety
static ID id_to_s;
static VALUE nyara_http_methods;

static bool start_with(const char* a, long a_len, const char* b, long b_len) {
  if (b_len > a_len) {
    return false;
  }
  for (size_t i = 0; i < b_len; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

static enum http_method canonicalize_http_method(VALUE m) {
  VALUE method_num;
  if (TYPE(m) == T_STRING) {
    method_num = rb_hash_aref(nyara_http_methods, m);
  } else {
    method_num = m;
  }
  Check_Type(method_num, T_FIXNUM);
  return (enum http_method)FIX2INT(method_num);
}

static VALUE ext_clear_route(VALUE req) {
  for (auto i = route_map.begin(); i != route_map.end(); ++i) {
    RouteEntries* entries = i->second;
    for (auto j = entries->begin(); j != entries->end(); ++j) {
      j->dealloc();
    }
    delete entries;
  }
  route_map.clear();
  return Qnil;
}

static VALUE ext_register_route(VALUE self, VALUE v_e) {
  // get route entries
  enum http_method m = canonicalize_http_method(rb_iv_get(v_e, "@http_method"));
  RouteEntries* route_entries;
  auto map_iter = route_map.find(m);
  if (map_iter == route_map.end()) {
    route_entries = new RouteEntries();
    route_map[m] = route_entries;
  } else {
    route_entries = map_iter->second;
  }

  // prefix
  VALUE v_prefix = rb_iv_get(v_e, "@prefix");
  long prefix_len = RSTRING_LEN(v_prefix);
  char* prefix = ALLOC_N(char, prefix_len);
  memcpy(prefix, RSTRING_PTR(v_prefix), prefix_len);

  // check if prefix is substring of last entry
  bool is_sub = false;
  if (route_entries->size()) {
    is_sub = start_with(route_entries->rbegin()->prefix, route_entries->rbegin()->prefix_len, prefix, prefix_len);
  }

  // suffix
  VALUE v_suffix = rb_iv_get(v_e, "@suffix");
  long suffix_len = RSTRING_LEN(v_suffix);
  char* suffix = ALLOC_N(char, suffix_len);
  memcpy(suffix, RSTRING_PTR(v_suffix), suffix_len);
  regex_t* suffix_re;
  OnigErrorInfo err_info;
  onig_new(&suffix_re, (const UChar*)suffix, (const UChar*)(suffix + suffix_len),
           ONIG_OPTION_NONE, ONIG_ENCODING_ASCII, ONIG_SYNTAX_RUBY, &err_info);

  std::vector<ID> _conv;
  RouteEntry e = {
    .is_sub = is_sub,
    .prefix = prefix,
    .prefix_len = prefix_len,
    .suffix_re = suffix_re,
    .suffix = suffix,
    .suffix_len = suffix_len,
    .controller = rb_iv_get(v_e, "@controller"),
    .id = rb_iv_get(v_e, "@id"),
    .conv = _conv,
    .scope = rb_iv_get(v_e, "@scope")
  };

  // conv
  VALUE v_conv = rb_iv_get(v_e, "@conv");
  VALUE* conv_ptr = RARRAY_PTR(v_conv);
  long conv_len = RARRAY_LEN(v_conv);
  if (onig_number_of_captures(suffix_re) != conv_len) {
    e.dealloc();
    rb_raise(rb_eRuntimeError, "number of captures mismatch");
  }
  for (long i = 0; i < conv_len; i++) {
    ID conv_id = SYM2ID(conv_ptr[i]);
    e.conv.push_back(conv_id);
  }

  route_entries->push_back(e);
  return Qnil;
}

static VALUE ext_list_route(VALUE self) {
  // note: prevent leak with init nil
  volatile VALUE arr = Qnil;
  volatile VALUE e = Qnil;
  volatile VALUE prefix = Qnil;
  volatile VALUE conv = Qnil;

  volatile VALUE route_hash = rb_hash_new();
  for (auto j = route_map.begin(); j != route_map.end(); j++) {
    RouteEntries* route_entries = j->second;
    VALUE arr = rb_ary_new();
    rb_hash_aset(route_hash, rb_str_new2(http_method_str(j->first)), arr);
    for (auto i = route_entries->begin(); i != route_entries->end(); i++) {
      e = rb_ary_new();
      rb_ary_push(e, i->is_sub ? Qtrue : Qfalse);
      rb_ary_push(e, i->scope);
      rb_ary_push(e, rb_str_new(i->prefix, i->prefix_len));
      rb_ary_push(e, rb_str_new(i->suffix, i->suffix_len));
      rb_ary_push(e, i->controller);
      rb_ary_push(e, i->id);
      conv = rb_ary_new();
      for (size_t j = 0; j < i->conv.size(); j++) {
        rb_ary_push(conv, ID2SYM(i->conv[j]));
      }
      rb_ary_push(e, conv);
      rb_ary_push(arr, e);
    }
  }
  return route_hash;
}

static VALUE build_args(const char* suffix, std::vector<ID>& conv) {
  volatile VALUE args = rb_ary_new();
  volatile VALUE str = rb_str_new2("");
  long last_len = 0;
  for (size_t j = 0; j < conv.size(); j++) {
    const char* capture_ptr = suffix + region.beg[j+1];
    long capture_len = region.end[j+1] - region.beg[j+1];
    if (conv[j] == id_to_s) {
      rb_ary_push(args, rb_str_new(capture_ptr, capture_len));
    } else if (capture_len == 0) {
      rb_ary_push(args, Qnil);
    } else {
      if (capture_len > last_len) {
        RESIZE_CAPA(str, capture_len);
        last_len = capture_len;
      }
      memcpy(RSTRING_PTR(str), capture_ptr, capture_len);
      STR_SET_LEN(str, capture_len);
      rb_ary_push(args, rb_funcall(str, conv[j], 0)); // hex, to_i, to_f
    }
  }
  return args;
}

extern "C"
RouteResult nyara_lookup_route(enum http_method method_num, VALUE vpath) {
  RouteResult r = {Qnil, Qnil, Qnil};
  auto map_iter = route_map.find(method_num);
  if (map_iter == route_map.end()) {
    return r;
  }
  RouteEntries* route_entries = map_iter->second;

  const char* path = RSTRING_PTR(vpath);
  long len = RSTRING_LEN(vpath);
  // must iterate all
  bool last_matched = false;
  for (auto i = route_entries->begin(); i != route_entries->end(); ++i) {
    bool matched;
    if (i->is_sub && last_matched) { // save a bit compare
      matched = last_matched;
    } else {
      matched = start_with(path, len, i->prefix, i->prefix_len);
    }
    last_matched = matched;
    if (matched) {
      const char* suffix = path + i->prefix_len;
      long suffix_len = len - i->prefix_len;
      if (suffix_len == 0) {
        r.args = rb_ary_new3(1, i->id);
        r.controller = i->controller;
        r.scope = i->scope;
        break;
      } else {
        long matched_len = onig_match(i->suffix_re, (const UChar*)suffix, (const UChar*)(suffix + suffix_len),
                                      (const UChar*)suffix, &region, 0);
        if (matched_len > 0) {
          r.args = build_args(suffix, i->conv);
          rb_ary_push(r.args, i->id);
          r.controller = i->controller;
          r.scope = i->scope;
          break;
        }
      }
    }
  }
  return r;
}

static VALUE ext_lookup_route(VALUE self, VALUE method, VALUE path) {
  enum http_method method_num = canonicalize_http_method(method);
  volatile RouteResult r = nyara_lookup_route(method_num, path);
  volatile VALUE a = rb_ary_new();
  rb_ary_push(a, r.scope);
  rb_ary_push(a, r.controller);
  rb_ary_push(a, r.args);
  return a;
}

extern "C"
void Init_route(VALUE nyara, VALUE ext) {
  nyara_http_methods = rb_const_get(nyara, rb_intern("HTTP_METHODS"));
  id_to_s = rb_intern("to_s");
  onig_region_init(&region);

  rb_define_singleton_method(ext, "register_route", RUBY_METHOD_FUNC(ext_register_route), 1);
  rb_define_singleton_method(ext, "clear_route", RUBY_METHOD_FUNC(ext_clear_route), 0);

  // for test
  rb_define_singleton_method(ext, "list_route", RUBY_METHOD_FUNC(ext_list_route), 0);
  rb_define_singleton_method(ext, "lookup_route", RUBY_METHOD_FUNC(ext_lookup_route), 2);
}
