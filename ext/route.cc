#include <ruby.h>
#include <ruby/re.h>
#include "route.h"
#include <vector>
#include "str_intern.h"

struct RouteEntry {
  bool is_sub;
  long prefix_len;
  char* prefix;
  regex_t *suffix;
  VALUE controller;
  ID id;
  VALUE scope;
  std::vector<ID> conv;

  ~RouteEntry() {
    if (prefix) {
      free(prefix);
      prefix = NULL;
    }
    if (suffix) {
      onig_free(suffix);
      suffix = NULL;
    }
  }
};

static std::vector<RouteEntry> route_entries;
static bool initialized = false;
static OnigRegion region; // we can reuse the region without worrying thread safety
static ID id_to_s;

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

extern "C"
VALUE request_clear_route(VALUE req) {
  route_entries.clear();
  return Qnil;
}

extern "C"
VALUE request_register_route(VALUE self, VALUE v_prefix, VALUE v_suffix, VALUE controller, VALUE v_id, VALUE scope, VALUE v_conv) {
  long prefix_len = RSTRING_LEN(v_prefix); 
  char* prefix = (char*)malloc(prefix_len);
  memcpy(prefix, RSTRING_PTR(v_prefix), prefix_len);
  bool is_sub = false;
  if (route_entries.size()) {
    is_sub = start_with(route_entries.rbegin()->prefix, route_entries.rbegin()->prefix_len, prefix, prefix_len);
  }
  regex_t* suffix;
  OnigErrorInfo err_info;
  onig_new(&suffix, (const UChar*)RSTRING_PTR(v_suffix), (const UChar*)(RSTRING_PTR(v_suffix) + RSTRING_LEN(v_suffix)),
           ONIG_OPTION_NONE, ONIG_ENCODING_ASCII, ONIG_SYNTAX_RUBY, &err_info);
  std::vector<ID> _conv;

  RouteEntry e = {
    .is_sub = is_sub,
    .prefix_len = prefix_len,
    .prefix = prefix,
    .suffix = suffix,
    .controller = controller,
    .id = SYM2ID(v_id),
    .scope = scope,
    .conv = _conv
  };

  VALUE* conv_ptr = RARRAY_PTR(v_conv);
  long conv_len = RARRAY_LEN(v_conv);
  for (long i = 0; i < conv_len; i++) {
    ID conv_id = SYM2ID(conv_ptr[i]);
    e.conv.push_back(conv_id);
  }

  route_entries.push_back(e);

  if (!initialized) {
    initialized = true;
    id_to_s = rb_intern("to_s");
    onig_region_init(&region);
  }
  return Qnil;
}

extern "C"
VALUE request_inspect_route(VALUE self) {
  volatile VALUE arr = rb_ary_new();
  volatile VALUE e;
  volatile VALUE prefix;
  volatile VALUE conv;
  for (auto i = route_entries.begin(); i != route_entries.end(); i++) {
    e = rb_ary_new();
    rb_ary_push(e, i->is_sub ? Qtrue : Qfalse);
    rb_ary_push(e, rb_str_new(i->prefix, i->prefix_len));
    // todo suffix
    rb_ary_push(e, i->controller);
    rb_ary_push(e, ID2SYM(i->id));
    rb_ary_push(e, i->scope);
    conv = rb_ary_new();
    for (size_t j = 0; j < i->conv.size(); j++) {
      rb_ary_push(conv, ID2SYM(i->conv[j]));
    }
    rb_ary_push(e, conv);
    rb_ary_push(arr, e);
  }
  return arr;
}

static VALUE build_args(char* suffix, std::vector<ID>& conv) {
  volatile VALUE args = rb_ary_new();
  volatile VALUE str = rb_str_new2("");
  long last_len = 0;
  for (size_t j = 0; j < conv.size(); j++) {
    char* capture_ptr = suffix + region.beg[j+1];
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
RouteResult search_route(VALUE v_pathinfo) {
  char* pathinfo = RSTRING_PTR(v_pathinfo);
  long len = RSTRING_LEN(v_pathinfo);
  RouteResult r = {Qnil, Qnil, Qnil};
  // must iterate all
  bool last_matched = false;
  for (auto i = route_entries.begin(); i != route_entries.end(); ++i) {
    bool matched;
    if (i->is_sub && last_matched) { // save a bit compare
      matched = last_matched;
    } else {
      matched = start_with(pathinfo, len, i->prefix, i->prefix_len);
    }
    last_matched = matched;
    if (matched) {
      char* suffix = pathinfo + i->prefix_len;
      long suffix_len = len - i->prefix_len;
      if (suffix_len == 0) {
        r.args = rb_ary_new();
        r.controller = i->controller;
        r.scope = i->scope;
        break;
      } else {
        long matched_len = onig_match(i->suffix, (const UChar*)suffix, (const UChar*)(suffix + suffix_len),
                                      (const UChar*)suffix, &region, 0);
        if (matched_len > 0) {
          if (region.num_regs - 1 != i->conv.size()) {
            rb_raise(rb_eRuntimeError, "captures=%u but conv size=%lu", region.num_regs - 1, i->conv.size());
          }
          r.args = build_args(suffix, i->conv);
          r.controller = i->controller;
          r.scope = i->scope;
          break;
        }
      }
    }
  }
  return r;
}

extern "C"
VALUE request_search_route(VALUE self, VALUE pathinfo) {
  volatile RouteResult r = search_route(pathinfo);
  volatile VALUE a = rb_ary_new();
  rb_ary_push(a, r.controller);
  rb_ary_push(a, r.args);
  rb_ary_push(a, r.scope);
  return a;
}
