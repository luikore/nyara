/* unify API for epoll and kqueue */

#include "nyara.h"
#include "request.h"
#include <sys/fcntl.h>
#include <sys/socket.h>
#include <errno.h>
#include <stdint.h>
#include <unistd.h>
#include <ruby/st.h>

#define MAX_E 1024
static void loop_body(VALUE rid);
static void loop_check();
static int qfd = 0;
static int tcp_server_fd = 0;
static st_table* handled_rids; // {rid => nil} for current round

#ifdef HAVE_KQUEUE
#include "inc/kqueue.h"
#elif HAVE_EPOLL
#include "inc/epoll.h"
#endif

#ifndef rb_obj_hide
extern VALUE rb_obj_hide(VALUE obj);
extern VALUE rb_obj_reveal(VALUE obj, VALUE klass);
#endif

#define MAX_RECEIVE_DATA 65536 * 2
static char received_data[MAX_RECEIVE_DATA];
extern http_parser_settings nyara_request_parse_settings;

static VALUE rid_request_map;    // {rid(FIXNUM) => request}
static VALUE to_resume_requests; // [request], for current round

static VALUE sym_accept;

// Fiber.yield
static VALUE sym_term_close;
static VALUE sym_writing;
static VALUE sym_reading;
static VALUE sym_sleep;

static Request* curr_request;
static bool graceful_quit = false;

static VALUE _fiber_func(VALUE _, VALUE args) {
  VALUE instance = rb_ary_pop(args);
  VALUE meth = rb_ary_pop(args);
  rb_apply(instance, SYM2ID(meth), args);
  return Qnil;
}

static void _resume_action(Request* p) {
  VALUE state = rb_fiber_resume(p->fiber, 0, NULL);
  if (state == Qnil) { // _fiber_func always returns Qnil
    // terminated (todo log raised error ?)
    nyara_request_term_close(p->self);
  } else if (state == sym_term_close) {
    nyara_request_term_close(p->self);
  } else if (state == sym_writing) {
    // do nothing
  } else if (state == sym_reading) {
    // do nothing
  } else if (state == sym_sleep) {
    // do nothing
  }
}

static void _handle_request(VALUE request) {
  Request* p;
  Data_Get_Struct(request, Request, p);
  if (p->sleeping) {
    return;
  }
  curr_request = p;

  // read and parse data
  // NOTE we don't let http_parser invoke ruby code, because:
  // 1. so the stack is shallower
  // 2. Fiber.yield can pause http_parser, then the unparsed received_data is lost
  long len = read(p->fd, received_data, MAX_RECEIVE_DATA);
  if (len < 0) {
    if (errno != EAGAIN && errno != EWOULDBLOCK) {
      // this can happen when 2 events are fetched, and first event closes the fd, then second event fails
      if (p->fd) {
        nyara_detach_rid(p->rid);
      }
      return;
    }
  } else if (len) {
    // note: for http_parser, len = 0 means eof reached
    //       but when in a fd-becomes-writable event it can also be 0
    http_parser_execute(&(p->hparser), &nyara_request_parse_settings, received_data, len);
  }

  if (!p->parse_state) {
    return;
  }

  // ensure action
  if (p->fiber == Qnil) {
    volatile RouteResult result = nyara_lookup_route(p->method, p->path, p->accept);
    nyara_summary_request(p->method, p->path, result.controller);
    if (RTEST(result.controller)) {
      rb_ary_push(result.args, rb_class_new_instance(1, &(p->self), result.controller));
      // result.args is on stack, no need to worry gc
      p->fiber = rb_fiber_new(_fiber_func, result.args);
      p->instance = RARRAY_PTR(result.args)[RARRAY_LEN(result.args) - 1];
      p->scope = result.scope;
      p->format = result.format;
      p->response_header = rb_class_new_instance(0, NULL, nyara_header_hash_class);
      p->response_header_extra_lines = rb_ary_new();
      nyara_request_init_env(request);
    } else {
      static const char* not_found = "HTTP/1.1 404 Not Found\r\nConnection: close\r\nContent-Length: 0\r\n\r\n";
      static long not_found_len = 0;
      if (!not_found_len) {
        not_found_len = strlen(not_found);
      }
      nyara_send_data(p->fd, not_found, not_found_len);
      nyara_detach_rid(p->rid);
      return;
    }
  }

  _resume_action(p);
}

// platform independent, invoked by LOOP_E()
static void loop_body(VALUE rid) {
  if (rid == sym_accept) {
    int cfd = accept(tcp_server_fd, NULL, NULL);
    if (cfd > 0) {
      nyara_set_nonblock(cfd);
      Request* p = nyara_request_new(cfd);
      rb_hash_aset(rid_request_map, p->rid, p->self);
      ADD_E(cfd, p->rid);
    }
  } else {
    // epoll_wait can return multiple results on a same request,
    // and this request may be closed at previous round.
    if (st_lookup(handled_rids, rid, NULL)) {
      return;
    }
    st_insert(handled_rids, rid, Qnil);

    VALUE request = rb_hash_aref(rid_request_map, rid);
    if (request != Qnil) {
      _handle_request(request);
    }
  }
}

static void loop_check() {
  // execute other thread / interrupts
  rb_thread_schedule();

  // wakeup actions which finished sleeping
  long len = RARRAY_LEN(to_resume_requests);
  if (len) {
    VALUE* ptr = RARRAY_PTR(to_resume_requests);
    for (long i = 0; i < len; i++) {
      VALUE request = ptr[i];
      Request* p;
      Data_Get_Struct(request, Request, p);

      p->sleeping = false;
      if (!rb_fiber_alive_p(p->fiber) || !p->fd) { // do not wake dead requests
        continue;
      }

      _resume_action(p);
      if (qfd) {
        // printf("%s\n", "no way!");
        // _Exit(1);
        VALUE* v_fds = RARRAY_PTR(p->watched_fds);
        long v_fds_len = RARRAY_LEN(p->watched_fds);
        for (long i = 0; i < v_fds_len; i++) {
          ADD_E(FIX2INT(v_fds[i]), p->rid);
        }
        ADD_E(p->fd, p->rid);
      } else {
        // we are in a test, no queue
      }
    }

    rb_ary_clear(to_resume_requests);
  }

  if (graceful_quit) {
    if (RTEST(rb_funcall(rid_request_map, rb_intern("empty?"), 0))) {
      _Exit(0);
    }
  }
}

void nyara_detach_rid(VALUE rid) {
  VALUE request = rb_hash_delete(rid_request_map, rid);
  if (request != Qnil) {
    Request* p;
    Data_Get_Struct(request, Request, p);
    VALUE* watched = RARRAY_PTR(p->watched_fds);
    long watched_len = RARRAY_LEN(p->watched_fds);
    for (long i = 0; i < watched_len; i++) {
      close(NUM2INT(watched[i]));
    }
    if (p->fd) {
      close(p->fd);
      p->fd = 0;
    }
  }
}

static VALUE ext_init_queue(VALUE _) {
  INIT_E();
  return Qnil;
}

// run queue loop with server_fd
static VALUE ext_run_queue(VALUE _, VALUE v_server_fd) {
  tcp_server_fd = FIX2INT(v_server_fd);
  nyara_set_nonblock(tcp_server_fd);
  ADD_E(tcp_server_fd, sym_accept);

  LOOP_E();
  return Qnil;
}

// set graceful quit flag and do not accept server_fd anymore
static VALUE ext_graceful_quit(VALUE _, VALUE v_server_fd) {
  graceful_quit = true;
  int fd = FIX2INT(v_server_fd);
  DEL_E(fd);
  return Qnil;
}

// put request into sleep
static VALUE ext_request_sleep(VALUE _, VALUE request) {
  Request* p;
  Data_Get_Struct(request, Request, p);

  p->sleeping = true;
  if (!qfd) {
    // we are in a test
    return Qnil;
  }

  VALUE* v_fds = RARRAY_PTR(p->watched_fds);
  long v_fds_len = RARRAY_LEN(p->watched_fds);
  for (long i = 0; i < v_fds_len; i++) {
    DEL_E(FIX2INT(v_fds[i]));
  }
  DEL_E(p->fd);
  return Qnil;
}

// NOTE this will be executed in another thread, resuming fiber in a non-main thread will stuck
static VALUE ext_request_wakeup(VALUE _, VALUE request) {
  // NOTE should not use curr_request
  rb_ary_push(to_resume_requests, request);
  return Qnil;
}

static VALUE ext_set_nonblock(VALUE _, VALUE v_fd) {
  int fd = FIX2INT(v_fd);
  nyara_set_nonblock(fd);
  return Qnil;
}

static VALUE ext_fd_watch(VALUE _, VALUE v_fd) {
  int fd = NUM2INT(v_fd);
  rb_ary_push(curr_request->watched_fds, v_fd);
  ADD_E(fd, curr_request->rid);
  return Qnil;
}

static VALUE ext_fd_unwatch(VALUE _, VALUE v_fd) {
  int fd = NUM2INT(v_fd);
  rb_ary_delete(curr_request->watched_fds, v_fd);
  DEL_E(fd);
  return Qnil;
}

// override TCPSocket.send
// returns sent length
static VALUE ext_fd_send(VALUE _, VALUE v_fd, VALUE v_data, VALUE v_flags) {
  int flags = NUM2INT(v_flags);
  int fd = NUM2INT(v_fd);
  char* buf = RSTRING_PTR(v_data);
  long len = RSTRING_LEN(v_data);

  // similar to _send_data in request.c
  while(len) {
    long written = send(fd, buf, len, flags);
    if (written <= 0) {
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        rb_fiber_yield(1, &sym_writing);
        continue;
      } else {
        rb_sys_fail("send(2)");
        break;
      }
    } else {
      buf += written;
      len -= written;
      if (len) {
        rb_fiber_yield(1, &sym_writing);
      }
    }
  }

  return LONG2NUM(RSTRING_LEN(v_data) - len);
}

// override TCPSocket.recv
// simulate blocking recv len or eof
static VALUE ext_fd_recv(VALUE _, VALUE v_fd, VALUE v_len, VALUE v_flags) {
  int flags = NUM2INT(v_flags);
  int fd = NUM2INT(v_fd);
  long buf_len = NUM2INT(v_len); // int shall be large enough...

  volatile VALUE str = rb_tainted_str_new(0, buf_len);
  volatile VALUE klass = RBASIC(str)->klass;
  rb_obj_hide(str);

  char* s = RSTRING_PTR(str);
  while(buf_len) {
    long recved = recv(fd, s, buf_len, flags);
    if (recved < 0) {
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        rb_fiber_yield(1, &sym_reading);
        continue;
      } else {
        rb_sys_fail("recv(2)");
        break;
      }
    } else if (recved == 0) { // reached EOF
      break;
    }
    s += recved;
    buf_len -= recved;
  }

  if (RBASIC(str)->klass || RSTRING_LEN(str) != NUM2INT(v_len)) {
    rb_raise(rb_eRuntimeError, "buffer string modified");
  }
  rb_obj_reveal(str, klass);
  if (buf_len) {
    rb_str_set_len(str, RSTRING_LEN(str) - buf_len);
  }
  rb_obj_taint(str);

  return str;
}

// (for test) run request handler, read from associated fd and write to it
static VALUE ext_handle_request(VALUE _, VALUE request) {
  Request* p;
  Data_Get_Struct(request, Request, p);

  while (p->fiber == Qnil || rb_fiber_alive_p(p->fiber)) {
    _handle_request(request);
    // stop if no more to read
    // NOTE this condition is sufficient to terminate handle, because
    // - there's no connect yield during test
    // - there's no view pause yield up to _handle_request
    if (!p->sleeping) {
      char buf[1];
      if (recv(p->fd, buf, 1, MSG_PEEK) <= 0) {
        break;
      }
    }
  }
  return p->instance;
}

void Init_event(VALUE ext) {
  rid_request_map = rb_hash_new();
  rb_gc_register_mark_object(rid_request_map);
  handled_rids = st_init_numtable();
  to_resume_requests = rb_ary_new();
  rb_gc_register_mark_object(to_resume_requests);

  sym_accept = ID2SYM(rb_intern("accept"));
  sym_term_close = ID2SYM(rb_intern("term_close"));
  sym_writing = ID2SYM(rb_intern("writing"));
  sym_reading = ID2SYM(rb_intern("reading"));
  sym_sleep = ID2SYM(rb_intern("sleep"));

  rb_define_singleton_method(ext, "init_queue", ext_init_queue, 0);
  rb_define_singleton_method(ext, "run_queue", ext_run_queue, 1);
  rb_define_singleton_method(ext, "graceful_quit", ext_graceful_quit, 1);

  rb_define_singleton_method(ext, "request_sleep", ext_request_sleep, 1);
  rb_define_singleton_method(ext, "request_wakeup", ext_request_wakeup, 1);

  // fd operations
  rb_define_singleton_method(ext, "set_nonblock", ext_set_nonblock, 1);
  rb_define_singleton_method(ext, "fd_watch", ext_fd_watch, 1);
  rb_define_singleton_method(ext, "fd_unwatch", ext_fd_unwatch, 1);
  rb_define_singleton_method(ext, "fd_send", ext_fd_send, 3);
  rb_define_singleton_method(ext, "fd_recv", ext_fd_recv, 3);

  // for test
  rb_define_singleton_method(ext, "handle_request", ext_handle_request, 1);
}
